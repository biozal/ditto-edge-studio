package com.costoda.dittoedgestudio.util

import android.util.Base64
import android.util.Log
import com.costoda.dittoedgestudio.domain.model.AuthMode
import com.costoda.dittoedgestudio.domain.model.DittoDatabase
import com.costoda.dittoedgestudio.domain.model.QrCodePayload
import com.costoda.dittoedgestudio.domain.model.QrConfigPayload
import kotlinx.serialization.json.Json
import java.io.ByteArrayInputStream
import java.util.zip.Inflater
import java.util.zip.InflaterInputStream
import java.util.zip.ZipException

private const val TAG = "QrCodeDecoder"

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
            Log.e(TAG, "QR decode failed: ${e.javaClass.simpleName}: ${e.message}", e)
            null
        }
    }

    private fun decodeV2(base64Data: String): QrImportResult? {
        val compressed = Base64.decode(base64Data, Base64.DEFAULT)
        Log.d(TAG, "decodeV2: compressed size=${compressed.size}, header=${compressed.take(4).joinToString { "0x%02X".format(it) }}")
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
            InflaterInputStream(ByteArrayInputStream(data)).use { it.readBytes() }
        } catch (e: ZipException) {
            Log.d(TAG, "RFC 1950 inflate failed (${e.message}), retrying as raw DEFLATE")
            InflaterInputStream(ByteArrayInputStream(data), Inflater(true)).use { it.readBytes() }
        }
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

    private fun QrConfigPayload.toDittoDatabase() = DittoDatabase(
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
        logLevel = logLevel,
        isStrictModeEnabled = isStrictModeEnabled,
    )
}
