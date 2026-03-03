package com.costoda.dittoedgestudio.util

import android.util.Base64
import com.costoda.dittoedgestudio.domain.model.AuthMode
import io.mockk.every
import io.mockk.mockkStatic
import io.mockk.unmockkStatic
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.util.zip.Deflater
import java.util.zip.Inflater

/**
 * Unit tests for [QrCodeDecoder].
 *
 * android.util.Base64 is mocked using MockK's mockkStatic to run without an Android runtime.
 */
class QrCodeDecoderTest {

    @Before
    fun setup() {
        mockkStatic(Base64::class)
        // Route android Base64 to java.util.Base64 for JVM unit tests
        every { Base64.decode(any<String>(), any()) } answers {
            java.util.Base64.getDecoder().decode(firstArg<String>())
        }
        every { Base64.encodeToString(any(), any()) } answers {
            java.util.Base64.getEncoder().encodeToString(firstArg<ByteArray>())
        }
    }

    @After
    fun teardown() {
        unmockkStatic(Base64::class)
    }

    // ─── Helpers ────────────────────────────────────────────────────────────────

    private fun buildV2Payload(
        name: String = "Test DB",
        databaseId: String = "db-123",
        favorites: String = "",
    ): String {
        val favoritesJson = if (favorites.isNotEmpty()) {
            ""","favorites":[{"q":"$favorites"}]"""
        } else {
            ""","favorites":[]"""
        }
        val json = """
            {
              "version": 2,
              "config": {
                "_id": "",
                "name": "$name",
                "databaseId": "$databaseId",
                "token": "tok_abc",
                "authUrl": "https://auth.example.com",
                "websocketUrl": "wss://ws.example.com",
                "httpApiUrl": "https://api.example.com",
                "httpApiKey": "key_xyz",
                "mode": "server",
                "allowUntrustedCerts": false,
                "secretKey": "",
                "isBluetoothLeEnabled": true,
                "isLanEnabled": true,
                "isAwdlEnabled": false,
                "isCloudSyncEnabled": true,
                "logLevel": "info"
              }$favoritesJson
            }
        """.trimIndent()
        val bytes = json.toByteArray(Charsets.UTF_8)
        val deflater = Deflater(Deflater.DEFAULT_COMPRESSION, false)
        deflater.setInput(bytes)
        deflater.finish()
        val output = ByteArray(bytes.size * 2 + 100)
        val length = deflater.deflate(output)
        deflater.end()
        val compressed = output.copyOf(length)
        return "EDS2:" + java.util.Base64.getEncoder().encodeToString(compressed)
    }

    private fun buildV1Payload(name: String = "Legacy DB", databaseId: String = "db-legacy"): String {
        return """
            {
              "_id": "",
              "name": "$name",
              "databaseId": "$databaseId",
              "token": "tok_legacy",
              "authUrl": "https://auth.example.com",
              "websocketUrl": "wss://ws.example.com",
              "httpApiUrl": "https://api.example.com",
              "httpApiKey": "key_legacy",
              "mode": "server",
              "allowUntrustedCerts": false,
              "secretKey": "",
              "isBluetoothLeEnabled": true,
              "isLanEnabled": true,
              "isAwdlEnabled": false,
              "isCloudSyncEnabled": true,
              "logLevel": "info"
            }
        """.trimIndent()
    }

    // ─── Tests ───────────────────────────────────────────────────────────────────

    @Test
    fun `decode valid EDS2 v2 payload returns correct database`() {
        val raw = buildV2Payload(name = "Production", databaseId = "prod-db-001")

        val result = QrCodeDecoder.decode(raw)

        assertNotNull(result)
        assertEquals("Production", result!!.database.name)
        assertEquals("prod-db-001", result.database.databaseId)
        assertEquals("tok_abc", result.database.token)
        assertEquals(AuthMode.SERVER, result.database.mode)
    }

    @Test
    fun `decode legacy v1 raw JSON returns correct database`() {
        val raw = buildV1Payload(name = "Legacy DB", databaseId = "db-legacy")

        val result = QrCodeDecoder.decode(raw)

        assertNotNull(result)
        assertEquals("Legacy DB", result!!.database.name)
        assertEquals("db-legacy", result.database.databaseId)
        assertTrue(result.favorites.isEmpty())
    }

    @Test
    fun `decode invalid string returns null`() {
        val result = QrCodeDecoder.decode("not-a-valid-qr-payload")
        assertNull(result)
    }

    @Test
    fun `decode empty string returns null`() {
        val result = QrCodeDecoder.decode("")
        assertNull(result)
    }

