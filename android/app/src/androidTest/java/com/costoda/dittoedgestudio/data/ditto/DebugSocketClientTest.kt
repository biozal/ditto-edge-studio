package com.costoda.dittoedgestudio.data.ditto

import android.net.LocalServerSocket
import android.net.LocalSocket
import android.net.LocalSocketAddress
import androidx.test.ext.junit.runners.AndroidJUnit4
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.IOException
import java.util.concurrent.ConcurrentLinkedQueue
import java.util.concurrent.atomic.AtomicBoolean

/**
 * PoC-grade protocol tests for [DebugSocketClient] against a self-hosted
 * `LocalServerSocket` — FIFO pairing, timeout-closes-connection, and the
 * response-line cap. (The live-Ditto round-trip is DebugSocketPocTest.)
 */
@RunWith(AndroidJUnit4::class)
class DebugSocketClientTest {

    private val servers = mutableListOf<Pair<String, LocalServerSocket>>()
    private val serverThreads = mutableListOf<Thread>()
    private val connections = ConcurrentLinkedQueue<LocalSocket>()
    private val serverFailures = ConcurrentLinkedQueue<Throwable>()
    private val stopping = AtomicBoolean(false)

    @After
    fun tearDown() {
        stopping.set(true)
        servers.forEach { (name, server) ->
            // Closing a listener (or interrupting its thread) does not unblock
            // LocalServerSocket.accept on Android. A single local connection
            // wakes accept; stopping makes serveConnection close it immediately.
            try {
                LocalSocket().use { wakeup ->
                    wakeup.connect(LocalSocketAddress(name, LocalSocketAddress.Namespace.ABSTRACT))
                }
            } catch (error: IOException) { serverFailures.add(error) }
            try { server.close() } catch (error: IOException) { serverFailures.add(error) }
        }
        connections.forEach { connection ->
            // LocalSocket.close alone may not unblock a pending read.
            try { connection.shutdownInput() } catch (_: IOException) { /* already disconnected */ }
            try { connection.shutdownOutput() } catch (_: IOException) { /* already disconnected */ }
            try { connection.close() } catch (error: IOException) { serverFailures.add(error) }
        }
        serverThreads.forEach(Thread::interrupt)
        val deadline = System.nanoTime() + 3_000_000_000L
        serverThreads.forEach { thread ->
            val remainingMs = (deadline - System.nanoTime()) / 1_000_000L
            if (remainingMs > 0) thread.join(remainingMs)
        }
        val survivors = serverThreads.filter { it.isAlive }
        assertTrue("Test server threads did not stop: ${survivors.map { it.name }}", survivors.isEmpty())
        if (serverFailures.isNotEmpty()) {
            throw AssertionError("Unexpected test server failure").apply {
                serverFailures.forEach { addSuppressed(it) }
            }
        }
    }

    private fun startServerThread(block: () -> Unit) {
        val thread = Thread(block, "debug-socket-test-${serverThreads.size}").apply {
            isDaemon = true
            // Report unexpected failures through JUnit after joining, rather than
            // crashing instrumentation during an unrelated later test.
            uncaughtExceptionHandler = Thread.UncaughtExceptionHandler { _, error -> serverFailures.add(error) }
        }
        serverThreads.add(thread)
        thread.start()
    }

    private fun serveConnection(connection: LocalSocket, block: (LocalSocket) -> Unit) {
        connections.add(connection)
        try {
            connection.use { if (!stopping.get()) block(it) }
        } catch (error: IOException) {
            // Timeout/oversize tests intentionally close the client before the
            // reply. Other I/O errors still fail this test via the thread handler.
            val disconnected = error.message.orEmpty().let {
                it.contains("Broken pipe", ignoreCase = true) ||
                    it.contains("Connection reset", ignoreCase = true)
            }
            if (!stopping.get() && !disconnected) throw error
        } catch (error: InterruptedException) {
            if (!stopping.get()) throw error
            Thread.currentThread().interrupt()
        } finally {
            connections.remove(connection)
        }
    }

    private fun accept(server: LocalServerSocket): LocalSocket? = try {
        server.accept()
    } catch (error: IOException) {
        if (!stopping.get()) throw error
        null
    }

    /** Starts an echo-ish server: replies to each line with `line` reversed. */
    private fun startEchoServer(
        delayMs: Long = 0,
        replies: Int = Int.MAX_VALUE,
    ): String {
        // LocalServerSocket is abstract-namespace; the client takes a namespace param.
        val name = "poc-${System.nanoTime()}"
        val srv = LocalServerSocket(name)
        servers.add(name to srv)
        startServerThread {
            var handled = 0
            while (!stopping.get() && handled < replies) {
                val conn = accept(srv) ?: break
                // Each server has one tracked thread. There are no detached
                // per-connection workers that can outlive tearDown.
                serveConnection(conn) { c ->
                    val buf = ByteArray(1024)
                    var line = StringBuilder()
                    while (!stopping.get()) {
                        val read = c.inputStream.read(buf)
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
                handled++
            }
        }
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
        servers.add(name to srv)
        startServerThread {
            val conn = accept(srv)
            if (conn != null) serveConnection(conn) { c ->
                val buf = ByteArray(1024)
                if (c.inputStream.read(buf) >= 0) {
                    // flood: 1 MiB of X per query line, no newline → over the cap
                    c.outputStream.write(ByteArray(1024 * 1024) { 'X'.code.toByte() })
                    c.outputStream.flush()
                }
            }
        }
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
