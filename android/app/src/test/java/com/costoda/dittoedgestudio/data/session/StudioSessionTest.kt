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
import io.mockk.coVerify
import io.mockk.coEvery
import io.mockk.every
import io.mockk.mockk
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.StandardTestDispatcher
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

    private fun newSession(databaseId: Long = 42L): StudioSession = StudioSession(
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
        ioDispatcher = testDispatcher,
        teardownDispatcher = testDispatcher,
    )

    @Test
    fun `close is idempotent - dittoManager close called exactly once`() = runTest {
        val session = newSession()
        coEvery { dittoManager.close() } returns Unit

        // First close
        session.close()
        assertTrue(session.isClosed())

        // Subsequent closes are no-ops
        session.close()
        session.close()

        // Teardown is dispatched to the testDispatcher; drive it to completion.
        advanceUntilIdle()

        // Verify Ditto was closed exactly once across all three calls
        coVerify(exactly = 1) { dittoManager.close() }
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
        coEvery { dittoManager.close() } returns Unit

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
        coEvery { dittoManager.close() } coAnswers { gate.await() }

        // Call close(); it must RETURN even though dittoManager.close() is still suspended on the gate.
        session.close()

        // The session is marked closed synchronously, and the teardown job is registered.
        assertTrue(session.isClosed())
        val teardownJob = DittoTeardownRegistry.inFlightJob(42L)
        assertNotNull("teardown job should be registered", teardownJob)
        // Drive the dispatcher just enough to actually invoke dittoManager.close() — it must
        // suspend on the gate, NOT complete.
        runCurrent()
        assertTrue("teardown should still be suspended on the gate", teardownJob!!.isActive)

        // Release the gate; teardown completes; registry clears the entry.
        gate.complete(Unit)
        advanceUntilIdle()
        assertTrue("teardown should have completed", teardownJob.isCompleted)
        assertNull(DittoTeardownRegistry.inFlightJob(42L))
        coVerify(exactly = 1) { dittoManager.close() }
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
        coEvery { dittoManager.close() } returns Unit
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
    fun `hydrate awaits in-flight close for the same database`() = runTest {
        // Session A: arrange a close that suspends indefinitely on a gate.
        val sessionA = newSession(databaseId = 42L)
        val gate = CompletableDeferred<Unit>()
        coEvery { dittoManager.close() } coAnswers { gate.await() }

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
        coEvery { dittoManager.close() } coAnswers { gate.await() }

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