    @Test
    fun `decode payload with favorites returns favorites list`() {
        val raw = buildV2Payload(favorites = "SELECT * FROM collection")

        val result = QrCodeDecoder.decode(raw)

        assertNotNull(result)
        assertEquals(1, result!!.favorites.size)
        assertEquals("SELECT * FROM collection", result.favorites[0])
    }

    @Test
    fun `decode payload without favorites returns empty favorites`() {
        val raw = buildV2Payload()

        val result = QrCodeDecoder.decode(raw)

        assertNotNull(result)
        assertTrue(result!!.favorites.isEmpty())
    }

    @Test
    fun `decode v2 raw DEFLATE fallback succeeds for nowrap=true compressed payload`() {
        // Simulate what Apple's NSData.compressed(using: .zlib) might produce on some
        // platforms: raw DEFLATE (RFC 1951) without the 2-byte header/checksum wrapper.
        val json = """{"version":2,"config":{"_id":"","name":"RawDeflate","databaseId":"rd-1",
            "token":"t","authUrl":"https://a.example.com","websocketUrl":"wss://w.example.com",
            "httpApiUrl":"https://h.example.com","httpApiKey":"k","mode":"server",
            "allowUntrustedCerts":false,"secretKey":"","isBluetoothLeEnabled":true,
            "isLanEnabled":true,"isAwdlEnabled":false,"isCloudSyncEnabled":true,
            "logLevel":"info"},"favorites":[]}""".trimIndent()
        val bytes = json.toByteArray(Charsets.UTF_8)
        val deflater = Deflater(Deflater.DEFAULT_COMPRESSION, true) // nowrap=true → raw DEFLATE
        deflater.setInput(bytes)
        deflater.finish()
        val output = ByteArray(bytes.size * 2 + 100)
        val length = deflater.deflate(output)
        deflater.end()
        val compressed = output.copyOf(length)
        val raw = "EDS2:" + java.util.Base64.getEncoder().encodeToString(compressed)

        val result = QrCodeDecoder.decode(raw)

        assertNotNull(result)
        assertEquals("RawDeflate", result!!.database.name)
        assertEquals("rd-1", result.database.databaseId)
    }

    @Test
    fun `decompressZlib handles RFC 1950 zlib-wrapped data`() {
        val input = "hello cross-platform zlib".toByteArray(Charsets.UTF_8)
        val deflater = Deflater(Deflater.DEFAULT_COMPRESSION, false) // RFC 1950
        deflater.setInput(input)
        deflater.finish()
        val buf = ByteArray(input.size * 2 + 100)
        val len = deflater.deflate(buf)
        deflater.end()

        val result = QrCodeDecoder.decompressZlib(buf.copyOf(len))

        assertEquals("hello cross-platform zlib", String(result, Charsets.UTF_8))
    }

    @Test
    fun `decompressZlib falls back for raw DEFLATE data`() {
        val input = "hello raw deflate".toByteArray(Charsets.UTF_8)
        val deflater = Deflater(Deflater.DEFAULT_COMPRESSION, true) // raw DEFLATE
        deflater.setInput(input)
        deflater.finish()
        val buf = ByteArray(input.size * 2 + 100)
        val len = deflater.deflate(buf)
        deflater.end()

        val result = QrCodeDecoder.decompressZlib(buf.copyOf(len))

        assertEquals("hello raw deflate", String(result, Charsets.UTF_8))
    }

    @Test
    fun `decode v2 preserves all 16 database config fields`() {
        val raw = buildV2Payload(name = "Full Test", databaseId = "full-db")

        val result = QrCodeDecoder.decode(raw)
        val db = result!!.database

        assertEquals("Full Test", db.name)
        assertEquals("full-db", db.databaseId)
        assertEquals("tok_abc", db.token)
        assertEquals("https://auth.example.com", db.authUrl)
        assertEquals("wss://ws.example.com", db.websocketUrl)
        assertEquals("https://api.example.com", db.httpApiUrl)
        assertEquals("key_xyz", db.httpApiKey)
        assertEquals(AuthMode.SERVER, db.mode)
        assertEquals(false, db.allowUntrustedCerts)
        assertEquals("", db.secretKey)
        assertEquals(true, db.isBluetoothLeEnabled)
        assertEquals(true, db.isLanEnabled)
        assertEquals(false, db.isAwdlEnabled)
        assertEquals(true, db.isCloudSyncEnabled)
        assertEquals("info", db.logLevel)
    }
}
