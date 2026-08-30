package com.costoda.dittoedgestudio.viewmodel

import androidx.lifecycle.SavedStateHandle
import com.costoda.dittoedgestudio.data.ditto.DittoManager
import com.costoda.dittoedgestudio.data.logging.DittoLogCaptureService
import com.costoda.dittoedgestudio.data.repository.CollectionsRepository
import com.costoda.dittoedgestudio.data.repository.DatabaseRepository
import com.costoda.dittoedgestudio.data.repository.NetworkDiagnosticsRepository
import com.costoda.dittoedgestudio.data.repository.ObservableRepository
import com.costoda.dittoedgestudio.data.repository.SubscriptionsRepository
import com.costoda.dittoedgestudio.data.repository.SystemRepository
import com.costoda.dittoedgestudio.data.session.PeersUiState
import com.costoda.dittoedgestudio.data.session.StudioSession
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
    private val meshTopologyFlow =
        MutableStateFlow(com.costoda.dittoedgestudio.domain.model.MeshTopology.Empty)
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
        every { systemRepository.meshTopology } returns meshTopologyFlow
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

        val session99 = createSession(databaseId = 99L)
        val vm = MainStudioViewModel(
            sessionProvider = { session99 },
            savedStateHandle = SavedStateHandle(),
        )
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
    fun `showDirectConnectedOnly defaults to true`() = runTest {
        val vm = createViewModel()
        assertTrue(vm.showDirectConnectedOnly.value)
    }

    @Test
    fun `toggleDirectConnectedOnly flips the flag`() = runTest {
        val vm = createViewModel()
        assertTrue(vm.showDirectConnectedOnly.value)
        vm.toggleDirectConnectedOnly()
        assertEquals(false, vm.showDirectConnectedOnly.value)
        vm.toggleDirectConnectedOnly()
        assertTrue(vm.showDirectConnectedOnly.value)
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

    private fun createSession(databaseId: Long = 1L): StudioSession = StudioSession(
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
        },
        context = mockk(relaxed = true),
        ioDispatcher = testDispatcher,
    )

    private fun createViewModel(savedStateHandle: SavedStateHandle = SavedStateHandle()): MainStudioViewModel {
        val session = createSession()
        return MainStudioViewModel(
            sessionProvider = { session },
            savedStateHandle = savedStateHandle,
        )
    }

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

    @Test
    fun `state initializes from a pre-populated SavedStateHandle`() = runTest {
        val handle = SavedStateHandle(
            mapOf(
                MainStudioViewModel.KEY_SELECTED_NAV to StudioNavItem.QUERY.name,
            )
        )

        val vm = createViewModel(savedStateHandle = handle)
        // No need to advance — these are read directly from the handle, not from a coroutine

        assertEquals(StudioNavItem.QUERY, vm.selectedNavItem)
    }

    @Test
    fun `mutations write back to the SavedStateHandle`() = runTest {
        val handle = SavedStateHandle()
        val vm = createViewModel(savedStateHandle = handle)

        vm.selectedNavItem = StudioNavItem.OBSERVERS

        assertEquals(StudioNavItem.OBSERVERS.name, handle.get<String>(MainStudioViewModel.KEY_SELECTED_NAV))
    }

    @Test
    fun `stale saved state with nonexistent nav item falls back to SUBSCRIPTIONS without crashing`() = runTest {
        val handle = SavedStateHandle(
            mapOf(
                MainStudioViewModel.KEY_SELECTED_NAV to "NONEXISTENT_SECTION",
            )
        )

        val vm = createViewModel(savedStateHandle = handle)
        // Should not throw IllegalArgumentException from valueOf()

        assertEquals(StudioNavItem.SUBSCRIPTIONS, vm.selectedNavItem)
    }

    // ── Fix 1: ephemeral UI state survives section switch (shared session) ────

    @Test
    fun `selectedObserver set via VM A is visible via VM B sharing the same session`() = runTest {
        val sharedSession = createSession()
        val vmA = MainStudioViewModel(sessionProvider = { sharedSession }, savedStateHandle = SavedStateHandle())
        val vmB = MainStudioViewModel(sessionProvider = { sharedSession }, savedStateHandle = SavedStateHandle())

        val observer = DittoObservable(id = 42, databaseId = "test-db-id", name = "Obs", query = "SELECT * FROM c")
        vmA.selectedObserver = observer

        // VM B reads the same session.uiState — value must be the one VM A wrote.
        assertEquals(observer, vmB.selectedObserver)
    }

    @Test
    fun `eventCurrentPage set via VM A is visible via VM B sharing the same session`() = runTest {
        val sharedSession = createSession()
        val vmA = MainStudioViewModel(sessionProvider = { sharedSession }, savedStateHandle = SavedStateHandle())
        val vmB = MainStudioViewModel(sessionProvider = { sharedSession }, savedStateHandle = SavedStateHandle())

        vmA.eventCurrentPage = 3

        assertEquals(3, vmB.eventCurrentPage)
    }

    @Test
    fun `ephemeral state in session is independent from another session`() = runTest {
        val sessionA = createSession(databaseId = 1L)
        val sessionB = createSession(databaseId = 1L) // separate instance
        val vmA = MainStudioViewModel(sessionProvider = { sessionA }, savedStateHandle = SavedStateHandle())
        val vmB = MainStudioViewModel(sessionProvider = { sessionB }, savedStateHandle = SavedStateHandle())

        val observer = DittoObservable(id = 7, databaseId = "test-db-id", name = "X", query = "SELECT * FROM t")
        vmA.selectedObserver = observer

        // Different session instance — vmB must not see vmA's state.
        assertEquals(null, vmB.selectedObserver)
    }

    // ── executeModes derivation ──────────────────────────────────────────────

    @Test
    fun `executeModes is Local only when httpApiUrl is blank`() = runTest {
        coEvery { databaseRepository.getById(1L) } returns testDatabase.copy(
            httpApiUrl = "",
            httpApiKey = "key",
        )

        val vm = createViewModel()
        advanceUntilIdle()

        assertEquals(listOf("Local"), vm.session.uiState.queryWorkbench.executeModes.value)
    }

    @Test
    fun `executeModes is Local only when httpApiKey is blank`() = runTest {
        coEvery { databaseRepository.getById(1L) } returns testDatabase.copy(
            httpApiUrl = "host.example",
            httpApiKey = "",
        )

        val vm = createViewModel()
        advanceUntilIdle()

        assertEquals(listOf("Local"), vm.session.uiState.queryWorkbench.executeModes.value)
    }

    @Test
    fun `executeModes is Local and HTTP when both are set`() = runTest {
        coEvery { databaseRepository.getById(1L) } returns testDatabase.copy(
            httpApiUrl = "host.example",
            httpApiKey = "k",
        )

        val vm = createViewModel()
        advanceUntilIdle()

        assertEquals(listOf("Local", "HTTP"), vm.session.uiState.queryWorkbench.executeModes.value)
    }

    @Test
    fun `executeMode resets to Local when HTTP drops out of executeModes`() = runTest {
        // Start with HTTP available + selected.
        coEvery { databaseRepository.getById(1L) } returns testDatabase.copy(
            httpApiUrl = "host.example",
            httpApiKey = "k",
        )
        val vm = createViewModel()
        advanceUntilIdle()
        vm.session.uiState.queryWorkbench.executeMode.value = "HTTP"

        // Then re-hydrate with HTTP removed — VM-side hook re-derives executeModes and
        // sees "HTTP" is no longer valid → resets to "Local".
        coEvery { databaseRepository.getById(1L) } returns testDatabase.copy(
            httpApiUrl = "",
            httpApiKey = "k",
        )
        vm.session.hydrate()
        advanceUntilIdle()

        assertEquals(listOf("Local"), vm.session.uiState.queryWorkbench.executeModes.value)
        assertEquals("Local", vm.session.uiState.queryWorkbench.executeMode.value)
    }
}
