package com.costoda.dittoedgestudio.viewmodel

import com.costoda.dittoedgestudio.data.repository.DatabaseRepository
import com.costoda.dittoedgestudio.domain.model.AuthMode
import com.costoda.dittoedgestudio.domain.model.DittoDatabase
import com.costoda.dittoedgestudio.domain.model.StartupSetting
import com.costoda.dittoedgestudio.domain.model.StartupSettingType
import com.costoda.dittoedgestudio.domain.model.SyncScope
import io.mockk.MockKAnnotations
import io.mockk.clearAllMocks
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.impl.annotations.MockK
import io.mockk.slot
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
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
class DatabaseEditorViewModelTest {

    @MockK
    private lateinit var repository: DatabaseRepository
    private val testDispatcher = StandardTestDispatcher()

    @Before
    fun setup() {
        MockKAnnotations.init(this)
        Dispatchers.setMain(testDispatcher)
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
        clearAllMocks()
    }

    private fun newItemViewModel(): DatabaseEditorViewModel {
        coEvery { repository.getAll() } returns emptyList()
        return DatabaseEditorViewModel(-1L, repository)
    }

    private fun editItemViewModel(id: Long, db: DittoDatabase): DatabaseEditorViewModel {
        coEvery { repository.getAll() } returns listOf(db)
        return DatabaseEditorViewModel(id, repository)
    }

    @Test
    fun `canSave is false when name is blank`() = runTest {
        val vm = newItemViewModel()
        vm.databaseId.value = "db-id"
        vm.token.value = "token"
        vm.name.value = ""
        testDispatcher.scheduler.advanceUntilIdle()

        assertFalse(vm.canSave.value)
    }

    @Test
    fun `canSave is false when databaseId is blank`() = runTest {
        val vm = newItemViewModel()
        vm.name.value = "My DB"
        vm.token.value = "token"
        vm.databaseId.value = ""
        testDispatcher.scheduler.advanceUntilIdle()

        assertFalse(vm.canSave.value)
    }

    @Test
    fun `canSave is false when token is blank`() = runTest {
        val vm = newItemViewModel()
        vm.name.value = "My DB"
        vm.databaseId.value = "db-id"
        vm.token.value = ""
        testDispatcher.scheduler.advanceUntilIdle()

        assertFalse(vm.canSave.value)
    }

    @Test
    fun `canSave is true when all required fields are populated`() = runTest {
        val vm = newItemViewModel()
        vm.name.value = "My DB"
        vm.databaseId.value = "db-id"
        vm.token.value = "my-token"
        testDispatcher.scheduler.advanceUntilIdle()

        assertTrue(vm.canSave.value)
    }

    @Test
    fun `save calls repository with correct DittoDatabase for new item with id 0`() = runTest {
        val vm = newItemViewModel()
        vm.name.value = "New DB"
        vm.databaseId.value = "new-db-id"
        vm.token.value = "new-token"

        val captured = slot<DittoDatabase>()
        coEvery { repository.save(capture(captured)) } returns 1L

        vm.save()
        testDispatcher.scheduler.advanceUntilIdle()

        coVerify(exactly = 1) { repository.save(any()) }
        assertEquals(0L, captured.captured.id)
        assertEquals("New DB", captured.captured.name)
        assertEquals("new-db-id", captured.captured.databaseId)
    }

    @Test
    fun `save calls repository update when editing existing item with non-zero id`() = runTest {
        val existingDb = DittoDatabase(id = 5L, name = "Existing", databaseId = "ex-id", token = "ex-token")
        val vm = editItemViewModel(5L, existingDb)
        testDispatcher.scheduler.advanceUntilIdle()

        val captured = slot<DittoDatabase>()
        coEvery { repository.save(capture(captured)) } returns 5L

        vm.save()
        testDispatcher.scheduler.advanceUntilIdle()

        coVerify(exactly = 1) { repository.save(any()) }
        assertEquals(5L, captured.captured.id)
    }

