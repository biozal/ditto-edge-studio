package com.edgestudio.data.repositories

import com.ditto.kotlin.Ditto
import com.ditto.kotlin.DittoQueryResult
import com.ditto.kotlin.serialization.DittoCborSerializable
import com.edgestudio.data.IDittoManager
import com.edgestudio.models.ESDatabaseConfig
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertNotNull

/**
 * Unit tests for DatabaseRepository
 *
 * Note: These tests use a mock implementation of IDittoManager to test repository behavior
 * without requiring actual Ditto SDK initialization.
 */
class DatabaseRepositoryTest {

    /**
     * Mock implementation of IDittoManager for testing
     */
    private class MockDittoManager : IDittoManager {
        override var dittoLocalDatabase: Ditto? = null
        override var dittoSelectedDatabase: Ditto? = null
        override var selectedDatabaseConfig: ESDatabaseConfig? = null

        private val executedQueries = mutableListOf<String>()

        override fun closeSelectedDatabase() {}
        override fun closeLocalDatabase() {}
        override suspend fun closeLocalObservers() {}

        override suspend fun initializeDittoStore() {}

        override suspend fun initializeDittoSelectedDatabase(databaseConfig: ESDatabaseConfig) {
            selectedDatabaseConfig = databaseConfig
        }

        override suspend fun isDittoLocalDatabaseInitialized(): Boolean = dittoLocalDatabase != null

        override suspend fun isDittoSelectedDatabaseInitialized(): Boolean = dittoSelectedDatabase != null

        override suspend fun isDittoSelectedDatabaseSyncing(): Boolean = false

        override suspend fun localDatabaseExecuteDql(
            query: String,
            parameters: DittoCborSerializable.Dictionary?
        ): DittoQueryResult? {
            executedQueries.add(query)
            // Return null for now - in a real mock we'd return mock results
            return null
        }

        override suspend fun registerObserverLocalDatabase(
            query: String,
            arguments: DittoCborSerializable.Dictionary?
        ): Flow<DittoQueryResult> {
            executedQueries.add(query)
            // Return empty flow for testing
            // In a real test, we'd return a flow that emits mock DittoQueryResult
            return flowOf()
        }

        override suspend fun selectedDatabaseExecuteDql(
            query: String,
            parameters: DittoCborSerializable.Dictionary?
        ): DittoQueryResult? {
            executedQueries.add(query)
            return null
        }

        override suspend fun selectedDatabaseStartSync() {}
        override suspend fun selectedDatabaseStopSync() {}

        fun getExecutedQueries(): List<String> = executedQueries
    }

    @Test
    fun `repository instance is created successfully`() {
        val mockDittoManager = MockDittoManager()
        val repository = DatabaseRepository(mockDittoManager)

        assertNotNull(repository, "DatabaseRepository instance should not be null")
    }

    @Test
    fun `addDatabaseConfig executes INSERT query`() = runTest {
        val mockDittoManager = MockDittoManager()
        val repository = DatabaseRepository(mockDittoManager)

        val testConfig = ESDatabaseConfig(
            id = "test-id",
            name = "Test Database",
            databaseId = "test-db-id",
            authToken = "test-token",
            authUrl = "https://test.ditto.live",
            httpApiUrl = "https://api.test.ditto.live",
            httpApiKey = "test-api-key",
            mode = "cloud",
            allowUntrustedCerts = false
        )

        repository.addDatabaseConfig(testConfig)

        val queries = mockDittoManager.getExecutedQueries()
        assert(queries.any { it.contains("INSERT INTO dittoDatabaseConfig") }) {
            "Should execute INSERT query for adding database config"
        }
    }

    @Test
    fun `deleteDatabaseConfig executes DELETE query`() = runTest {
        val mockDittoManager = MockDittoManager()
        val repository = DatabaseRepository(mockDittoManager)

        val testConfig = ESDatabaseConfig(
            id = "test-id",
            name = "Test Database",
            databaseId = "test-db-id",
            authToken = "test-token",
            authUrl = "https://test.ditto.live",
            httpApiUrl = "https://api.test.ditto.live",
            httpApiKey = "test-api-key",
            mode = "cloud",
            allowUntrustedCerts = false
        )

        repository.deleteDatabaseConfig(testConfig)

        val queries = mockDittoManager.getExecutedQueries()
        assert(queries.any { it.contains("DELETE FROM dittoDatabaseConfig") }) {
            "Should execute DELETE query for deleting database config"
        }
    }

    @Test
    fun `updateDatabaseConfig executes UPDATE query`() = runTest {
        val mockDittoManager = MockDittoManager()
        val repository = DatabaseRepository(mockDittoManager)

        val testConfig = ESDatabaseConfig(
            id = "test-id",
            name = "Updated Database",
            databaseId = "test-db-id",
            authToken = "test-token",
            authUrl = "https://test.ditto.live",
            httpApiUrl = "https://api.test.ditto.live",
            httpApiKey = "test-api-key",
            mode = "cloud",
            allowUntrustedCerts = false
        )

        repository.updateDatabaseConfig(testConfig)

        val queries = mockDittoManager.getExecutedQueries()
        assert(queries.any { it.contains("UPDATE dittoDatabaseConfig") }) {
            "Should execute UPDATE query for updating database config"
        }
    }

    @Test
    fun `getDatabaseConfig executes SELECT query with ID parameter`() = runTest {
        val mockDittoManager = MockDittoManager()
        val repository = DatabaseRepository(mockDittoManager)

        repository.getDatabaseConfig("test-id")

        val queries = mockDittoManager.getExecutedQueries()
        assert(queries.any { it.contains("SELECT * FROM dittoDatabaseConfig WHERE _id = :id") }) {
            "Should execute SELECT query with ID parameter for getting database config"
        }
    }

    @Test
    fun `tasksStateFlow is available`() {
        val mockDittoManager = MockDittoManager()
        val repository = DatabaseRepository(mockDittoManager)

        assertNotNull(repository.tasksStateFlow, "TasksStateFlow should be available")
    }

    @Test
    fun `closeObserver delegates to dittoManager`() = runTest {
        val mockDittoManager = MockDittoManager()
        val repository = DatabaseRepository(mockDittoManager)

        // Should not throw exception
        repository.closeObserver()
    }

    // Note: Testing Flow emissions and observer behavior would require more complex
    // mocking of DittoQueryResult and its items. This could be added in future
    // integration tests with proper Ditto SDK test fixtures.
}
