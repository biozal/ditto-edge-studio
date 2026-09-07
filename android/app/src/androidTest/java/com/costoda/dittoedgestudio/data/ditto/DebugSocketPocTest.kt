package com.costoda.dittoedgestudio.data.ditto

import android.net.LocalSocket
import android.net.LocalSocketAddress
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.ditto.kotlin.DittoConfig
import com.ditto.kotlin.DittoFactory
import java.io.File
import java.util.Properties
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeNotNull
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Phase 4 PoC (plan: plans/2026-08-24-vsc-pr16-5.1-diagnostics-parity.md):
 * proves that on Android a real Ditto SDK 5.1 debug socket can be opened for
 * our own embedded instance (`ALTER SYSTEM SET debug_socket`), and that
 * `android.net.LocalSocket` (filesystem namespace) can round-trip a newline-DQL
 * query against it.
 *
 * Credentials come from `app/src/androidTest/assets/debugSocketTestConfig.properties`
 * (gitignored — never commit real tokens). Properties: `databaseId`, `offlineToken`.
 * The test self-skips (Assume) when the fixture is absent.
 */
@RunWith(AndroidJUnit4::class)
class DebugSocketPocTest {

    private var scope: CoroutineScope? = null
    private var ditto: com.ditto.kotlin.Ditto? = null
    private var persistenceDir: File? = null

    private fun loadCredentials(): Pair<String, String>? {
        val context = InstrumentationRegistry.getInstrumentation().context
        return try {
            val props = Properties()
            context.assets.open("debugSocketTestConfig.properties").use { props.load(it) }
            val id = props.getProperty("databaseId")?.trim()
            val token = props.getProperty("offlineToken")?.trim()
            if (id.isNullOrEmpty() || token.isNullOrEmpty()) null else id to token
        } catch (_: Exception) {
            null
        }
    }

    @Before
    fun setUp() {
        persistenceDir = File(
            InstrumentationRegistry.getInstrumentation().targetContext.cacheDir,
            "debug-socket-poc-${System.currentTimeMillis()}",
        )
        persistenceDir!!.mkdirs()
        scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    }

    @After
    fun tearDown() {
        runBlocking {
            runCatching {
                ditto?.store?.execute("ALTER SYSTEM SET debug_socket = ''")
            }
            runCatching { ditto?.close() }
            scope?.cancel()
        }
        persistenceDir?.deleteRecursively()
    }

    @Test
    fun debugSocketRoundTripsDqlOverLocalSocket() = runBlocking {
        val (databaseId, offlineToken) = loadCredentials().let {
            assumeNotNull(
                "debugSocketTestConfig.properties absent from androidTest assets — skipping PoC",
                it,
            )
            it!!
        }

        val config = DittoConfig(
            databaseId = databaseId,
            connect = DittoConfig.Connect.SmallPeersOnly(),
            persistenceDirectory = persistenceDir!!.absolutePath,
        )
        val d = DittoFactory.create(config, scope!!)
        ditto = d
        d.setOfflineOnlyLicenseToken(offlineToken)

        val socketPath = File(persistenceDir, "ditto-debug.sock").absolutePath
        d.store.execute("ALTER SYSTEM SET debug_socket = '$socketPath'")

        // Wait for the socket to appear.
        val socketFile = File(socketPath)
        val deadline = System.currentTimeMillis() + 5_000
        while (!socketFile.exists() && System.currentTimeMillis() < deadline) {
            kotlinx.coroutines.delay(50)
        }
        assertTrue("debug socket never appeared at $socketPath", socketFile.exists())

        // LocalSocket round-trip (filesystem namespace).
        val socket = LocalSocket()
        val response = arrayOfNulls<String>(1)
        try {
            socket.connect(LocalSocketAddress(socketPath, LocalSocketAddress.Namespace.FILESYSTEM))
            socket.outputStream.write("SELECT * FROM system:dual\n".toByteArray(Charsets.UTF_8))
            socket.outputStream.flush()

            // Read one response line on a worker thread with a latch timeout
            // (LocalSocket has no reliable SO_TIMEOUT on all API levels).
            val latch = CountDownLatch(1)
            Thread {
                try {
                    val sb = StringBuilder()
                    val buffer = ByteArray(4096)
                    while (!sb.contains('\n')) {
                        val read = socket.inputStream.read(buffer)
                        if (read < 0) break
                        sb.append(String(buffer, 0, read, Charsets.UTF_8))
                    }
                    response[0] = sb.toString().lineSequence().firstOrNull()
                } catch (_: Exception) {
                }
                latch.countDown()
            }.start()
            assertTrue("no response line within 10s", latch.await(10, TimeUnit.SECONDS))
        } finally {
            runCatching { socket.close() }
        }

        val line = response[0]
        assertNotNull("expected a response line from the debug socket", line)
        assertTrue("response should contain the dual row: $line", line!!.contains("dummy"))
        assertTrue("response should be a JSON array: $line", line.trim().startsWith("["))
    }
}
