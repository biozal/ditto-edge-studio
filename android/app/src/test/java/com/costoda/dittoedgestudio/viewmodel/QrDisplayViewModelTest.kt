package com.costoda.dittoedgestudio.viewmodel

import android.graphics.Bitmap
import android.util.Base64
import com.costoda.dittoedgestudio.data.repository.FavoritesRepository
import com.costoda.dittoedgestudio.domain.model.DittoDatabase
import com.costoda.dittoedgestudio.domain.model.DittoQueryHistory
import com.costoda.dittoedgestudio.ui.qrcode.QrDisplayViewModel
import io.mockk.MockKAnnotations
import io.mockk.clearAllMocks
import io.mockk.coEvery
import io.mockk.every
import io.mockk.impl.annotations.MockK
import io.mockk.mockkObject
import io.mockk.mockkStatic
import io.mockk.unmockkStatic
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class QrDisplayViewModelTest {

    @MockK
    private lateinit var favoritesRepository: FavoritesRepository

    private val testDispatcher = StandardTestDispatcher()

    private val testDatabase = DittoDatabase(
        id = 1L,
        name = "Display Test DB",
        databaseId = "display-db-001",
        token = "tok_display",
        authUrl = "https://auth.example.com",
        websocketUrl = "wss://ws.example.com",
        httpApiUrl = "https://api.example.com",
        httpApiKey = "key_display",
    )

    @Before
    fun setup() {
        MockKAnnotations.init(this)
        Dispatchers.setMain(testDispatcher)
        mockkStatic(Base64::class)
        every { Base64.encodeToString(any(), any()) } answers {
            java.util.Base64.getEncoder().encodeToString(firstArg<ByteArray>())
        }
        every { Base64.decode(any<String>(), any()) } answers {
            java.util.Base64.getDecoder().decode(firstArg<String>())
        }
        mockkStatic(Bitmap::class)
    }

    @After
    fun teardown() {
        Dispatchers.resetMain()
        clearAllMocks()
        unmockkStatic(Base64::class)
        unmockkStatic(Bitmap::class)
    }

    @Test
    fun `bitmap is null initially before load completes`() {
        coEvery { favoritesRepository.loadFavorites(any()) } returns emptyList()
        every { Bitmap.createBitmap(any<IntArray>(), any(), any(), any()) } returns
            io.mockk.mockk<Bitmap>(relaxed = true)

        val viewModel = QrDisplayViewModel(testDatabase, favoritesRepository)

        // Before advancing, bitmap should still be null
        assertNull(viewModel.bitmap.value)
    }

    @Test
    fun `bitmap is non-null after load completes`() = runTest {
        coEvery { favoritesRepository.loadFavorites(any()) } returns emptyList()
        every { Bitmap.createBitmap(any<IntArray>(), any(), any(), any()) } returns
            io.mockk.mockk<Bitmap>(relaxed = true)

        val viewModel = QrDisplayViewModel(testDatabase, favoritesRepository)

        testDispatcher.scheduler.advanceUntilIdle()

        assertNotNull(viewModel.bitmap.value)
        assertFalse(viewModel.isError.value)
    }

    @Test
    fun `isError is true when encoding fails`() = runTest {
        coEvery { favoritesRepository.loadFavorites(any()) } returns emptyList()
        // Simulate encoding failure by making Bitmap.createBitmap throw
        every { Bitmap.createBitmap(any<IntArray>(), any(), any(), any()) } throws RuntimeException("render failed")

        val viewModel = QrDisplayViewModel(testDatabase, favoritesRepository)

        testDispatcher.scheduler.advanceUntilIdle()

        assertTrue(viewModel.isError.value)
        assertNull(viewModel.bitmap.value)
    }

    @Test
    fun `fetches favorites for the given databaseId`() = runTest {
        val favorites = listOf(
            DittoQueryHistory(id = 1L, databaseId = "display-db-001", query = "SELECT * FROM docs"),
        )
        coEvery { favoritesRepository.loadFavorites("display-db-001") } returns favorites
        every { Bitmap.createBitmap(any<IntArray>(), any(), any(), any()) } returns
            io.mockk.mockk<Bitmap>(relaxed = true)

        val viewModel = QrDisplayViewModel(testDatabase, favoritesRepository)

        testDispatcher.scheduler.advanceUntilIdle()

        // Verify the repository was called with the correct databaseId
        io.mockk.coVerify(exactly = 1) { favoritesRepository.loadFavorites("display-db-001") }
    }
}
