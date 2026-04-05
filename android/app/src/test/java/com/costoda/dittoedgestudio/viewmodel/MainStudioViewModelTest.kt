package com.costoda.dittoedgestudio.viewmodel

import com.costoda.dittoedgestudio.data.ditto.DittoManager
import com.costoda.dittoedgestudio.data.logging.DittoLogCaptureService
import com.costoda.dittoedgestudio.data.repository.CollectionsRepository
import com.costoda.dittoedgestudio.data.repository.DatabaseRepository
import com.costoda.dittoedgestudio.data.repository.NetworkDiagnosticsRepository
import com.costoda.dittoedgestudio.data.repository.ObservableRepository
import com.costoda.dittoedgestudio.data.repository.SubscriptionsRepository
import com.costoda.dittoedgestudio.data.repository.SystemRepository
import com.costoda.dittoedgestudio.domain.model.DittoCollection
import com.costoda.dittoedgestudio.domain.model.ConnectionsByTransport
import com.costoda.dittoedgestudio.domain.model.DittoDatabase
import com.costoda.dittoedgestudio.domain.model.DittoObservable
import com.costoda.dittoedgestudio.domain.model.LocalPeerInfo
import com.costoda.dittoedgestudio.domain.model.NetworkInterfaceInfo
import com.costoda.dittoedgestudio.domain.model.P2PTransportInfo
import com.costoda.dittoedgestudio.domain.model.SyncStatusInfo
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.every
import io.mockk.mockk
import io.mockk.verify
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import com.ditto.kotlin.Ditto
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class MainStudioViewModelTest {

    private val testDispatcher = StandardTestDispatcher()

    private lateinit var databaseRepository: DatabaseRepository
    private lateinit var dittoManager: DittoManager
    private lateinit var systemRepository: SystemRepository
    private lateinit var networkRepo: NetworkDiagnosticsRepository
    private lateinit var subscriptionsRepository: SubscriptionsRepository
    private lateinit var collectionsRepository: CollectionsRepository
    private lateinit var logCaptureService: DittoLogCaptureService
    private lateinit var observableRepository: ObservableRepository
    private lateinit var mockDitto: Ditto

    private val localPeerFlow = MutableStateFlow<LocalPeerInfo?>(null)
    private val peersFlow = MutableStateFlow<List<SyncStatusInfo>>(emptyList())
    private val connectionsFlow = MutableStateFlow(ConnectionsByTransport.Empty)
    private val collectionsFlow = MutableStateFlow<List<DittoCollection>>(emptyList())

    private val testDatabase = DittoDatabase(
        id = 1L,
        name = "Test DB",
        databaseId = "test-db-id",
        isBluetoothLeEnabled = true,
        isLanEnabled = true,
        isAwdlEnabled = false,
        isCloudSyncEnabled = true,
    )

    @Before
    fun setUp() {
        Dispatchers.setMain(testDispatcher)

        databaseRepository = mockk()
        dittoManager = mockk(relaxed = true)
        systemRepository = mockk(relaxed = true)
        networkRepo = mockk(relaxed = true)
        subscriptionsRepository = mockk(relaxed = true)
        collectionsRepository = mockk(relaxed = true)
        logCaptureService = mockk(relaxed = true)
        observableRepository = mockk()
        coEvery { observableRepository.loadObservables(any()) } returns emptyList()
        mockDitto = mockk(relaxed = true)

        coEvery { subscriptionsRepository.loadSubscriptions(any()) } returns emptyList()

        every { systemRepository.localPeer } returns localPeerFlow
        every { systemRepository.peers } returns peersFlow
        every { systemRepository.connectionsByTransport } returns connectionsFlow
        every { collectionsRepository.collections } returns collectionsFlow
        every { networkRepo.hasLocationOrNearbyPermission() } returns false

        coEvery { databaseRepository.getById(1L) } returns testDatabase
        coEvery { dittoManager.hydrate(any()) } returns mockDitto
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
    }

    @Test
    fun `hydrate calls dittoManager_hydrate and systemRepository_startObserving`() = runTest {
        val vm = createViewModel()
        advanceUntilIdle()

        coVerify { dittoManager.hydrate(testDatabase) }
        verify { systemRepository.startObserving(mockDitto) }
        assertTrue(vm.syncEnabled)
    }

    @Test
    fun `hydrate sets syncEnabled true on success`() = runTest {
        val vm = createViewModel()
        advanceUntilIdle()

        assertTrue(vm.syncEnabled)
    }

    @Test
    fun `hydrate sets hydrateError when database not found`() = runTest {
        coEvery { databaseRepository.getById(99L) } returns null

        val vm = MainStudioViewModel(99L, databaseRepository, dittoManager, systemRepository, networkRepo, subscriptionsRepository, collectionsRepository, logCaptureService, observableRepository)
        advanceUntilIdle()

        assertNotNull(vm.hydrateError)
    }

    @Test
    fun `peersUiState is Initializing before hydration completes`() = runTest {
        // Don't advance idle — check initial state
        val vm = createViewModel()

        // Initial state is Initializing (before coroutine runs)
        val initial = vm.peersUiState.value
        assertTrue(initial is PeersUiState.Initializing)
    }

    @Test
    fun `peersUiState is Active when localPeer emits`() = runTest {
        val vm = createViewModel()
        // Subscribe to activate WhileSubscribed sharing
        val collectionJob = launch { vm.peersUiState.collect {} }
        advanceUntilIdle()

        val localPeer = LocalPeerInfo("peer-id", "Test Device", "Kotlin", "Android", "5.0.0")
        localPeerFlow.value = localPeer
        advanceUntilIdle()

        val state = vm.peersUiState.value
        assertTrue(state is PeersUiState.Active)
        assertEquals(localPeer, (state as PeersUiState.Active).localPeer)
        collectionJob.cancel()
    }

    @Test
    fun `loadNetworkDiagnostics populates networkInterfaces and p2pTransports`() = runTest {
        val mockInterfaces = listOf(
            NetworkInterfaceInfo(
                id = "wlan0",
                interfaceName = "wlan0",
                kind = NetworkInterfaceInfo.InterfaceKind.Wifi,
                isActive = true,
                hardwareAddress = null,
                mtu = null,
                ipv4Address = null,
                ipv6Address = null,
                gatewayAddress = null,
                ssid = null,
                bssid = null,
                rssi = null,
                signalLevel = null,
                linkSpeedMbps = null,
                txLinkSpeedMbps = null,
                rxLinkSpeedMbps = null,
                frequencyMhz = null,
                frequencyBandLabel = null,
                wifiStandardLabel = null,
                ethernetBandwidthKbps = null,
                locationPermissionGranted = false,
            ),
        )
        val mockTransports = listOf(
            P2PTransportInfo(
                kind = P2PTransportInfo.Kind.WifiAware,
                isHardwareAvailable = true,
                isEnabled = true,
                statusDetail = "Available",
            ),
        )
        coEvery { networkRepo.fetchInterfaces() } returns mockInterfaces
        coEvery { networkRepo.fetchP2PTransports() } returns mockTransports

        val vm = createViewModel()
        advanceUntilIdle()

        vm.loadNetworkDiagnostics()
        advanceUntilIdle()

        assertEquals(mockInterfaces, vm.networkInterfaces.value)
        assertEquals(mockTransports, vm.p2pTransports.value)
    }

    @Test
    fun `applyTransportSettings updates local state and calls dittoManager`() = runTest {
        every { dittoManager.currentInstance() } returns mockDitto
        coEvery { databaseRepository.save(any()) } returns 1L

        val vm = createViewModel()
        advanceUntilIdle()

        vm.applyTransportSettings(bt = false, lan = true, wifiAware = true)
        advanceUntilIdle()

        assertFalse(vm.transportBluetoothEnabled)
        assertTrue(vm.transportLanEnabled)
        assertTrue(vm.transportWifiAwareEnabled)
        assertFalse(vm.transportConfigVisible)
        verify { dittoManager.applyTransportConfig(mockDitto, any()) }
        coVerify { databaseRepository.save(any()) }
    }

    private fun createViewModel() = MainStudioViewModel(
        databaseId = 1L,
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
    fun `hydrate loads observers from repository`() = runTest {
        val obs = listOf(DittoObservable(id = 1, databaseId = "test-db-id", name = "Obs1", query = "SELECT * FROM c"))
        coEvery { observableRepository.loadObservables("test-db-id") } returns obs

        val vm = createViewModel()
        advanceUntilIdle()

        assertEquals(1, vm.observers.value.size)
        assertEquals("Obs1", vm.observers.value[0].name)
    }

    @Test
    fun `addObserver saves to repository and updates state`() = runTest {
        every { dittoManager.currentInstance() } returns mockDitto
        val vm = createViewModel()
        advanceUntilIdle()

        coEvery { observableRepository.saveObservable(any()) } returns 10L
        coEvery { observableRepository.loadObservables(any()) } returns listOf(
            DittoObservable(id = 10, databaseId = "test-db-id", name = "New", query = "SELECT * FROM t"),
        )

        vm.addObserver("New", "SELECT * FROM t")
        advanceUntilIdle()

        coVerify { observableRepository.saveObservable(any()) }
        assertEquals(1, vm.observers.value.size)
    }

    @Test
    fun `removeObserver deletes from repository and updates state`() = runTest {
        val obs = DittoObservable(id = 5, databaseId = "test-db-id", name = "Obs", query = "SELECT * FROM c")
        coEvery { observableRepository.loadObservables(any()) } returns listOf(obs)

        val vm = createViewModel()
        advanceUntilIdle()

        coEvery { observableRepository.removeObservable(any()) } returns Unit
        coEvery { observableRepository.loadObservables(any()) } returns emptyList()
        vm.removeObserver(obs)
        advanceUntilIdle()

        coVerify { observableRepository.removeObservable(5) }
        assertTrue(vm.observers.value.isEmpty())
    }
}
