package com.costoda.dittoedgestudio.util

import android.util.Base64
import android.util.Log
import com.costoda.dittoedgestudio.BuildConfig
import com.costoda.dittoedgestudio.domain.model.AuthMode
import com.costoda.dittoedgestudio.domain.model.DittoDatabase
import com.costoda.dittoedgestudio.domain.model.MulticastConfig
import com.costoda.dittoedgestudio.domain.model.QrCodePayload
import com.costoda.dittoedgestudio.domain.model.QrConfigPayload
import kotlinx.serialization.json.Json
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.util.zip.Inflater
import java.util.zip.InflaterInputStream
import java.util.zip.ZipException

private const val TAG = "QrCodeDecoder"

/**
 * Hard cap on decompressed QR payload size. A real EDS2 payload is a small config
 * JSON (QR v40 tops out at ~3 KB raw); anything past 1 MB decompressed is a hostile
 * zip-bomb, not a config.
 */
private const val MAX_DECOMPRESSED_BYTES = 1_048_576 // 1 MB

/** Thrown when a compressed QR payload inflates past [MAX_DECOMPRESSED_BYTES]. */
internal class QrPayloadTooLargeException(message: String) : Exception(message)

object QrCodeDecoder {

    private val json = Json {
        ignoreUnknownKeys = true
        coerceInputValues = true
    }

    /**
     * Decodes a QR code string into a [QrImportResult].
     *
     * Supports:
     * - EDS2 (v2): `EDS2:` prefix + Base64(zlib-compressed JSON)
     * - Legacy (v1): raw JSON with no prefix
     *
     * Returns null if the input is not a valid database config QR.
     */
    fun decode(rawText: String): QrImportResult? {
        return try {
            if (rawText.startsWith("EDS2:")) {
                decodeV2(rawText.removePrefix("EDS2:"))
            } else {
                decodeV1(rawText)
            }
        } catch (e: Exception) {
            // Gated: SerializationException messages can embed fragments of the
            // decoded config JSON (tokens/keys) — never write those to release logcat.
            if (BuildConfig.DEBUG) {
                Log.e(TAG, "QR decode failed: ${e.javaClass.simpleName}: ${e.message}", e)
            }
            null
        }
    }

    private fun decodeV2(base64Data: String): QrImportResult? {
        val compressed = Base64.decode(base64Data, Base64.DEFAULT)
        if (BuildConfig.DEBUG) {
            Log.d(TAG, "decodeV2: compressed size=${compressed.size}, header=${compressed.take(4).joinToString { "0x%02X".format(it) }}")
        }
        val jsonBytes = decompressZlib(compressed)
        val jsonString = String(jsonBytes, Charsets.UTF_8)
        val payload = json.decodeFromString<QrCodePayload>(jsonString)
        return payload.toImportResult()
    }

    /**
     * Decompresses zlib data with cross-platform fallback.
     *
     * Tries RFC 1950 (zlib wrapper with 2-byte header + Adler-32) first — the format
     * produced by Android's Deflater(nowrap=false) and documented for Apple's
     * NSData.compressed(using: .zlib). Falls back to raw DEFLATE (RFC 1951, no header)
     * if the header check fails, to handle platform-specific compression variants.
     */
    internal fun decompressZlib(data: ByteArray): ByteArray {
        return try {
            InflaterInputStream(ByteArrayInputStream(data)).use { it.readBounded() }
        } catch (e: ZipException) {
            if (BuildConfig.DEBUG) {
                Log.d(TAG, "RFC 1950 inflate failed (${e.message}), retrying as raw DEFLATE")
            }
            InflaterInputStream(ByteArrayInputStream(data), Inflater(true)).use { it.readBounded() }
        }
    }

    /**
     * Reads the stream fully, refusing to inflate past [MAX_DECOMPRESSED_BYTES].
     * Throws [QrPayloadTooLargeException] (not [ZipException]) so the oversized
     * payload is rejected outright instead of being retried by the raw-DEFLATE
     * fallback in [decompressZlib].
     */
    private fun InputStream.readBounded(): ByteArray {
        val out = ByteArrayOutputStream()
        val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
        while (true) {
            val read = read(buffer)
            if (read < 0) break
            if (out.size() + read > MAX_DECOMPRESSED_BYTES) {
                throw QrPayloadTooLargeException(
                    "Decompressed QR payload exceeds $MAX_DECOMPRESSED_BYTES bytes",
                )
            }
            out.write(buffer, 0, read)
        }
        return out.toByteArray()
    }

    private fun decodeV1(rawJson: String): QrImportResult? {
        val config = json.decodeFromString<QrConfigPayload>(rawJson)
        return QrImportResult(
            database = config.toDittoDatabase(),
            favorites = emptyList(),
        )
    }

    private fun QrCodePayload.toImportResult() = QrImportResult(
        database = config.toDittoDatabase(),
        favorites = favorites.map { it.q },
    )

    private fun QrConfigPayload.toDittoDatabase(): DittoDatabase {
        // Minimal validation: a config without a name or databaseId is malformed —
        // fail the decode here with a clear error rather than deferring to a
        // downstream require() at save/open time.
        require(name.isNotBlank()) { "QR config is missing a database name" }
        require(databaseId.isNotBlank()) { "QR config is missing a databaseId" }
        // Multicast validation at the decode boundary (the UI path enforces the
        // same rules via MulticastConfig): the group address must be class-D
        // (224-239) and the port in 1..65535. DittoManager coerces the port with
        // toUShort() — 0 becomes the SDK's broken "any port" sentinel and 70000
        // silently truncates to 4464 — so an invalid QR must never reach
        // Room/the SDK. Sanitize deterministically and UNCONDITIONALLY — garbage
        // in a disabled config would otherwise persist and be applied into the
        // disabled multicastBeta block. The enabled flag only flips off when the
        // config was enabled AND invalid. The group address is trimmed here too:
        // isValidGroupAddress trims before validating, so the stored value must
        // be the trimmed one or a padded address would validate but persist dirty.
        val multicastInvalid =
            !MulticastConfig.isValidGroupAddress(multicastGroupAddress) || multicastPort !in 1..65535
        return DittoDatabase(
            name = name,
            databaseId = databaseId,
            token = token,
            authUrl = authUrl,
            websocketUrl = websocketUrl,
            httpApiUrl = httpApiUrl,
            httpApiKey = httpApiKey,
            mode = AuthMode.fromValue(mode),
            allowUntrustedCerts = allowUntrustedCerts,
            secretKey = secretKey,
            isBluetoothLeEnabled = isBluetoothLeEnabled,
            isLanEnabled = isLanEnabled,
            isAwdlEnabled = isAwdlEnabled,
            isCloudSyncEnabled = isCloudSyncEnabled,
            isMulticastEnabled = isMulticastEnabled && !multicastInvalid,
            multicastGroupAddress = if (multicastInvalid) {
                MulticastConfig.DEFAULT_GROUP_ADDRESS
            } else {
                multicastGroupAddress.trim()
            },
            multicastPort = if (multicastInvalid) MulticastConfig.DEFAULT_PORT else multicastPort,
            multicastInterfaceName = if (multicastInvalid) null else multicastInterfaceName,
            logLevel = logLevel,
            isStrictModeEnabled = isStrictModeEnabled,
        )
    }
}
