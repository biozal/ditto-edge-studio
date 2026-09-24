package com.costoda.dittoedgestudio.util

import com.costoda.dittoedgestudio.domain.model.AuthMode
import com.costoda.dittoedgestudio.domain.model.DittoDatabase
import com.costoda.dittoedgestudio.domain.model.DittoSubscription
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Cross-platform wire-format parity: what THIS app emits must be decodable by the Apple app.
 *
 * These assert on real encoder output. The tests that existed before hand-wrote fixture JSON
 * (`"_id": ""`, `{"version":1,…}`) and round-tripped Android→Android through the same tolerant
 * kotlinx model, so they could not see that kotlinx was dropping keys Swift decodes with a
 * plain, non-optional `decode`. Asserting on the encoder is the whole point.
 */
class QrCrossPlatformParityTest {

    private fun database() = DittoDatabase(
        id = 1L,
        name = "Prod",
        databaseId = "abc123",
        token = "token",
        authUrl = "https://x.cloud.dittolive.app",
        websocketUrl = "",
        httpApiUrl = "https://x.cloud.dittolive.app",
        httpApiKey = "key",
        mode = AuthMode.SERVER,
        allowUntrustedCerts = false,
        secretKey = "",
    )

    // MARK: - Database config QR

    @Test
    fun `encoded config JSON carries _id, which Swift decodes non-optionally`() {
        val payload = QrCodeEncoder.buildPayloadForTest(database(), favorites = emptyList())

        val json = QrCodeEncoder.encodePayloadJson(payload)

        // Swift: `_id = try container.decode(String.self, forKey: ._id)` — a plain decode
        // with no LegacyCodingKeys alias, so a missing key throws keyNotFound and
        // QRCodeGenerator.decode swallows it with `try?`, returning nil.
        assertTrue("encoded config must contain \"_id\": $json", json.contains("\"_id\""))
    }

    @Test
    fun `encoded config JSON carries favorites even when the sender has none`() {
        val payload = QrCodeEncoder.buildPayloadForTest(database(), favorites = emptyList())

        val json = QrCodeEncoder.encodePayloadJson(payload)

        // Swift: `let favorites: [FavoriteQueryItem]` is non-optional, so its synthesized
        // decoder also calls decode(_:forKey:) and throws on an absent key.
        assertTrue("encoded config must contain \"favorites\": $json", json.contains("\"favorites\""))
    }

    // MARK: - Subscriptions QR

    @Test
    fun `encoded subscriptions JSON carries version, which Swift decodes non-optionally`() {
        val subs = listOf(DittoSubscription(id = 1L, name = "All orders", query = "SELECT * FROM orders"))

        val json = SubscriptionsQrCodec.encodePayloadJson(subs)

        // Swift: `struct SubscriptionsQRPayload { let version: Int; … }`
        assertTrue("encoded subscriptions must contain \"version\": $json", json!!.contains("\"version\""))
        assertTrue(json.contains("\"subscriptions\""))
    }

    @Test
    fun `empty subscription list still encodes to null`() {
        assertEquals(null, SubscriptionsQrCodec.encodePayloadJson(emptyList()))
    }

    // MARK: - AuthMode spelling drift

    @Test
    fun `Apple's smallPeerOnly raw value imports as Small Peers Only, not Server`() {
        // The Apple app encodes AuthMode as the SDK-5 raw value "smallPeerOnly". Falling
        // through to the silent `?: SERVER` default turned an offline database into a
        // cloud-connecting one, which then fails DittoManager's token/authUrl requirement.
        assertEquals(AuthMode.SMALL_PEERS_ONLY, AuthMode.fromValue("smallPeerOnly"))
    }

    @Test
    fun `small peers only spelling is matched case-insensitively`() {
        assertEquals(AuthMode.SMALL_PEERS_ONLY, AuthMode.fromValue("SmallPeersOnly"))
        assertEquals(AuthMode.SMALL_PEERS_ONLY, AuthMode.fromValue("smallpeersonly"))
        assertEquals(AuthMode.SMALL_PEERS_ONLY, AuthMode.fromValue("  smallPeerOnly  "))
    }

    @Test
    fun `server spelling still resolves and unknown values still default to server`() {
        assertEquals(AuthMode.SERVER, AuthMode.fromValue("server"))
        assertEquals(AuthMode.SERVER, AuthMode.fromValue("Server"))
        assertEquals(AuthMode.SERVER, AuthMode.fromValue("something-unrecognized"))
    }
}