    @Test
    fun `save preserves transport and multicast fields the editor does not own`() = runTest {
        // Regression: save() used to build a fresh DittoDatabase from editor fields
        // only, so every non-editor column (transports, multicast, websocketUrl)
        // reverted to data-class defaults on each edit-save.
        val existingDb = DittoDatabase(
            id = 5L,
            name = "Existing",
            databaseId = "ex-id",
            token = "ex-token",
            websocketUrl = "wss://custom.example.com",
            isBluetoothLeEnabled = false,
            isLanEnabled = false,
            isAwdlEnabled = true,
            isCloudSyncEnabled = false,
            isMulticastEnabled = true,
            multicastGroupAddress = "239.1.2.3",
            multicastPort = 7000,
            multicastInterfaceName = "en0",
        )
        val vm = editItemViewModel(5L, existingDb)
        testDispatcher.scheduler.advanceUntilIdle()

        val captured = slot<DittoDatabase>()
        coEvery { repository.save(capture(captured)) } returns 5L

        vm.name.value = "Renamed"
        assertTrue(vm.save())
        testDispatcher.scheduler.advanceUntilIdle()

        val saved = captured.captured
        assertEquals("Renamed", saved.name)
        assertEquals("wss://custom.example.com", saved.websocketUrl)
        assertFalse(saved.isBluetoothLeEnabled)
        assertFalse(saved.isLanEnabled)
        assertTrue(saved.isAwdlEnabled)
        assertFalse(saved.isCloudSyncEnabled)
        assertTrue(saved.isMulticastEnabled)
        assertEquals("239.1.2.3", saved.multicastGroupAddress)
        assertEquals(7000, saved.multicastPort)
        assertEquals("en0", saved.multicastInterfaceName)
    }

    @Test
    fun `save after re-entering corrupt scopes clears the corrupt flag`() = runTest {
        // hasCorruptSyncScopes is derived from the stored JSON at decode time; a
        // save writes freshly-built scope JSON, so the flag must not carry forward
        // (a stale true would keep the database unopenable after the user fixed it).
        val existing = DittoDatabase(
            id = 5L,
            name = "Existing",
            databaseId = "ex-id",
            token = "ex-token",
            hasCorruptSyncScopes = true,
        )
        val vm = editItemViewModel(5L, existing)
        testDispatcher.scheduler.advanceUntilIdle()
        vm.discardCorruptSyncScopes.value = true
        testDispatcher.scheduler.advanceUntilIdle()

        val captured = slot<DittoDatabase>()
        coEvery { repository.save(capture(captured)) } returns 5L

        assertTrue(vm.save())
        testDispatcher.scheduler.advanceUntilIdle()

        assertFalse(captured.captured.hasCorruptSyncScopes)
    }

    @Test
    fun `loadForEdit populates all fields correctly`() = runTest {
        val db = DittoDatabase(
            id = 3L,
            name = "Test DB",
            databaseId = "test-id",
            token = "test-token",
            authUrl = "https://auth.example.com",
            httpApiUrl = "https://api.example.com",
            httpApiKey = "api-key",
            mode = AuthMode.SMALL_PEERS_ONLY,
            allowUntrustedCerts = true,
            secretKey = "secret",
            logLevel = "debug",
        )
        val vm = newItemViewModel()
        vm.loadForEdit(db)

        assertEquals("Test DB", vm.name.value)
        assertEquals("test-id", vm.databaseId.value)
        assertEquals("test-token", vm.token.value)
        assertEquals("https://auth.example.com", vm.authUrl.value)
        assertEquals("https://api.example.com", vm.httpApiUrl.value)
        assertEquals("api-key", vm.httpApiKey.value)
        assertEquals(AuthMode.SMALL_PEERS_ONLY, vm.mode.value)
        assertTrue(vm.allowUntrustedCerts.value)
        assertEquals("secret", vm.secretKey.value)
        assertEquals("debug", vm.logLevel.value)
    }

    @Test
    fun `websocketUrl field does not exist on ViewModel`() {
        // Ensures SDK 5.0 adaptation — websocketUrl is intentionally omitted
        // Uses Java reflection to avoid kotlin-reflect dependency
        val vm = newItemViewModel()
        val fieldNames = generateSequence(vm.javaClass as Class<*>?) { it.superclass }
            .flatMap { it.declaredFields.asSequence() }
            .map { it.name }
            .toList()
        assertFalse("websocketUrl should not exist on DatabaseEditorViewModel", fieldNames.contains("websocketUrl"))
    }

