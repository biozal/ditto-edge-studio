package com.costoda.dittoedgestudio.data.ditto

import com.costoda.dittoedgestudio.domain.model.AdvancedSettingsDql
import com.costoda.dittoedgestudio.domain.model.AuthMode
import com.costoda.dittoedgestudio.domain.model.CollectionSyncScope
import com.costoda.dittoedgestudio.domain.model.DittoDatabase
import com.costoda.dittoedgestudio.domain.model.StartupSetting
import com.costoda.dittoedgestudio.domain.model.StartupSettingType
import com.costoda.dittoedgestudio.domain.model.SyncScope
import com.ditto.kotlin.Ditto
import com.ditto.kotlin.DittoAuthenticator
import com.ditto.kotlin.DittoConfig
import com.ditto.kotlin.DittoFactory
import com.ditto.kotlin.DittoQueryResult
import com.ditto.kotlin.DittoStore
import com.ditto.kotlin.DittoSync
import io.mockk.coEvery
import io.mockk.every
import io.mockk.mockk
import io.mockk.mockkObject
import io.mockk.slot
import io.mockk.verify
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class DittoManagerTest {

    private lateinit var manager: DittoManager
    private lateinit var mockDitto: Ditto
    private lateinit var mockAuth: DittoAuthenticator
    private lateinit var mockStore: DittoStore
    private lateinit var mockSync: DittoSync
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Unconfined)

    /** Records the order of DQL statements and sync starts across the open sequence. */
    private lateinit var events: MutableList<String>

    private val serverDatabase = DittoDatabase(
        id = 1L,
        name = "Test DB",
        databaseId = "test-db-id",
        token = "test-token",
        authUrl = "https://test.ditto.live",
        websocketUrl = "wss://test.ditto.live",
        mode = AuthMode.SERVER,
        isBluetoothLeEnabled = false,
        isLanEnabled = false,
        isAwdlEnabled = false,
        isCloudSyncEnabled = false,
    )

    private val smallPeersDatabase = DittoDatabase(
        id = 2L,
        name = "Offline DB",
        databaseId = "offline-db-id",
        token = "offline-license-token",
        mode = AuthMode.SMALL_PEERS_ONLY,
        isBluetoothLeEnabled = false,
        isLanEnabled = false,
        isAwdlEnabled = false,
        isCloudSyncEnabled = false,
    )

    @Before
    fun setUp() {
        events = mutableListOf()
        mockAuth = mockk(relaxed = true)
        mockStore = mockk(relaxed = true)
        mockSync = mockk(relaxed = true)
        mockDitto = mockk(relaxed = true) {
            every { auth } returns mockAuth
            every { store } returns mockStore
            every { sync } returns mockSync
        }
        // The open sequence issues ALTER SYSTEM statements through store.execute with a
        // result handler; invoke the handler with an empty result so the applier runs.
        coEvery {
            mockStore.execute(any<String>(), any<Map<String, Any?>>(), any<(DittoQueryResult) -> Any?>())
        } answers {
            events.add("dql:${firstArg<String>()}")
            val handler = thirdArg<(DittoQueryResult) -> Any?>()
            val emptyResult = mockk<DittoQueryResult>(relaxed = true) {
                every { items } returns emptyList()
            }
            handler.invoke(emptyResult)
        }
        coEvery { mockSync.start() } answers { events.add("sync.start") }
        mockkObject(DittoFactory)
        coEvery { DittoFactory.create(any<DittoConfig>(), any()) } returns mockDitto

        manager = DittoManager(scope)
    }

    // --- Auth handler registration (SERVER mode) ---

    @Test
    fun `hydrate sets expirationHandler for SERVER mode`() = runTest {
        manager.hydrate(serverDatabase)

        val handlerSlot = slot<suspend (Ditto, Double) -> Unit>()
        verify { mockAuth.expirationHandler = capture(handlerSlot) }
        assertNotNull(handlerSlot.captured)
    }

    @Test
    fun `hydrate does not set expirationHandler for SMALL_PEERS_ONLY mode`() = runTest {
        manager.hydrate(smallPeersDatabase)

        verify(exactly = 0) { mockAuth.expirationHandler = any() }
    }

    // --- Offline license token (SMALL_PEERS_ONLY mode) ---

    @Test
    fun `hydrate sets offline license token for SMALL_PEERS_ONLY with token`() = runTest {
        manager.hydrate(smallPeersDatabase)

        verify { mockDitto.setOfflineOnlyLicenseToken("offline-license-token") }
    }

    @Test
    fun `hydrate does not set offline license token when token is blank`() = runTest {
        val noTokenDb = smallPeersDatabase.copy(token = "")
        manager.hydrate(noTokenDb)

        verify(exactly = 0) { mockDitto.setOfflineOnlyLicenseToken(any()) }
    }

    @Test
    fun `hydrate does not set offline license token for SERVER mode`() = runTest {
        manager.hydrate(serverDatabase)

        verify(exactly = 0) { mockDitto.setOfflineOnlyLicenseToken(any()) }
    }

    // --- Input validation ---

    @Test(expected = IllegalArgumentException::class)
    fun `hydrate throws when databaseId is blank`() = runTest {
        manager.hydrate(serverDatabase.copy(databaseId = ""))
    }

    @Test(expected = IllegalArgumentException::class)
    fun `hydrate throws when token is blank for SERVER mode`() = runTest {
        manager.hydrate(serverDatabase.copy(token = ""))
    }

    @Test(expected = IllegalArgumentException::class)
    fun `hydrate throws when authUrl is blank for SERVER mode`() = runTest {
        manager.hydrate(serverDatabase.copy(authUrl = ""))
    }

    @Test
    fun `hydrate does not throw when token is blank for SMALL_PEERS_ONLY mode`() = runTest {
        // SMALL_PEERS_ONLY with no token is valid — offline license is optional
        manager.hydrate(smallPeersDatabase.copy(token = ""))
        assertNotNull(manager.currentInstance())
    }

    // --- Lifecycle ---

    @Test
    fun `hydrate closes previous instance before creating new one`() = runTest {
        manager.hydrate(serverDatabase)
        manager.hydrate(serverDatabase)

        // close() called once when closing the first instance before creating a new one
        verify(atLeast = 1) { mockDitto.close() }
    }

    @Test
    fun `close clears the current instance`() = runTest {
        manager.hydrate(serverDatabase)
        manager.close()

        assertNull(manager.currentInstance())
    }

    // --- buildConfig ---

    @Test
    fun `hydrate creates Server config for SERVER mode`() = runTest {
        val configSlot = slot<DittoConfig>()
        coEvery { DittoFactory.create(capture(configSlot), any()) } returns mockDitto

        manager.hydrate(serverDatabase)

        assertNotNull(configSlot.captured.connect as? DittoConfig.Connect.Server)
    }

    @Test
    fun `hydrate creates SmallPeersOnly config for SMALL_PEERS_ONLY mode`() = runTest {
        val configSlot = slot<DittoConfig>()
        coEvery { DittoFactory.create(capture(configSlot), any()) } returns mockDitto

        manager.hydrate(smallPeersDatabase)

        assertNotNull(configSlot.captured.connect as? DittoConfig.Connect.SmallPeersOnly)
    }

    // --- Advanced configuration (open sequence) ---

    @Test
    fun `hydrate applies strict mode and sync scopes before starting sync`() = runTest {
        val db = serverDatabase.copy(
            isStrictModeEnabled = true,
            startupSettings = listOf(
                StartupSetting(parameter = "some_setting", type = StartupSettingType.String, value = "v"),
            ),
            collectionSyncScopes = listOf(
                CollectionSyncScope(collection = "orders", scope = SyncScope.LocalPeerOnly),
            ),
        )

        manager.hydrate(db)

        val dql = events.filter { it.startsWith("dql:") }.map { it.removePrefix("dql:") }
        assertEquals("ALTER SYSTEM SET some_setting = :value", dql[0])
        assertEquals("ALTER SYSTEM SET DQL_STRICT_MODE = true", dql[1])
        assertEquals(AdvancedSettingsDql.SET_SYNC_SCOPES_QUERY, dql[2])
        assertEquals(AdvancedSettingsDql.SHOW_SYNC_SCOPES_QUERY, dql[3])
        assertEquals("sync.start", events.last())
        // The SHOW returned no rows (empty result), so the write is unverified.
        assertEquals(true, manager.lastAdvancedApplyResult?.scopesUnverified)
        assertEquals(1, manager.lastAdvancedApplyResult?.appliedScopeCount)
    }

    @Test
    fun `hydrate throws when stored sync scopes are corrupt`() = runTest {
        val corrupt = serverDatabase.copy(hasCorruptSyncScopes = true)

        try {
            manager.hydrate(corrupt)
            org.junit.Assert.fail("expected IllegalArgumentException")
        } catch (e: IllegalArgumentException) {
            assertTrue(e.message!!.contains("sync scopes", ignoreCase = true))
        }
        // Fail-closed: the instance must not have been opened.
        assertNull(manager.currentInstance())
    }

    @Test
    fun `hydrate does not start sync when the scope statement fails`() = runTest {
        coEvery {
            mockStore.execute(
                AdvancedSettingsDql.SET_SYNC_SCOPES_QUERY,
                any<Map<String, Any?>>(),
                any<(DittoQueryResult) -> Any?>(),
            )
        } throws RuntimeException("ALTER SYSTEM rejected")

        val db = serverDatabase.copy(
            collectionSyncScopes = listOf(
                CollectionSyncScope(collection = "orders", scope = SyncScope.LocalPeerOnly),
            ),
        )

        try {
            manager.hydrate(db)
            org.junit.Assert.fail("expected ApplyError")
        } catch (e: AdvancedSettingsApplier.ApplyError.ScopeStatementFailed) {
            // expected
        }
        assertTrue("sync.start must not run when scopes fail", events.none { it == "sync.start" })
        assertNull(manager.currentInstance())
    }

    @Test
    fun `startSync re-applies the open sequence on the live instance`() = runTest {
        manager.hydrate(serverDatabase)
        events.clear()

        manager.startSync()

        assertTrue(events.any { it == "dql:${AdvancedSettingsDql.SET_SYNC_SCOPES_QUERY}" })
        assertEquals("sync.start", events.last())
    }

    @Test
    fun `refreshActiveConfigIfMatching swaps the config a sync restart re-applies`() = runTest {
        manager.hydrate(serverDatabase)
        val edited = serverDatabase.copy(
            startupSettings = listOf(
                StartupSetting(parameter = "new_setting", type = StartupSettingType.String, value = "v"),
            ),
        )
        manager.refreshActiveConfigIfMatching(edited)
        events.clear()

        manager.startSync()

        assertTrue(events.any { it == "dql:ALTER SYSTEM SET new_setting = :value" })
    }
}
