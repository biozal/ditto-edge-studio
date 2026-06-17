package com.costoda.dittoedgestudio.data.repository

import com.costoda.dittoedgestudio.domain.model.AttachmentInfo
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.io.ByteArrayInputStream
import java.io.File
import java.io.InputStream
import java.util.concurrent.atomic.AtomicInteger

class AttachmentServiceTest {

    private lateinit var tmpDir: File
    private lateinit var gateway: RecordingGateway
    private lateinit var svc: AttachmentService

    @Before
    fun setUp() {
        tmpDir = File.createTempFile("attsvc", ".dir").apply { delete(); mkdirs() }
        gateway = RecordingGateway()
        svc = AttachmentService(gateway = gateway, cacheDirProvider = { tmpDir })
    }

    @After
    fun tearDown() { tmpDir.deleteRecursively() }

    @Test
    fun `createFromFile delegates to gateway and returns id`() = runTest {
        gateway.newAttachmentResult = "new-att-1"
        val id = svc.createFromFile(path = "/tmp/foo.bin", metadata = mapOf("type" to "image/png"))
        assertEquals("new-att-1", id)
        assertEquals(listOf("/tmp/foo.bin" to mapOf("type" to "image/png")), gateway.newAttachmentCalls)
    }

    @Test
    fun `fetchToCache writes the stream contents to cacheDir attachments id`() = runTest {
        val payload = "hello".toByteArray()
        gateway.fetchPayload = payload
        val info = AttachmentInfo(id = "abc", len = payload.size.toLong(),
            fieldName = "photo", metadata = mapOf("type" to "image/png"))

        val file = svc.fetchToCache(info)

        assertEquals(File(tmpDir, "attachments/abc"), file)
        assertArrayEquals(payload, file.readBytes())
    }

    @Test
    fun `fetchToCache short-circuits when the file already exists with matching length`() = runTest {
        val payload = "hello".toByteArray()
        // Prime the cache: first call writes the file.
        gateway.fetchPayload = payload
        val info = AttachmentInfo("abc", len = payload.size.toLong(), fieldName = "x",
            metadata = emptyMap())
        svc.fetchToCache(info)
        assertEquals(1, gateway.fetchCallCount.get())

        // Second call must NOT touch the gateway.
        svc.fetchToCache(info)
        assertEquals(1, gateway.fetchCallCount.get())
    }

    @Test
    fun `fetchToCache rewrites when cached file size differs from token len`() = runTest {
        val cacheRoot = File(tmpDir, "attachments").apply { mkdirs() }
        File(cacheRoot, "abc").writeBytes(byteArrayOf(0x00))  // 1 byte; token claims 5
        val payload = "hello".toByteArray()
        gateway.fetchPayload = payload

        val info = AttachmentInfo("abc", len = payload.size.toLong(), fieldName = "x",
            metadata = emptyMap())
        val file = svc.fetchToCache(info)
        assertArrayEquals(payload, file.readBytes())
        assertTrue(gateway.fetchCallCount.get() == 1)
    }
}

private class RecordingGateway : AttachmentStoreGateway {
    val newAttachmentCalls: MutableList<Pair<String, Map<String, String>>> = mutableListOf()
    var newAttachmentResult: String = ""
    val fetchCallCount = AtomicInteger(0)
    var fetchPayload: ByteArray = ByteArray(0)

    override suspend fun newAttachment(path: String, metadata: Map<String, String>): String {
        newAttachmentCalls += path to metadata
        return newAttachmentResult
    }

    override suspend fun fetchAttachment(tokenMap: Map<String, Any>): InputStream {
        fetchCallCount.incrementAndGet()
        return ByteArrayInputStream(fetchPayload)
    }
}
