package com.costoda.dittoedgestudio.viewmodel

import com.costoda.dittoedgestudio.data.repository.DatabaseRepository
import com.costoda.dittoedgestudio.domain.model.AuthMode
import com.costoda.dittoedgestudio.domain.model.DittoDatabase
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
}
