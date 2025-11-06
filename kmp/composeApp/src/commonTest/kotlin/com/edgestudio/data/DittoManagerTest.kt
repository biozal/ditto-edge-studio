package com.edgestudio.data

import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

/**
 * Unit tests for DittoManager
 *
 * Note: These tests verify the state management and lifecycle behavior of DittoManager.
 * Full integration tests with actual Ditto SDK would require platform-specific test setup.
 */
class DittoManagerTest {

    @Test
    fun `initial state has no database initialized`() = runTest {
        val testDispatcher = UnconfinedTestDispatcher(testScheduler)
        val scopeProvider = TestCoroutineScopeProvider(backgroundScope, testDispatcher)
        val dittoManager = DittoManager(scopeProvider)

        assertFalse(
            dittoManager.isDittoLocalDatabaseInitialized(),
            "Local database should not be initialized initially"
        )
        assertFalse(
            dittoManager.isDittoSelectedDatabaseInitialized(),
            "Selected database should not be initialized initially"
        )
    }

    @Test
    fun `dittoManager instance is created successfully`() {
        val dittoManager = DittoManager()

        assertNotNull(dittoManager, "DittoManager instance should not be null")
    }

    @Test
    fun `closeLocalDatabase clears local database reference`() = runTest {
        val testDispatcher = UnconfinedTestDispatcher(testScheduler)
        val scopeProvider = TestCoroutineScopeProvider(backgroundScope, testDispatcher)
        val dittoManager = DittoManager(scopeProvider)

        // Close the database (even if not initialized)
        dittoManager.closeLocalDatabase()

        assertFalse(
            dittoManager.isDittoLocalDatabaseInitialized(),
            "Local database should not be initialized after closing"
        )
    }

    @Test
    fun `closeSelectedDatabase clears selected database reference`() = runTest {
        val testDispatcher = UnconfinedTestDispatcher(testScheduler)
        val scopeProvider = TestCoroutineScopeProvider(backgroundScope, testDispatcher)
        val dittoManager = DittoManager(scopeProvider)

        // Close the database (even if not initialized)
        dittoManager.closeSelectedDatabase()

        assertFalse(
            dittoManager.isDittoSelectedDatabaseInitialized(),
            "Selected database should not be initialized after closing"
        )
    }

    @Test
    fun `isDittoSelectedDatabaseSyncing returns false when not initialized`() = runTest {
        val testDispatcher = UnconfinedTestDispatcher(testScheduler)
        val scopeProvider = TestCoroutineScopeProvider(backgroundScope, testDispatcher)
        val dittoManager = DittoManager(scopeProvider)

        val isSyncing = dittoManager.isDittoSelectedDatabaseSyncing()

        assertFalse(isSyncing, "Syncing should be false when database is not initialized")
    }

    @Test
    fun `closeLocalObservers completes without error when no database`() = runTest {
        val testDispatcher = UnconfinedTestDispatcher(testScheduler)
        val scopeProvider = TestCoroutineScopeProvider(backgroundScope, testDispatcher)
        val dittoManager = DittoManager(scopeProvider)

        // Should not throw exception even when database is not initialized
        dittoManager.closeLocalObservers()

        assertTrue(true, "closeLocalObservers should complete without error")
    }

    @Test
    fun `selectedDatabaseConfig is null initially`() {
        val dittoManager = DittoManager()

        assertEquals(dittoManager.selectedDatabaseConfig, null, "Selected database config should be null initially")
    }

    // Note: Tests for initializeDittoStore() require platform-specific Ditto SDK setup
    // and would be better suited for integration tests rather than unit tests.
    // These would need to be implemented in platform-specific test source sets.
}
