package com.costoda.dittoedgestudio.util

import android.util.Base64
import com.costoda.dittoedgestudio.domain.model.DittoSubscription
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.util.zip.Deflater

/**
 * Cross-platform payload codec for bulk subscription sharing
 * (parity with SwiftUI `QRCodeGenerator.encodeSubscriptions`/`decodeSubscriptions`).
 *
 * Wire format: `"EDS_SUBS1:" + base64(zlib(json))` where the JSON is
 * `{ "version": 1, "subscriptions": [ { "name": ..., "query": ..., "args": ...? } ] }`.
 * Swift, iPad, this app, and the VS Code extension can all scan each other's codes.
 */
object SubscriptionsQrCodec {

    const val PREFIX = "EDS_SUBS1:"

    @Serializable
    data class Item(
        val name: String,
        val query: String,
        val args: String? = null,
    )

    @Serializable
    private data class Payload(
        val version: Int = 1,
        val subscriptions: List<Item>,
    )

    // encodeDefaults = true is REQUIRED for cross-platform parity, not a preference.
    // kotlinx skips any property whose value equals its declared default, so `version`
    // (declared `= 1`) was never written and the emitted JSON was
    // `{"subscriptions":[...]}` — while Swift's `SubscriptionsQRPayload.version` is a
    // non-optional `Int`, so its synthesized decoder threw `keyNotFound` and
    // `decodeSubscriptions` swallowed it with `try?`. Apple devices silently could not
    // scan subscription codes produced here, contradicting this file's own header.
    private val json = Json {
        ignoreUnknownKeys = true
        encodeDefaults = true
    }

    /**
     * The JSON step of [encode], separated so tests can assert on what this codec really
     * emits. The previous test hand-wrote `{"version":1,…}` rather than asserting on
     * encoder output, which is why the missing `version` key shipped.
     */
    internal fun encodePayloadJson(subscriptions: List<DittoSubscription>): String? {
        if (subscriptions.isEmpty()) return null
        val items = subscriptions.map {
            Item(
                name = it.name.ifBlank { "Unnamed subscription" },
                query = it.query,
                args = null,
            )
        }
        return json.encodeToString(Payload(subscriptions = items))
    }

    fun encode(subscriptions: List<DittoSubscription>): String? {
        return try {
            val jsonString = encodePayloadJson(subscriptions) ?: return null
            val bytes = jsonString.toByteArray(Charsets.UTF_8)
            val deflater = Deflater(Deflater.DEFAULT_COMPRESSION, false) // RFC 1950, matches iOS
            deflater.setInput(bytes)
            deflater.finish()
            val output = ByteArray(bytes.size * 2 + 100)
            val length = deflater.deflate(output)
            deflater.end()
            PREFIX + Base64.encodeToString(output.copyOf(length), Base64.NO_WRAP)
        } catch (_: Exception) {
            null
        }
    }

    /** Returns null when the payload isn't an EDS_SUBS1 code or fails to decode. */
    fun decode(payload: String): List<Item>? {
        if (!payload.startsWith(PREFIX)) return null
        return try {
            val compressed = Base64.decode(payload.removePrefix(PREFIX), Base64.DEFAULT)
            val jsonString = String(QrCodeDecoder.decompressZlib(compressed), Charsets.UTF_8)
            json.decodeFromString<Payload>(jsonString).subscriptions
        } catch (_: Exception) {
            null
        }
    }
}