    @Test
    fun `mode defaults to AuthMode SERVER`() = runTest {
        val vm = newItemViewModel()
        assertEquals(AuthMode.SERVER, vm.mode.value)
    }

    @Test
    fun `logLevel defaults to info`() = runTest {
        val vm = newItemViewModel()
        assertEquals("info", vm.logLevel.value)
    }

    @Test
    fun `switching mode from SERVER to SMALL_PEERS_ONLY clears authUrl and httpApiUrl`() = runTest {
        val vm = newItemViewModel()
        vm.authUrl.value = "https://auth.example.com"
        vm.httpApiUrl.value = "https://api.example.com"

        vm.switchMode(AuthMode.SMALL_PEERS_ONLY)

        assertEquals("", vm.authUrl.value)
        assertEquals("", vm.httpApiUrl.value)
        assertEquals(AuthMode.SMALL_PEERS_ONLY, vm.mode.value)
    }

    // MARK: Advanced Configuration

    private fun validNewItemViewModel(): DatabaseEditorViewModel {
        val vm = newItemViewModel()
        vm.name.value = "My DB"
        vm.databaseId.value = "db-id"
        vm.token.value = "token"
        return vm
    }

    @Test
    fun `canSave is blocked by an invalid scope row`() = runTest {
        val vm = validNewItemViewModel()
        testDispatcher.scheduler.advanceUntilIdle()
        assertTrue(vm.canSave.value)

        vm.addSyncScope() // blank collection name is invalid
        testDispatcher.scheduler.advanceUntilIdle()

        assertFalse(vm.canSave.value)
        assertTrue(vm.hasAdvancedValidationErrors.value)
    }

    @Test
    fun `canSave is blocked by an unacknowledged sensitive setting`() = runTest {
        val vm = validNewItemViewModel()
        vm.addStartupSetting()
        val row = vm.startupSettings.value.first()
        vm.setParameter(row.id, "some_port")
        vm.setType(row.id, StartupSettingType.Integer)
        vm.setValue(row.id, "9000")
        testDispatcher.scheduler.advanceUntilIdle()

        assertFalse(vm.canSave.value)

        vm.setAcknowledged(row.id, true)
        testDispatcher.scheduler.advanceUntilIdle()

        assertTrue(vm.canSave.value)
    }

    @Test
    fun `renaming a setting revokes its acknowledgement`() = runTest {
        val vm = validNewItemViewModel()
        vm.addStartupSetting()
        val row = vm.startupSettings.value.first()
        vm.setParameter(row.id, "some_port")
        vm.setAcknowledged(row.id, true)
        assertTrue(vm.startupSettings.value.first().isAcknowledged)

        vm.setParameter(row.id, "additional_p2p_trusted_ca_certs")

        assertFalse(vm.startupSettings.value.first().isAcknowledged)
    }

    @Test
    fun `editing the value of a sensitive setting revokes its acknowledgement`() = runTest {
        val vm = validNewItemViewModel()
        vm.addStartupSetting()
        val row = vm.startupSettings.value.first()
        vm.setParameter(row.id, "metrics_exporter_prometheus_http_listener_addr")
        vm.setValue(row.id, "127.0.0.1:9000")
        vm.setAcknowledged(row.id, true)

        vm.setValue(row.id, "0.0.0.0:9000")

        assertFalse(vm.startupSettings.value.first().isAcknowledged)
    }

    @Test
    fun `switching type to Boolean seeds a value and revokes acknowledgement`() = runTest {
        val vm = validNewItemViewModel()
        vm.addStartupSetting()
        val row = vm.startupSettings.value.first()
        vm.setParameter(row.id, "sqlite3_synchronous")
        vm.setValue(row.id, "FULL")
        vm.setAcknowledged(row.id, true)

        vm.setType(row.id, StartupSettingType.Boolean)

        val updated = vm.startupSettings.value.first()
        assertEquals("True", updated.value) // seeded
        assertFalse(updated.isAcknowledged) // seeded value is a real value change
    }

    @Test
    fun `switching type to Boolean over an existing boolean only canonicalises spelling`() = runTest {
        val vm = validNewItemViewModel()
        vm.addStartupSetting()
        val row = vm.startupSettings.value.first()
        vm.setParameter(row.id, "sqlite3_synchronous")
        vm.setValue(row.id, "true") // typed as String first
        vm.setAcknowledged(row.id, true)

        vm.setType(row.id, StartupSettingType.Boolean)

        val updated = vm.startupSettings.value.first()
        assertEquals("True", updated.value) // canonical spelling
        assertTrue(updated.isAcknowledged) // re-spelling is NOT a value change
    }

