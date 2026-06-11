package com.costoda.dittoedgestudio.data.session

import com.costoda.dittoedgestudio.data.ditto.DittoManager
import com.costoda.dittoedgestudio.data.logging.DittoLogCaptureService
import com.costoda.dittoedgestudio.data.repository.CollectionsRepository
import com.costoda.dittoedgestudio.data.repository.DatabaseRepository
import com.costoda.dittoedgestudio.data.repository.NetworkDiagnosticsRepository
import com.costoda.dittoedgestudio.data.repository.ObservableRepository
import com.costoda.dittoedgestudio.data.repository.SubscriptionsRepository
import com.costoda.dittoedgestudio.data.repository.SystemRepository
import com.costoda.dittoedgestudio.domain.model.ConnectionsByTransport
import com.costoda.dittoedgestudio.domain.model.DittoCollection
import com.costoda.dittoedgestudio.domain.model.LocalPeerInfo
import com.costoda.dittoedgestudio.domain.model.SyncStatusInfo
import io.mockk.coVerify
import io.mockk.coEvery
import io.mockk.every
import io.mockk.mockk
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
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
    }

    private fun newSession(): StudioSession = StudioSession(
        databaseId = 42L,
        databaseRepository = databaseRepository,
        dittoManager = dittoManager,
        systemRepository = systemRepository,
        networkRepo = networkRepo,
        subscriptionsRepository = subscriptionsRepository,
        collectionsRepository = collectionsRepository,
        loggingCaptureService = logCaptureService,
        observableRepository = observableRepository,
        ioDispatcher = testDispatcher,
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
}
