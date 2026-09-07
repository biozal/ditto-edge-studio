package com.costoda.dittoedgestudio.data.ditto

import android.net.LocalSocket
import android.net.LocalSocketAddress
import java.io.ByteArrayOutputStream
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

/**
 * Client for the Ditto SDK 5.1 `debug_socket` listener (parity with the VS Code
 * extension's `DebugSocketClient`).
 *
 * Protocol: one DQL statement per line → one reply line (JSON array of items,
 * or `ERROR: <message>`). Requests are **serialised** (the wire has no request
 * IDs, so FIFO pairing is the only safe alignment). A 30 s timeout closes the
 * connection — the next call reconnects lazily. Reply lines are capped at
 * 64 MiB; exceeding that closes the connection (mirrors the extension).
 *
 * All public methods are safe to call from any dispatcher.
 */
/*
 * NOTE: currently unused by the app — retained deliberately.
 *
 * The in-app Debug Console this drove was removed: it opened a socket back to
 * our *own* process to run DQL that the query editor already runs directly on
 * the same Ditto instance, with no syntax restriction either way. `debug_socket`
 * only earns its keep for an *external* process (which is why the VS Code
 * extension needs it), so this client stays for a future
 * attach-to-another-Ditto feature rather than being rewritten from scratch.
 */
class DebugSocketClient(
    private val connectTimeoutMs: Long = DEFAULT_CONNECT_TIMEOUT_MS, // unused: LocalSocket has no connect timeout
    private val queryTimeoutMs: Long = DEFAULT_QUERY_TIMEOUT_MS,
    private val maxLineBytes: Int = DEFAULT_MAX_LINE_BYTES,
    private val namespace: LocalSocketAddress.Namespace = LocalSocketAddress.Namespace.FILESYSTEM,
) {

    class NotConnectedException(message: String) : Exception(message)
    class TimeoutException(message: String) : Exception(message)
    class ResponseTooLargeException(message: String) : Exception(message)

    private val lock = Mutex()
    private var socket: LocalSocket? = null
    private var socketPath: String? = null
    /** Leftover bytes from a read that carried more than one reply line — without
     *  this, bundled replies are dropped and FIFO pairing breaks. */
    private val receiveBuffer = ByteArrayOutputStream()

    val isConnected: Boolean get() = socket?.isConnected == true

    /** Connects to the unix socket at [path]. Idempotent; reconnects after close. */
    suspend fun connect(path: String) {
        lock.withLock {
            if (isConnected && socketPath == path) return
            closeLocked()
            socketPath = path
            withContext(Dispatchers.IO) {
                val newSocket = LocalSocket()
                newSocket.connect(LocalSocketAddress(path, namespace))
                socket = newSocket
            }
        }
    }

    /**
     * Sends [statement] (newline-terminated on the wire) and returns the reply
     * line (without the terminator). Throws [TimeoutException] after
     * [queryTimeoutMs] — the connection is then dead (extension parity).
     */
    suspend fun execute(statement: String): String {
        lock.withLock {
            val path = socketPath
                ?: throw NotConnectedException("Not connected — call connect(path) first")
            if (!isConnected) {
                closeLocked()
                withContext(Dispatchers.IO) {
                    val newSocket = LocalSocket()
                    newSocket.connect(LocalSocketAddress(path, namespace))
                    socket = newSocket
                }
            }
            val active = socket ?: throw NotConnectedException("Connection dropped")
            return try {
                withContext(Dispatchers.IO) { executeExchange(active, statement) }
            } catch (e: TimeoutException) {
                closeLocked()
                throw e
            } catch (e: ResponseTooLargeException) {
                closeLocked()
                throw e
            }
        }
    }

    /**
     * Write-then-read with a hard timeout. `InputStream.read` can't be cancelled,
     * so the timeout is a watchdog that force-closes the socket — the blocked read
     * then throws IOException, which this maps to [TimeoutException] (extension
     * parity: a timeout closes the connection; the next call reconnects).
     */
    private suspend fun executeExchange(socket: LocalSocket, statement: String): String =
        withContext(Dispatchers.IO) {
            val completed = AtomicBoolean(false)
            val timedOut = AtomicBoolean(false)
            // Plain thread, not a coroutine: the exchange below blocks this thread, and a
            // coroutine watchdog in the same scope would only start after the block returns
            // (launch bodies don't preempt a non-suspending block).
            val watchdog = Thread {
                try {
                    Thread.sleep(queryTimeoutMs)
                    if (!completed.get()) {
                        timedOut.set(true)
                        // LocalSocket.close() alone does NOT reliably unblock a pending
                        // read() on Android — shutdown the input side first.
                        runCatching { socket.shutdownInput() }
                        runCatching { socket.shutdownOutput() }
                        runCatching { socket.close() }
                    }
                } catch (_: InterruptedException) {
                    // Normal cancel path — the exchange finished first.
                }
            }.apply {
                isDaemon = true
                name = "debug-socket-watchdog"
                start()
            }
            try {
                socket.outputStream.write(statement.toByteArray(Charsets.UTF_8))
                socket.outputStream.write('\n'.code)
                socket.outputStream.flush()
                val line = readLineLocked(socket)
                completed.set(true)
                line
            } catch (e: java.io.IOException) {
                if (timedOut.get()) throw TimeoutException("No response within ${queryTimeoutMs}ms")
                throw e
            } catch (e: NotConnectedException) {
                // Watchdog close surfaces here too ("Socket closed by the peer").
                if (timedOut.get()) throw TimeoutException("No response within ${queryTimeoutMs}ms")
                throw e
            } finally {
                watchdog.interrupt()
            }
        }

    fun close() {
        // Non-suspend convenience for session teardown (the Ditto-side listener dies
        // with the instance, so an in-flight execute's socket dying later is benign).
        if (!lock.tryLock()) return
        try {
            closeLocked()
        } finally {
            lock.unlock()
        }
    }

    /** Suspending close that waits for an in-flight exchange to finish. */
    suspend fun closeAndWait() {
        lock.withLock { closeLocked() }
    }

    private fun closeLocked() {
        runCatching { socket?.close() }
        socket = null
        receiveBuffer.reset()
    }

    /** Reads until `\n`; throws [ResponseTooLargeException] past [maxLineBytes]. */
    private fun readLineLocked(socket: LocalSocket): String {
        val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
        while (true) {
            val buffered = receiveBuffer.toByteArray()
            val existing = buffered.indexOf('\n'.code.toByte())
            if (existing >= 0) {
                val line = String(buffered, 0, existing, Charsets.UTF_8)
                receiveBuffer.reset()
                if (existing + 1 < buffered.size) {
                    receiveBuffer.write(buffered, existing + 1, buffered.size - existing - 1)
                }
                return line
            }
            val read = socket.inputStream.read(buffer)
            if (read < 0) throw NotConnectedException("Socket closed by the peer")
            receiveBuffer.write(buffer, 0, read)
            if (receiveBuffer.size() > maxLineBytes) {
                throw ResponseTooLargeException(
                    "Response exceeded $maxLineBytes bytes",
                )
            }
        }
    }

    companion object {
        const val DEFAULT_CONNECT_TIMEOUT_MS = 10_000L
        const val DEFAULT_QUERY_TIMEOUT_MS = 30_000L
        const val DEFAULT_MAX_LINE_BYTES = 64 * 1024 * 1024
        private const val DEFAULT_BUFFER_SIZE = 8 * 1024
    }
}