    @Test
    fun `reset to defaults clears both lists and undo restores them`() = runTest {
        val vm = validNewItemViewModel()
        vm.addSyncScope()
        vm.updateScopeCollection(vm.collectionSyncScopes.value.first().id, "orders")
        vm.addStartupSetting()
        vm.setParameter(vm.startupSettings.value.first().id, "some_setting")

        vm.resetAdvancedToDefaults()

        assertTrue(vm.collectionSyncScopes.value.isEmpty())
        assertTrue(vm.startupSettings.value.isEmpty())
        assertTrue(vm.resetToDefaultsRequested.value)
        assertTrue(vm.canUndoResetToDefaults)

        vm.undoResetToDefaults()

        assertEquals(1, vm.collectionSyncScopes.value.size)
        assertEquals(1, vm.startupSettings.value.size)
        assertFalse(vm.resetToDefaultsRequested.value)
    }

    @Test
    fun `undo reset is not offered once a row is re-entered`() = runTest {
        val vm = validNewItemViewModel()
        vm.addSyncScope()
        vm.resetAdvancedToDefaults()
        vm.addSyncScope() // user starts over

        assertFalse(vm.canUndoResetToDefaults)
    }

    @Test
    fun `corrupt scopes block save until discarded or replaced`() = runTest {
        val existing = DittoDatabase(
            id = 5L,
            name = "Existing",
            databaseId = "ex-id",
            token = "ex-token",
            hasCorruptSyncScopes = true,
        )
        val vm = editItemViewModel(5L, existing)
        testDispatcher.scheduler.advanceUntilIdle()

        assertTrue(vm.hasCorruptSyncScopes.value)
        assertFalse(vm.canSave.value)

        vm.discardCorruptSyncScopes.value = true
        testDispatcher.scheduler.advanceUntilIdle()

        assertTrue(vm.canSave.value)
    }

    @Test
    fun `save persists normalized advanced lists`() = runTest {
        val vm = validNewItemViewModel()
        vm.addSyncScope()
        val scopeRow = vm.collectionSyncScopes.value.first()
        vm.updateScopeCollection(scopeRow.id, "  orders  ")
        vm.updateScope(scopeRow.id, SyncScope.LocalPeerOnly)
        vm.addSyncScope() // blank row — must be dropped, not persisted

        vm.addStartupSetting()
        val settingRow = vm.startupSettings.value.first()
        vm.setParameter(settingRow.id, " some_setting ")
        vm.setValue(settingRow.id, "v")

        val captured = slot<DittoDatabase>()
        coEvery { repository.save(capture(captured)) } returns 1L

        assertTrue(vm.save())
        testDispatcher.scheduler.advanceUntilIdle()

        assertEquals(1, captured.captured.collectionSyncScopes.size)
        assertEquals("orders", captured.captured.collectionSyncScopes[0].collection)
        assertEquals(SyncScope.LocalPeerOnly, captured.captured.collectionSyncScopes[0].scope)
        assertEquals(1, captured.captured.startupSettings.size)
        assertEquals("some_setting", captured.captured.startupSettings[0].parameter)
    }

    @Test
    fun `loadForEdit canonicalises stored boolean spelling`() = runTest {
        val db = DittoDatabase(
            id = 3L,
            name = "DB",
            databaseId = "db-id",
            token = "t",
            startupSettings = listOf(
                StartupSetting(
                    parameter = "some_flag",
                    type = StartupSettingType.Boolean,
                    value = "true",
                    isAcknowledged = false,
                ),
            ),
        )
        val vm = newItemViewModel()
        vm.loadForEdit(db)

        assertEquals("True", vm.startupSettings.value.first().value)
    }

    @Test
    fun `advanced summary counts rows`() = runTest {
        val vm = validNewItemViewModel()
        assertEquals("0 scopes · 0 startup settings", vm.advancedSummary())
        vm.addSyncScope()
        vm.addStartupSetting()
        assertEquals("1 scope · 1 startup setting", vm.advancedSummary())
    }
}
