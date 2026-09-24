package com.costoda.dittoedgestudio.data.session

import com.costoda.dittoedgestudio.data.ditto.DittoManager
import com.costoda.dittoedgestudio.data.logging.DittoLogCaptureService
import com.costoda.dittoedgestudio.data.repository.CollectionsRepository
import com.costoda.dittoedgestudio.data.repository.DatabaseRepository
import com.costoda.dittoedgestudio.data.repository.NetworkDiagnosticsRepository
import com.costoda.dittoedgestudio.data.repository.ObservableRepository
import com.costoda.dittoedgestudio.data.repository.SubscriptionsRepository
import com.costoda.dittoedgestudio.data.repository.SystemRepository
import com.costoda.dittoedgestudio.domain.model.AuthMode
import com.costoda.dittoedgestudio.domain.model.ConnectionsByTransport
import com.costoda.dittoedgestudio.domain.model.DittoCollection
import com.costoda.dittoedgestudio.domain.model.DittoDatabase
import com.costoda.dittoedgestudio.domain.model.IndexField
import com.costoda.dittoedgestudio.domain.model.LocalPeerInfo
import com.costoda.dittoedgestudio.domain.model.SyncStatusInfo
import com.ditto.kotlin.Ditto
import com.ditto.kotlin.DittoConfig
import com.ditto.kotlin.DittoFactory
import com.ditto.kotlin.DittoQueryResult
import com.ditto.kotlin.DittoStore
import io.mockk.coVerify
import io.mockk.coEvery
import io.mockk.every
import io.mockk.mockk
import io.mockk.mockkObject
import io.mockk.unmockkObject
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestCoroutineScheduler
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class StudioSessionTest {

    private val testDispatcher = StandardTestDispatcher()

    private lateinit var databaseRepository: DatabaseRepository
    private lateinit var dittoManager: DittoManager
    private lateinit var systemRepository: SystemRepository
    private lateinit var networkRepo: NetworkDiagnosticsRepository
    private lateinit var subscriptionsRepository: SubscriptionsRepository
    private lateinit var collectionsRepository: CollectionsRepository
    private lateinit var logCaptureService: DittoLogCaptureService
    private lateinit var observableRepository: ObservableRepository

    @Before
    fun setUp() {
        Dispatchers.setMain(testDispatcher)
        databaseRepository = mockk(relaxed = true)
        dittoManager = mockk(relaxed = true)
        systemRepository = mockk(relaxed = true)
        networkRepo = mockk(relaxed = true)
        subscriptionsRepository = mockk(relaxed = true)
        collectionsRepository = mockk(relaxed = true)
        logCaptureService = mockk(relaxed = true)
        observableRepository = mockk(relaxed = true)

        every { systemRepository.localPeer } returns MutableStateFlow<LocalPeerInfo?>(null)
        every { systemRepository.peers } returns MutableStateFlow<List<SyncStatusInfo>>(emptyList())
        every { systemRepository.connectionsByTransport } returns MutableStateFlow(ConnectionsByTransport.Empty)
        every { collectionsRepository.collections } returns MutableStateFlow<List<DittoCollection>>(emptyList())
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
        // Drain any leftover teardown jobs across tests to keep the process-wide registry clean.
        DittoTeardownRegistry.inFlightJob(42L)?.cancel()
        DittoTeardownRegistry.inFlightJob(7L)?.cancel()
    }

    private fun newSession(
        databaseId: Long = 42L,
        ioDispatcher: CoroutineDispatcher = testDispatcher,
        teardownDispatcher: CoroutineDispatcher = testDispatcher,
    ): StudioSession = StudioSession(
        databaseId = databaseId,
        databaseRepository = databaseRepository,
        dittoManager = dittoManager,
        systemRepository = systemRepository,
        networkRepo = networkRepo,
        subscriptionsRepository = subscriptionsRepository,
        collectionsRepository = collectionsRepository,
        loggingCaptureService = logCaptureService,
        observableRepository = observableRepository,
        historyRepository = mockk(relaxed = true),
        appPreferences = mockk<com.costoda.dittoedgestudio.data.preferences.AppPreferencesGateway>().also {
            io.mockk.every { it.collectSystemMetrics } returns kotlinx.coroutines.flow.MutableStateFlow(true)
            // StudioSession collects the pins eagerly at construction.
            io.mockk.every { it.systemMetricPins(any()) } returns
                kotlinx.coroutines.flow.MutableStateFlow(emptyList())
        },
        context = mockk(relaxed = true),
        ioDispatcher = ioDispatcher,
        teardownDispatcher = teardownDispatcher,
    )

    @Test
    fun `close is idempotent - dittoManager close called exactly once`() = runTest {
        val session = newSession()
        coEvery { dittoManager.closeIfCurrent(any()) } returns Unit

        // First close
        session.close()
        assertTrue(session.isClosed())

        // Subsequent closes are no-ops
        session.close()
        session.close()

        // Teardown is dispatched to the testDispatcher; drive it to completion.
        advanceUntilIdle()

        // Verify Ditto was closed exactly once across all three calls
        coVerify(exactly = 1) { dittoManager.closeIfCurrent(any()) }
    }

    @Test
    fun `close stops system and collections observers exactly once`() = runTest {
        val session = newSession()

        session.close()
        session.close()

        coVerify(exactly = 1) { systemRepository.stopObserving() }
        coVerify(exactly = 1) { collectionsRepository.stopObserving() }
    }

    @Test
    fun `close clears subscription and observer state`() = runTest {
        val session = newSession()
        coEvery { dittoManager.closeIfCurrent(any()) } returns Unit

        session.close()
        advanceUntilIdle()

        assertEquals(emptyList<Any>(), session.subscriptions.value)
        assertEquals(emptyList<Any>(), session.observers.value)
        assertEquals(emptyList<Any>(), session.observerEvents.value)
    }

    @Test
    fun `isClosed reports false before close`() {
        val session = newSession()
        assertFalse(session.isClosed())
    }

    @Test
    fun `isClosed reports true after first close`() {
        val session = newSession()
        session.close()
        assertTrue(session.isClosed())
    }

    @Test
    fun `close does not block the calling thread`() = runTest {
        val session = newSession()
        val gate = CompletableDeferred<Unit>()
        coEvery { dittoManager.closeIfCurrent(any()) } coAnswers { gate.await() }

        // Call close(); it must RETURN even though dittoManager.closeIfCurrent(any()) is still suspended on the gate.
        session.close()

        // The session is marked closed synchronously, and the teardown job is registered.
        assertTrue(session.isClosed())
        val teardownJob = DittoTeardownRegistry.inFlightJob(42L)
        assertNotNull("teardown job should be registered", teardownJob)
        // Drive the dispatcher just enough to actually invoke dittoManager.closeIfCurrent(any()) — it must
        // suspend on the gate, NOT complete.
        runCurrent()
        assertTrue("teardown should still be suspended on the gate", teardownJob!!.isActive)

        // Release the gate; teardown completes; registry clears the entry.
        gate.complete(Unit)
        advanceUntilIdle()
        assertTrue("teardown should have completed", teardownJob.isCompleted)
        assertNull(DittoTeardownRegistry.inFlightJob(42L))
        coVerify(exactly = 1) { dittoManager.closeIfCurrent(any()) }
    }

    @Test
    fun `addIndex returns success when the repository succeeds`() = runTest {
        val session = newSession()
        coEvery { collectionsRepository.createIndex(any(), any()) } returns Unit

        val result = session.addIndex("tasks", listOf(IndexField("status")))

        assertTrue(result.isSuccess)
    }

    @Test
    fun `addIndex wraps repository failures in Result`() = runTest {
        val session = newSession()
        coEvery { collectionsRepository.createIndex(any(), any()) } throws
            IllegalStateException("No active Ditto instance")

        val result = session.addIndex("tasks", listOf(IndexField("status")))

        assertTrue(result.isFailure)
        assertEquals("No active Ditto instance", result.exceptionOrNull()?.message)
    }

    @Test
    fun `addIndex rethrows CancellationException instead of wrapping it in Result`() = runTest {
        val session = newSession()
        coEvery { collectionsRepository.createIndex(any(), any()) } throws
            CancellationException("caller gone")

        val outcome = runCatching { session.addIndex("tasks", listOf(IndexField("status"))) }

        assertTrue(
            "CancellationException must propagate, not become a fake failure",
            outcome.exceptionOrNull() is CancellationException,
        )
    }

    @Test
    fun `addIndex on a closed session throws CancellationException to the caller`() = runTest {
        val session = newSession()
        coEvery { dittoManager.closeIfCurrent(any()) } returns Unit
        session.close()
        advanceUntilIdle()

        val outcome = runCatching { session.addIndex("tasks", listOf(IndexField("status"))) }

        assertTrue(
            "A closed session must cancel the call, not hang or report a fake failure",
            outcome.exceptionOrNull() is CancellationException,
        )
    }

    @Test
    fun `applyTransportSettings restarts sync and keeps persisted state when the apply throws`() = runTest {
        // A failed live apply must not leave sync stopped, and the transport
        // StateFlows must keep showing the persisted (actually-applied) values
        // rather than the requested ones.
        val ditto = mockk<com.ditto.kotlin.Ditto>(relaxed = true) {
            every { sync } returns mockk(relaxed = true)
        }
        coEvery { databaseRepository.getById(42L) } returns DittoDatabase(
            databaseId = "db-42",
            mode = AuthMode.SMALL_PEERS_ONLY,
            isBluetoothLeEnabled = false,
            isLanEnabled = false,
        )
        coEvery { dittoManager.hydrate(any()) } returns ditto
        every { dittoManager.currentInstance() } returns ditto
        coEvery { subscriptionsRepository.loadSubscriptions(any()) } returns emptyList()
        coEvery { observableRepository.loadObservables(any()) } returns emptyList()

        val session = newSession()
        session.hydrate()
        advanceUntilIdle()
        assertFalse(session.transportBluetoothEnabled.value)

        every { dittoManager.applyTransportConfig(any(), any()) } throws RuntimeException("SDK rejected")

        session.applyTransportSettings(bt = true, lan = true, wifiAware = true)
        advanceUntilIdle()

        // Sync + observers restart even though the apply threw mid-sequence.
        coVerify(exactly = 1) { dittoManager.startSync() }
        coVerify(exactly = 2) { systemRepository.startObserving(ditto) }
        // Flows show the persisted values, not the rejected request.
        assertFalse(session.transportBluetoothEnabled.value)
        assertFalse(session.transportLanEnabled.value)
        assertFalse(session.isApplyingTransport.value)
        // The failure surfaces via the error flow instead of being swallowed.
        assertNotNull(session.transportApplyError.value)
        assertTrue(
            "apply error should describe the apply failure: ${session.transportApplyError.value}",
            session.transportApplyError.value!!.contains("Failed to apply transport settings"),
        )
    }

    @Test
    fun `applyTransportSettings surfaces a restart failure and reflects real sync state`() = runTest {
        // updateTransportConfig does NOT validate multicast configs (the Kotlin
        // SDK sets them with should_validate=false), so an SDK-invalid config
        // persists fine and only throws at the sync restart. That failure must
        // not be swallowed: sync state mirrors the live instance, flows show
        // persisted values, and the error is surfaced.
        val ditto = mockk<com.ditto.kotlin.Ditto>(relaxed = true) {
            every { sync } returns mockk(relaxed = true)
            every { sync.isActive } returns false
        }
        coEvery { databaseRepository.getById(42L) } returns DittoDatabase(
            databaseId = "db-42",
            mode = AuthMode.SMALL_PEERS_ONLY,
        )
        coEvery { dittoManager.hydrate(any()) } returns ditto
        every { dittoManager.currentInstance() } returns ditto
        coEvery { subscriptionsRepository.loadSubscriptions(any()) } returns emptyList()
        coEvery { observableRepository.loadObservables(any()) } returns emptyList()

        val session = newSession()
        session.hydrate()
        advanceUntilIdle()
        assertTrue(session.syncEnabled.value)

        // Apply succeeds (config was set without validation), restart throws.
        every { dittoManager.applyTransportConfig(any(), any()) } returns Unit
        coEvery { dittoManager.startSync() } throws RuntimeException("multicast validation failed")

        session.applyTransportSettings(bt = true, lan = true, wifiAware = true)
        advanceUntilIdle()

        // Sync state mirrors the live instance — stopped — not the request.
        assertFalse(session.syncEnabled.value)
        // The transport settings WERE applied and persisted (updateTransportConfig
        // does not validate), so the flows show them — only the restart failed.
        assertTrue(session.transportBluetoothEnabled.value)
        assertTrue(session.transportWifiAwareEnabled.value)
        // The restart failure is surfaced, not swallowed.
        assertNotNull(session.transportApplyError.value)
        assertTrue(
            "error should describe the restart failure: ${session.transportApplyError.value}",
            session.transportApplyError.value!!.contains("sync failed to restart"),
        )
        assertFalse(session.isApplyingTransport.value)
    }

    @Test
    fun `applyTransportSettings clears the error flow on a fully successful apply`() = runTest {
        val ditto = mockk<com.ditto.kotlin.Ditto>(relaxed = true) {
            every { sync } returns mockk(relaxed = true)
            every { sync.isActive } returns true
        }
        coEvery { databaseRepository.getById(42L) } returns DittoDatabase(
            databaseId = "db-42",
            mode = AuthMode.SMALL_PEERS_ONLY,
        )
        coEvery { dittoManager.hydrate(any()) } returns ditto
        every { dittoManager.currentInstance() } returns ditto
        coEvery { subscriptionsRepository.loadSubscriptions(any()) } returns emptyList()
        coEvery { observableRepository.loadObservables(any()) } returns emptyList()
        every { dittoManager.applyTransportConfig(any(), any()) } returns Unit
        coEvery { dittoManager.startSync() } returns Unit

        val session = newSession()
        session.hydrate()
        advanceUntilIdle()

        session.applyTransportSettings(bt = false, lan = true, wifiAware = true)
        advanceUntilIdle()

        assertTrue(session.syncEnabled.value)
        assertFalse(session.transportBluetoothEnabled.value)
        assertTrue(session.transportWifiAwareEnabled.value)
        assertNull(session.transportApplyError.value)
        assertFalse(session.isApplyingTransport.value)
    }

    @Test
    fun `Logs save updates the config read on section reentry and the next transport save`() = runTest {
        val initial = DittoDatabase(id = 42L, databaseId = "db-42", logLevel = "info")
        val ditto = mockk<com.ditto.kotlin.Ditto>(relaxed = true)
        coEvery { databaseRepository.getById(42L) } returns initial
        coEvery { dittoManager.hydrate(any()) } returns ditto
        every { dittoManager.currentInstance() } returns ditto
        val writes = mutableListOf<DittoDatabase>()
        coEvery { databaseRepository.save(any()) } answers {
            writes += firstArg<DittoDatabase>()
            42L
        }
        val session = newSession()
        session.hydrate()
        advanceUntilIdle()

        // This is the exact callback wired by LoggingSection to LoggingScreen.
        session.saveLogLevel(com.ditto.kotlin.DittoLogLevel.Debug)
        assertEquals("debug", session.databaseConfig.value?.logLevel)
        assertEquals("debug", session.currentDatabase()?.logLevel)
        io.mockk.verify {
            dittoManager.refreshActiveConfigIfMatching(initial.copy(logLevel = "debug"))
        }

        session.applyTransportSettings(bt = false, lan = true, wifiAware = false)
        advanceUntilIdle()

        assertEquals(2, writes.size)
        assertEquals("debug", writes.last().logLevel)
        assertFalse(writes.last().isBluetoothLeEnabled)
        assertEquals(writes.last(), session.databaseConfig.value)
        session.close()
        advanceUntilIdle()
    }

    @Test
    fun `a transport apply queued behind a log-level save copies the newly saved level`() = runTest {
        val initial = DittoDatabase(id = 42L, databaseId = "db-42", logLevel = "info")
        val ditto = mockk<com.ditto.kotlin.Ditto>(relaxed = true)
        coEvery { databaseRepository.getById(42L) } returns initial
        coEvery { dittoManager.hydrate(any()) } returns ditto
        every { dittoManager.currentInstance() } returns ditto
        val saveGate = CompletableDeferred<Unit>()
        val writes = mutableListOf<DittoDatabase>()
        coEvery { databaseRepository.save(any()) } coAnswers {
            writes += firstArg<DittoDatabase>()
            if (writes.size == 1) saveGate.await()
            42L
        }
        val session = newSession()
        session.hydrate()
        advanceUntilIdle()

        val logSave = launch { session.saveLogLevel(com.ditto.kotlin.DittoLogLevel.Debug) }
        runCurrent()
        session.applyTransportSettings(bt = false, lan = false, wifiAware = false)
        runCurrent()
        assertEquals("transport save must wait for the log-level save", 1, writes.size)

        saveGate.complete(Unit)
        advanceUntilIdle()
        logSave.join()

        assertEquals(2, writes.size)
        assertEquals("debug", writes.last().logLevel)
        assertFalse(writes.last().isLanEnabled)
        assertEquals(writes.last(), session.databaseConfig.value)
        session.close()
        advanceUntilIdle()
    }

    @Test
    fun `metrics polling pauses when hidden and preserves accumulated deltas on reentry`() = runTest {
        val store = mockk<com.ditto.kotlin.DittoStore>()
        val ditto = mockk<com.ditto.kotlin.Ditto> { every { this@mockk.store } returns store }
        every { dittoManager.currentInstance() } returns ditto
        var reads = 0
        coEvery {
            store.execute(
                "SELECT * FROM system:metrics",
                any<com.ditto.kotlin.serialization.DittoCborSerializable.Dictionary>(),
                any<(com.ditto.kotlin.DittoQueryResult) -> List<Map<String, Any?>>>(),
            )
        } answers {
            reads++
            val delta = if (reads == 1) 7 else 3
            val item = mockk<com.ditto.kotlin.DittoQueryResultItem> {
                every { jsonString() } returns """{"key":"ditto.test.counter","delta":$delta}"""
            }
            val result = mockk<com.ditto.kotlin.DittoQueryResult> { every { items } returns listOf(item) }
            thirdArg<(com.ditto.kotlin.DittoQueryResult) -> List<Map<String, Any?>>>().invoke(result)
        }
        val session = newSession()
        session.startSystemMetricsPolling()
        runCurrent()
        val first = session.systemMetrics.value
        assertEquals(7.0, first.samples.single().sinceConnect, 0.0)
        assertTrue(first.sinceMs > 0)

        session.stopSystemMetricsPolling()
        runCurrent()
        advanceTimeBy(15_000)
        runCurrent()
        assertEquals("hidden dashboard must not consume SDK deltas", 1, reads)
        assertEquals(first, session.systemMetrics.value)

        session.startSystemMetricsPolling()
        runCurrent()
        val resumed = session.systemMetrics.value
        assertEquals(10.0, resumed.samples.single().sinceConnect, 0.0)
        assertEquals(3.0, resumed.samples.single().periodDelta, 0.0)
        assertEquals(first.sinceMs, resumed.sinceMs)
        session.close()
        advanceUntilIdle()
        assertTrue(session.systemMetrics.value.samples.isEmpty())
        assertEquals(0L, session.systemMetrics.value.sinceMs)
    }

    @Test
    fun `a new session starts metrics accumulation from its own first delta`() = runTest {
        val store = mockk<com.ditto.kotlin.DittoStore>()
        val ditto = mockk<com.ditto.kotlin.Ditto> { every { this@mockk.store } returns store }
        every { dittoManager.currentInstance() } returns ditto
        val item = mockk<com.ditto.kotlin.DittoQueryResultItem> {
            every { jsonString() } returns """{"key":"ditto.test.counter","delta":4}"""
        }
        val result = mockk<com.ditto.kotlin.DittoQueryResult> { every { items } returns listOf(item) }
        coEvery {
            store.execute(
                "SELECT * FROM system:metrics",
                any<com.ditto.kotlin.serialization.DittoCborSerializable.Dictionary>(),
                any<(com.ditto.kotlin.DittoQueryResult) -> List<Map<String, Any?>>>(),
            )
        } answers {
            thirdArg<(com.ditto.kotlin.DittoQueryResult) -> List<Map<String, Any?>>>().invoke(result)
        }
        val first = newSession()
        first.startSystemMetricsPolling()
        runCurrent()
        advanceTimeBy(5_000)
        runCurrent()
        assertEquals(8.0, first.systemMetrics.value.samples.single().sinceConnect, 0.0)
        first.close()
        advanceUntilIdle()

        val reopened = newSession()
        reopened.startSystemMetricsPolling()
        runCurrent()
        assertEquals(4.0, reopened.systemMetrics.value.samples.single().sinceConnect, 0.0)
        reopened.close()
        advanceUntilIdle()
    }

    @Test
    fun `concurrent hydrate calls run DittoManager hydrate exactly once`() = runTest {
        // Two MainStudioViewModel instances (activity-store + entry-store) constructed in
        // the same composition pass both call hydrate() from init. The second must join
        // the in-flight run, not race a second DittoManager.hydrate on the same directory.
        val session = newSession()
        val gate = CompletableDeferred<Unit>()
        coEvery { databaseRepository.getById(42L) } returns DittoDatabase(
            databaseId = "db-42",
            mode = AuthMode.SMALL_PEERS_ONLY,
        )
        coEvery { dittoManager.hydrate(any()) } coAnswers {
            // Hold the first hydrate open so the second call overlaps in flight.
            gate.await()
            mockk(relaxed = true)
        }
        coEvery { subscriptionsRepository.loadSubscriptions(any()) } returns emptyList()
        coEvery { observableRepository.loadObservables(any()) } returns emptyList()

        session.hydrate()
        session.hydrate()
        // First hydrate is parked on the gate inside dittoManager.hydrate; the second
        // must be parked on the in-flight guard — not inside DittoManager.
        runCurrent()

        gate.complete(Unit)
        advanceUntilIdle()

        coVerify(exactly = 1) { dittoManager.hydrate(any()) }
        assertEquals("db-42", session.currentDittoId)
        assertEquals("db-42", session.currentDittoIdFlow.value)
        assertNull(session.hydrateError)
    }

    @Test
    fun `delayed old teardown cannot close a newly opened different database`() = runTest {
        // Hold only the teardown queue, before it enters the REAL manager.close().
        // A mock that suspends inside close would miss this ownership boundary.
        val teardownScheduler = TestCoroutineScheduler()
        val heldTeardown = StandardTestDispatcher(teardownScheduler)
        dittoManager = DittoManager(CoroutineScope(SupervisorJob() + Dispatchers.Default))
        val oldInstance = mockSdkInstance()
        val newInstance = mockSdkInstance()
        val opened = Channel<Ditto>(Channel.UNLIMITED)
        every { systemRepository.startObserving(any()) } answers {
            opened.trySend(firstArg())
            Unit
        }
        for (id in listOf(42L, 7L)) {
            coEvery { databaseRepository.getById(id) } returns DittoDatabase(
                id = id,
                databaseId = "db-$id",
                mode = AuthMode.SMALL_PEERS_ONLY,
            )
        }
        coEvery { subscriptionsRepository.loadSubscriptions(any()) } returns emptyList()
        coEvery { observableRepository.loadObservables(any()) } returns emptyList()
        mockkObject(DittoFactory)
        coEvery { DittoFactory.create(any<DittoConfig>(), any()) } returnsMany listOf(oldInstance, newInstance)
        val oldSession = newSession(42L, Dispatchers.Default, heldTeardown)
        val newSession = newSession(7L, Dispatchers.Default, heldTeardown)
        try {
            oldSession.hydrate()
            withContext(Dispatchers.Default) {
                withTimeout(5_000) { assertSame(oldInstance, opened.receive()) }
            }
            oldSession.close()
            assertTrue(DittoTeardownRegistry.inFlightJob(42L)?.isActive == true)

            // This is the picker opening B after closing A. B's production hydrate
            // waits only for B's registry key, and the real manager replaces A.
            newSession.hydrate()
            withContext(Dispatchers.Default) {
                withTimeout(5_000) { assertSame(newInstance, opened.receive()) }
            }
            assertSame(newInstance, dittoManager.currentInstance())
            assertEquals(7L, dittoManager.currentDatabase()?.id)

            // Now allow the old session's actual teardown to enter manager.close.
            teardownScheduler.runCurrent()
            assertSame("Old session teardown must not detach the new database", newInstance, dittoManager.currentInstance())
        } finally {
            oldSession.close()
            newSession.close()
            withContext(Dispatchers.Default) {
                withTimeout(5_000) {
                    do {
                        teardownScheduler.runCurrent()
                        delay(10)
                    } while (listOf(42L, 7L).any { DittoTeardownRegistry.inFlightJob(it)?.isActive == true })
                }
            }
            opened.close()
            unmockkObject(DittoFactory)
        }
    }

    /** Mock only the SDK boundary; session ownership and manager lifecycle stay real. */
    private fun mockSdkInstance(): Ditto {
        val store = mockk<DittoStore>(relaxed = true)
        coEvery {
            store.execute(any<String>(), any<Map<String, Any?>>(), any<(DittoQueryResult) -> Any?>())
        } answers {
            thirdArg<(DittoQueryResult) -> Any?>().invoke(mockk<DittoQueryResult>(relaxed = true) {
                every { items } returns emptyList()
            })
        }
        return mockk(relaxed = true) {
            every { this@mockk.store } returns store
        }
    }

    @Test
    fun `hydrate awaits in-flight close for the same database`() = runTest {
        // Session A: arrange a close that suspends indefinitely on a gate.
        val sessionA = newSession(databaseId = 42L)
        val gate = CompletableDeferred<Unit>()
        coEvery { dittoManager.closeIfCurrent(any()) } coAnswers { gate.await() }

        sessionA.close()
        runCurrent()
        assertTrue(DittoTeardownRegistry.inFlightJob(42L)?.isActive == true)

        // Session B for the same databaseId: hydrate should suspend until A's close finishes.
        // Reset close mock so the new session's close() (if any) does not deadlock subsequent tests;
        // hydrate() itself only calls dittoManager.hydrate().
        val sessionB = newSession(databaseId = 42L)
        coEvery { databaseRepository.getById(42L) } returns DittoDatabase(
            databaseId = "db-42",
            mode = AuthMode.SMALL_PEERS_ONLY,
        )
        coEvery { dittoManager.hydrate(any()) } returns mockk(relaxed = true)
        coEvery { subscriptionsRepository.loadSubscriptions(any()) } returns emptyList()
        coEvery { observableRepository.loadObservables(any()) } returns emptyList()

        sessionB.hydrate()
        // Pump pending coroutines *within* the await window; B must be parked on the registry
        // await — hydrate must NOT have opened yet.
        advanceTimeBy(DittoTeardownRegistry.AWAIT_CLOSE_TIMEOUT_MS / 2)
        runCurrent()
        coVerify(exactly = 0) { dittoManager.hydrate(any()) }

        // Release A's close; B's hydrate is now free to proceed and call dittoManager.hydrate().
        gate.complete(Unit)
        advanceUntilIdle()
        coVerify(exactly = 1) { dittoManager.hydrate(any()) }
    }

    @Test
    fun `hydrate proceeds when a previous close is wedged past the await timeout`() = runTest {
        // Regression guard. Ditto.close() blocks while any read transaction is still open, so a
        // single leaked transaction used to hang awaitCloseFor forever — and with it every later
        // hydrate for that database. The studio then showed no collections, no subscriptions and
        // a permanent Query Workbench spinner that survived backing out and re-entering. The
        // await is now bounded: a wedged close degrades to "open anyway", never to a brick.
        val sessionA = newSession(databaseId = 42L)
        val gate = CompletableDeferred<Unit>()
        coEvery { dittoManager.closeIfCurrent(any()) } coAnswers { gate.await() }

        sessionA.close()
        runCurrent()
        assertTrue(DittoTeardownRegistry.inFlightJob(42L)?.isActive == true)

        val sessionB = newSession(databaseId = 42L)
        coEvery { databaseRepository.getById(42L) } returns DittoDatabase(
            databaseId = "db-42",
            mode = AuthMode.SMALL_PEERS_ONLY,
        )
        coEvery { dittoManager.hydrate(any()) } returns mockk(relaxed = true)
        coEvery { subscriptionsRepository.loadSubscriptions(any()) } returns emptyList()
        coEvery { observableRepository.loadObservables(any()) } returns emptyList()

        sessionB.hydrate()
        // A's close never completes. Past the timeout, B must open rather than hang forever.
        advanceTimeBy(DittoTeardownRegistry.AWAIT_CLOSE_TIMEOUT_MS + 1_000)
        advanceUntilIdle()

        coVerify(exactly = 1) { dittoManager.hydrate(any()) }
        assertEquals("db-42", sessionB.currentDittoId)
        // A's close is still genuinely in flight — we proceeded past it, we did not abandon it.
        assertTrue(DittoTeardownRegistry.inFlightJob(42L)?.isActive == true)

        // Let the parked close finish so it does not leak into sibling tests.
        gate.complete(Unit)
        advanceUntilIdle()
    }
}
