package com.costoda.dittoedgestudio.data.ditto

import com.costoda.dittoedgestudio.domain.model.AuthMode
import com.costoda.dittoedgestudio.domain.model.DittoDatabase
import com.ditto.kotlin.Ditto
import com.ditto.kotlin.DittoAuthenticator
import com.ditto.kotlin.DittoConfig
import com.ditto.kotlin.DittoFactory
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
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Test

class DittoManagerTest {

    private lateinit var manager: DittoManager
    private lateinit var mockDitto: Ditto
    private lateinit var mockAuth: DittoAuthenticator
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Unconfined)

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
        mockAuth = mockk(relaxed = true)
        mockDitto = mockk(relaxed = true) {
            every { auth } returns mockAuth
        }
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
}
