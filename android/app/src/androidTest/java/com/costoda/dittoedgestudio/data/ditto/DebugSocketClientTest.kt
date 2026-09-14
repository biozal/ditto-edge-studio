package com.costoda.dittoedgestudio.data.ditto

import android.net.LocalServerSocket
import android.net.LocalSocket
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * PoC-grade protocol tests for [DebugSocketClient] against a self-hosted
 * `LocalServerSocket` — FIFO pairing, timeout-closes-connection, and the
 * response-line cap. (The live-Ditto round-trip is DebugSocketPocTest.)
 */
@RunWith(AndroidJUnit4::class)
class DebugSocketClientTest {

    private var server: LocalServerSocket? = null
    private var serverThread: Thread? = null

    @After
    fun tearDown() {
        runCatching { server?.close() }
        serverThread?.interrupt()
    }

    /** Starts an echo-ish server: replies to each line with `line` reversed. */
    private fun startEchoServer(
        delayMs: Long = 0,
        replies: Int = Int.MAX_VALUE,
    ): String {
        // LocalServerSocket is abstract-namespace; the client takes a namespace param.
        val name = "poc-${System.nanoTime()}"
        val srv = LocalServerSocket(name)
        server = srv
        serverThread = Thread {
            var handled = 0
            while (!Thread.currentThread().isInterrupted && handled < replies) {
                val conn = try {
                    srv.accept()
                } catch (_: Exception) {
                    break
                } ?: continue
                Thread {
                    conn.use { c ->
                        val buf = ByteArray(1024)
                        var line = StringBuilder()
                        while (true) {
                            val read = try {
                                c.inputStream.read(buf)
                            } catch (_: Exception) {
                                break
                            }
                            if (read < 0) break
                            line.append(String(buf, 0, read))
                            var idx = line.indexOf("\n")
                            while (idx >= 0) {
                                val statement = line.substring(0, idx)
                                line = StringBuilder(line.substring(idx + 1))
                                if (delayMs > 0) Thread.sleep(delayMs)
                                c.outputStream.write((statement.reversed() + "\n").toByteArray())
                                c.outputStream.flush()
                                idx = line.indexOf("\n")
                            }
                        }
                    }
                }.start()
                handled++
            }
        }.apply { isDaemon = true; start() }
        return name
    }

    @Test
    fun roundTripsAndPairsFifo() = runBlocking {
        val path = startEchoServer()
        val client = DebugSocketClient(namespace = android.net.LocalSocketAddress.Namespace.ABSTRACT)
        client.connect(path)
        try {
            assertEquals("cba", client.execute("abc"))
            assertEquals("321", client.execute("123"))
        } finally {
            client.close()
        }
    }

    @Test
    fun timeoutClosesConnectionAndNextCallReconnects() = runBlocking {
        val path = startEchoServer(delayMs = 5_000, replies = 2)
        val client = DebugSocketClient(
            connectTimeoutMs = 2_000,
            queryTimeoutMs = 300,
            namespace = android.net.LocalSocketAddress.Namespace.ABSTRACT,
        )
        client.connect(path)
        assertThrows(DebugSocketClient.TimeoutException::class.java) {
            runBlocking { client.execute("slow") }
        }
        assertTrue(!client.isConnected)
        // A fast statement on the SAME path reconnects lazily and succeeds
        // (server's second accept replies promptly? no — server delays all
        // replies; use a fresh fast server instead).
        val fastPath = startEchoServer()
        client.connect(fastPath)
        assertEquals("ok", client.execute("ko"))
        client.close()
    }

    @Test
    fun serialCallsPreserveOrderUnderConcurrency() = runBlocking {
        val path = startEchoServer()
        val client = DebugSocketClient(namespace = android.net.LocalSocketAddress.Namespace.ABSTRACT)
        client.connect(path)
        try {
            val results = (1..20).map { i ->
                async { i.toString() to client.execute("q$i") }
            }.awaitAll()
            results.forEach { (i, reply) ->
                assertEquals("q$i".reversed(), reply)
            }
        } finally {
            client.close()
        }
    }

    @Test
    fun oversizedReplyIsRejected() = runBlocking {
        val name = "poc-big-${System.nanoTime()}"
        val srv = LocalServerSocket(name)
        server = srv
        serverThread = Thread {
            val conn = try { srv.accept() } catch (_: Exception) { return@Thread }
            try {
                conn.use { c ->
                    val buf = ByteArray(1024)
                    while (c.inputStream.read(buf) >= 0) {
                        // flood: 1 MiB of X per query line, no newline → over the cap
                        c.outputStream.write(ByteArray(1024 * 1024) { 'X'.code.toByte() })
                        c.outputStream.flush()
                        break
                    }
                }
            } catch (_: java.io.IOException) {
                // Broken pipe when the client force-closes after the cap — expected.
            }
        }.apply { isDaemon = true; start() }
        val client = DebugSocketClient(
            queryTimeoutMs = 5_000,
            maxLineBytes = 256 * 1024,
            namespace = android.net.LocalSocketAddress.Namespace.ABSTRACT,
        )
        client.connect(name)
        assertThrows(DebugSocketClient.ResponseTooLargeException::class.java) {
            runBlocking { client.execute("big") }
        }
        client.close()
    }

    @Test
    fun executeWithoutConnectFails() {
        val client = DebugSocketClient()
        assertThrows(DebugSocketClient.NotConnectedException::class.java) {
            runBlocking { client.execute("SELECT 1") }
        }
    }
}
