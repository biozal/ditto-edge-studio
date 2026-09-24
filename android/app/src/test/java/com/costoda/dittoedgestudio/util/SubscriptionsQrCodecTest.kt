package com.costoda.dittoedgestudio.util

import android.util.Base64
import com.costoda.dittoedgestudio.domain.model.DittoSubscription
import io.mockk.every
import io.mockk.mockkStatic
import io.mockk.unmockkStatic
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Test

class SubscriptionsQrCodecTest {

    /** android.util.Base64 is routed to java.util.Base64 (same trick as QrCodeDecoderTest). */
    @Before
    fun setup() {
        mockkStatic(Base64::class)
        every { Base64.encodeToString(any(), any()) } answers {
            java.util.Base64.getEncoder().encodeToString(firstArg<ByteArray>())
        }
        every { Base64.decode(any<String>(), any()) } answers {
            java.util.Base64.getDecoder().decode(firstArg<String>())
        }
    }

    @After
    fun tearDown() {
        unmockkStatic(Base64::class)
    }

    @Test
    fun `round trip preserves name and query`() {
        val subs = listOf(
            DittoSubscription(id = 1, databaseId = "db", name = "orders sub", query = "SELECT * FROM orders"),
            DittoSubscription(id = 2, databaseId = "db", name = "", query = "SELECT * FROM cars"),
        )
        val encoded = SubscriptionsQrCodec.encode(subs)!!
        assertEquals(true, encoded.startsWith(SubscriptionsQrCodec.PREFIX))

        val decoded = SubscriptionsQrCodec.decode(encoded)!!
        assertEquals(2, decoded.size)
        assertEquals("orders sub", decoded[0].name)
        assertEquals("SELECT * FROM orders", decoded[0].query)
        // Blank name becomes the fallback label (SwiftUI parity).
        assertEquals("Unnamed subscription", decoded[1].name)
    }

    @Test
    fun `empty list encodes to null`() {
        assertNull(SubscriptionsQrCodec.encode(emptyList()))
    }

    @Test
    fun `decode rejects foreign payloads`() {
        assertNull(SubscriptionsQrCodec.decode("EDS2:foobar"))
        assertNull(SubscriptionsQrCodec.decode("EDS_SUBS1:not-base64!!"))
        assertNull(SubscriptionsQrCodec.decode("hello world"))
    }

    @Test
    fun `decodes a payload produced by the Swift encoder shape (raw zlib + base64)`() {
        // Hand-built: {"version":1,"subscriptions":[{"name":"n","query":"SELECT * FROM t"}]}
        // through java's Deflater, exactly what the encoder does; this test pins the round trip
        // via the decoder against a second encoder implementation path.
        val jsonString = """{"version":1,"subscriptions":[{"name":"n","query":"SELECT * FROM t","args":null}]}"""
        val bytes = jsonString.toByteArray(Charsets.UTF_8)
        val deflater = java.util.zip.Deflater(java.util.zip.Deflater.DEFAULT_COMPRESSION, false)
        deflater.setInput(bytes)
        deflater.finish()
        val out = ByteArray(bytes.size * 2 + 100)
        val len = deflater.deflate(out)
        deflater.end()
        val payload = SubscriptionsQrCodec.PREFIX +
            android.util.Base64.encodeToString(out.copyOf(len), android.util.Base64.NO_WRAP)

        val decoded = SubscriptionsQrCodec.decode(payload)!!
        assertEquals("SELECT * FROM t", decoded[0].query)
        assertEquals(null, decoded[0].args)
    }
}
