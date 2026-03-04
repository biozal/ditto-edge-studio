package com.costoda.dittoedgestudio.util

import android.graphics.Bitmap
import android.graphics.Color
import android.util.Base64
import com.costoda.dittoedgestudio.domain.model.DittoDatabase
import com.costoda.dittoedgestudio.domain.model.QrCodePayload
import com.costoda.dittoedgestudio.domain.model.QrConfigPayload
import com.costoda.dittoedgestudio.domain.model.QrFavoriteItem
import com.google.zxing.BarcodeFormat
import com.google.zxing.EncodeHintType
import com.google.zxing.qrcode.QRCodeWriter
import com.google.zxing.qrcode.decoder.ErrorCorrectionLevel
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.util.zip.Deflater

private const val MAX_PAYLOAD_BYTES = 2200
private const val QR_SIZE_PX = 512

object QrCodeEncoder {

    private val json = Json { }

    /**
     * Encodes a [DittoDatabase] (and optional favorites) into an EDS2 QR code [Bitmap].
     *
     * If the encoded payload would exceed 2200 bytes, favorites are dropped and encoding
     * is retried. Returns null if even the config alone exceeds the limit.
     */
    fun encode(database: DittoDatabase, favorites: List<String>): Bitmap? {
        val payload = buildPayload(database, favorites)
        val encoded = encodeToEds2(payload) ?: return null
        if (encoded.length > MAX_PAYLOAD_BYTES) {
            val payloadNoFavorites = buildPayload(database, emptyList())
            val encodedNoFavorites = encodeToEds2(payloadNoFavorites) ?: return null
            if (encodedNoFavorites.length > MAX_PAYLOAD_BYTES) return null
            return renderQrBitmap(encodedNoFavorites)
        }
        return renderQrBitmap(encoded)
    }

    private fun buildPayload(database: DittoDatabase, favorites: List<String>): QrCodePayload {
        return QrCodePayload(
            version = 2,
            config = QrConfigPayload(
                id = "",
                name = database.name,
                databaseId = database.databaseId,
                token = database.token,
                authUrl = database.authUrl,
                websocketUrl = database.websocketUrl,
                httpApiUrl = database.httpApiUrl,
                httpApiKey = database.httpApiKey,
                mode = database.mode.value,
                allowUntrustedCerts = database.allowUntrustedCerts,
                secretKey = database.secretKey,
                isBluetoothLeEnabled = database.isBluetoothLeEnabled,
                isLanEnabled = database.isLanEnabled,
                isAwdlEnabled = database.isAwdlEnabled,
                isCloudSyncEnabled = database.isCloudSyncEnabled,
                logLevel = database.logLevel,
            ),
            favorites = favorites.map { QrFavoriteItem(it) },
        )
    }

    private fun encodeToEds2(payload: QrCodePayload): String? {
        return try {
            val jsonString = json.encodeToString(payload)
            val bytes = jsonString.toByteArray(Charsets.UTF_8)
            val deflater = Deflater(Deflater.DEFAULT_COMPRESSION, false) // nowrap=false = RFC 1950
            deflater.setInput(bytes)
            deflater.finish()
            val output = ByteArray(bytes.size * 2 + 100)
            val length = deflater.deflate(output)
            deflater.end()
            val compressed = output.copyOf(length)
            "EDS2:" + Base64.encodeToString(compressed, Base64.NO_WRAP)
        } catch (_: Exception) {
            null
        }
    }

    private fun renderQrBitmap(content: String): Bitmap? {
        return try {
            val hints = mapOf(
                EncodeHintType.ERROR_CORRECTION to ErrorCorrectionLevel.M,
                EncodeHintType.MARGIN to 1,
            )
            val bitMatrix = QRCodeWriter().encode(
                content, BarcodeFormat.QR_CODE, QR_SIZE_PX, QR_SIZE_PX, hints,
            )
            val width = bitMatrix.width
            val height = bitMatrix.height
            val pixels = IntArray(width * height) { i ->
                val x = i % width
                val y = i / width
                if (bitMatrix[x, y]) Color.BLACK else Color.WHITE
            }
            Bitmap.createBitmap(pixels, width, height, Bitmap.Config.ARGB_8888)
        } catch (_: Exception) {
            null
        }
    }
}
