package com.costoda.dittoedgestudio.util

import android.graphics.Bitmap
import android.util.Base64
import com.costoda.dittoedgestudio.domain.model.AuthMode
import com.costoda.dittoedgestudio.domain.model.DittoDatabase
import com.costoda.dittoedgestudio.domain.model.QrCodePayload
import com.costoda.dittoedgestudio.domain.model.QrConfigPayload
import com.costoda.dittoedgestudio.domain.model.QrFavoriteItem
import io.mockk.every
import io.mockk.mockkStatic
import io.mockk.unmockkStatic
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import org.junit.After
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.util.zip.Deflater

/**
 * Unit tests for [QrCodeEncoder].
 *
 * android.util.Base64 and android.graphics.Bitmap are mocked for JVM unit tests.
 * QrCodeEncoder.encode() is tested directly using mocked Bitmap.createBitmap.
 */
class QrCodeEncoderTest {

    private val minimalDatabase = DittoDatabase(
        id = 0,
        name = "Test DB",
        databaseId = "test-db-001",
        token = "tok_test",
        authUrl = "https://auth.example.com",
        websocketUrl = "wss://ws.example.com",
        httpApiUrl = "https://api.example.com",
        httpApiKey = "key_test",
        mode = AuthMode.SERVER,
        allowUntrustedCerts = false,
        secretKey = "",
        isBluetoothLeEnabled = true,
        isLanEnabled = true,
        isAwdlEnabled = false,
        isCloudSyncEnabled = true,
        logLevel = "info",
        isStrictModeEnabled = false,
    )

    @Before
    fun setup() {
        mockkStatic(Base64::class)
        every { Base64.encodeToString(any(), any()) } answers {
            java.util.Base64.getEncoder().encodeToString(firstArg<ByteArray>())
        }
        every { Base64.decode(any<String>(), any()) } answers {
            java.util.Base64.getDecoder().decode(firstArg<String>())
        }
        mockkStatic(Bitmap::class)
        every { Bitmap.createBitmap(any<IntArray>(), any(), any(), any()) } returns
            io.mockk.mockk<Bitmap>(relaxed = true)
    }

    @After
    fun teardown() {
        unmockkStatic(Base64::class)
        unmockkStatic(Bitmap::class)
    }

    // ─── Helpers ────────────────────────────────────────────────────────────────

    /**
     * Generates a pseudo-random string of [length] alphanumeric chars using a fixed-seed LCG.
     * The output is deterministic and resists zlib compression (high entropy, fixed seed).
     */
    private fun pseudoRandomString(length: Int, seed: Long = 0xDEADBEEFL): String {
        val chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
        val rng = java.util.Random(seed)
        return (1..length).map { chars[rng.nextInt(chars.length)] }.joinToString("")
    }

    /**
     * Encodes a [DittoDatabase] + favorites to an EDS2 string (bypasses Bitmap rendering),
     * using the same logic as QrCodeEncoder internals. Returns null if > 2200 bytes.
     */
    private fun encodeToEds2String(database: DittoDatabase, favorites: List<String>): String? {
        val json = Json { }
        val payload = QrCodePayload(
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
                isStrictModeEnabled = database.isStrictModeEnabled,
            ),
            favorites = favorites.map { QrFavoriteItem(it) },
        )
        return try {
            val jsonString = json.encodeToString(payload)
            val bytes = jsonString.toByteArray(Charsets.UTF_8)
            val deflater = Deflater(Deflater.DEFAULT_COMPRESSION, false)
            deflater.setInput(bytes)
            deflater.finish()
            val output = ByteArray(bytes.size * 2 + 100)
            val length = deflater.deflate(output)
            deflater.end()
            val compressed = output.copyOf(length)
            val encoded = "EDS2:" + java.util.Base64.getEncoder().encodeToString(compressed)
            if (encoded.length > 2200) null else encoded
        } catch (_: Exception) {
            null
        }
    }

    // ─── Codec tests (encode/decode round-trip via encodeToEds2String) ───────────

    @Test
    fun `encode produces EDS2 prefix`() {
        val result = encodeToEds2String(minimalDatabase, emptyList())

        assertNotNull(result)
        assertTrue("Expected EDS2: prefix but got: $result", result!!.startsWith("EDS2:"))
    }

    @Test
    fun `encode and decode round-trip preserves all 16 database fields`() {
        val result = encodeToEds2String(minimalDatabase, emptyList())

        assertNotNull(result)
        val decoded = QrCodeDecoder.decode(result!!)
        assertNotNull(decoded)
        val db = decoded!!.database

        assertTrue(db.name == minimalDatabase.name)
        assertTrue(db.databaseId == minimalDatabase.databaseId)
        assertTrue(db.token == minimalDatabase.token)
        assertTrue(db.authUrl == minimalDatabase.authUrl)
        assertTrue(db.websocketUrl == minimalDatabase.websocketUrl)
        assertTrue(db.httpApiUrl == minimalDatabase.httpApiUrl)
        assertTrue(db.httpApiKey == minimalDatabase.httpApiKey)
        assertTrue(db.mode == minimalDatabase.mode)
        assertTrue(db.allowUntrustedCerts == minimalDatabase.allowUntrustedCerts)
        assertTrue(db.secretKey == minimalDatabase.secretKey)
        assertTrue(db.isBluetoothLeEnabled == minimalDatabase.isBluetoothLeEnabled)
        assertTrue(db.isLanEnabled == minimalDatabase.isLanEnabled)
        assertTrue(db.isAwdlEnabled == minimalDatabase.isAwdlEnabled)
        assertTrue(db.isCloudSyncEnabled == minimalDatabase.isCloudSyncEnabled)
        assertTrue(db.logLevel == minimalDatabase.logLevel)
        assertTrue(db.isStrictModeEnabled == minimalDatabase.isStrictModeEnabled)
    }

    @Test
    fun `roundTripPreservesStrictModeEnabled`() {
        val dbWithStrictMode = minimalDatabase.copy(isStrictModeEnabled = true)
        val result = encodeToEds2String(dbWithStrictMode, emptyList())

        assertNotNull(result)
        val decoded = QrCodeDecoder.decode(result!!)
        assertNotNull(decoded)
        assertTrue(decoded!!.database.isStrictModeEnabled)
    }

    // ─── Edge-case tests (use QrCodeEncoder.encode() with mocked Bitmap) ────────

    @Test
    fun `encode drops favorites when payload exceeds 2200 bytes`() {
        // minimalDatabase encodes to ~300 bytes (well under 2200)
        // 100 unique favorites push the combined payload over 2200 bytes
        val largeFavorites = (1..100).map { i ->
            "SELECT * FROM collection_$i WHERE field_name = 'some_filter_value_for_item_$i'"
        }

        val result = QrCodeEncoder.encode(minimalDatabase, largeFavorites)

        // Favorites were dropped to fit under 2200 bytes → bitmap returned
        assertNotNull(result)
    }

    @Test
    fun `encode returns null when config alone exceeds 2200 bytes`() {
        // Use pseudo-random (high-entropy) string fields so zlib cannot compress below 2200 bytes.
        // 3000 pseudo-random alphanumeric chars in the token field:
        // information-theoretic lower bound = 3000 × log2(62)/8 ≈ 2231 bytes compressed,
        // which as base64 + EDS2: prefix ≈ 2980 chars >> 2200.
        val massiveDatabase = minimalDatabase.copy(
            token = pseudoRandomString(3000, seed = 0xDEADBEEFL),
        )

        val result = QrCodeEncoder.encode(massiveDatabase, emptyList())

        assertNull(result)
    }
}
