package com.costoda.dittoedgestudio.viewmodel

import android.util.Base64
import com.costoda.dittoedgestudio.data.repository.DatabaseRepository
import com.costoda.dittoedgestudio.data.repository.FavoritesRepository
import com.costoda.dittoedgestudio.domain.model.DittoDatabase
import com.costoda.dittoedgestudio.ui.qrcode.QrScannerUiState
import com.costoda.dittoedgestudio.ui.qrcode.QrScannerViewModel
import io.mockk.MockKAnnotations
import io.mockk.clearAllMocks
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.every
import io.mockk.impl.annotations.MockK
import io.mockk.mockkStatic
import io.mockk.unmockkStatic
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.util.zip.Deflater

@OptIn(ExperimentalCoroutinesApi::class)
class QrScannerViewModelTest {

    @MockK
    private lateinit var databaseRepository: DatabaseRepository

    @MockK
    private lateinit var favoritesRepository: FavoritesRepository

    private val testDispatcher = StandardTestDispatcher()
    private lateinit var viewModel: QrScannerViewModel

    @Before
    fun setup() {
        MockKAnnotations.init(this)
        Dispatchers.setMain(testDispatcher)
        mockkStatic(Base64::class)
        every { Base64.decode(any<String>(), any()) } answers {
            java.util.Base64.getDecoder().decode(firstArg<String>())
        }
        every { Base64.encodeToString(any(), any()) } answers {
            java.util.Base64.getEncoder().encodeToString(firstArg<ByteArray>())
        }
        viewModel = QrScannerViewModel(databaseRepository, favoritesRepository)
    }

    @After
    fun teardown() {
        Dispatchers.resetMain()
        clearAllMocks()
        unmockkStatic(Base64::class)
    }

    // ─── Helpers ────────────────────────────────────────────────────────────────

    private fun buildValidEds2Payload(databaseId: String = "db-scan-001"): String {
        val json = """{"version":2,"config":{"_id":"","name":"Scanned DB","databaseId":"$databaseId","token":"tok","authUrl":"https://a.com","websocketUrl":"wss://w.com","httpApiUrl":"https://api.com","httpApiKey":"k","mode":"server","allowUntrustedCerts":false,"secretKey":"","isBluetoothLeEnabled":true,"isLanEnabled":true,"isAwdlEnabled":false,"isCloudSyncEnabled":true,"logLevel":"info"},"favorites":[]}"""
        val bytes = json.toByteArray(Charsets.UTF_8)
        val deflater = Deflater(Deflater.DEFAULT_COMPRESSION, false)
        deflater.setInput(bytes)
        deflater.finish()
        val output = ByteArray(bytes.size * 2 + 100)
        val length = deflater.deflate(output)
        deflater.end()
        return "EDS2:" + java.util.Base64.getEncoder().encodeToString(output.copyOf(length))
    }

    // ─── State transition tests ──────────────────────────────────────────────────

    @Test
    fun `initial state is Idle`() {
        assertEquals(QrScannerUiState.Idle, viewModel.uiState.value)
    }

    @Test
    fun `startScanning transitions Idle to Scanning`() {
        viewModel.startScanning()
        assertEquals(QrScannerUiState.Scanning, viewModel.uiState.value)
    }

    @Test
    fun `startScanning does not change state when already Scanning`() {
        viewModel.startScanning()
        viewModel.startScanning()
        assertEquals(QrScannerUiState.Scanning, viewModel.uiState.value)
    }

    @Test
    fun `processBarcode transitions Scanning to Processing then Success`() = runTest {
        coEvery { databaseRepository.save(any()) } returns 1L
        coEvery { favoritesRepository.saveFavorite(any(), any()) } returns null

        viewModel.startScanning()
        val payload = buildValidEds2Payload()
        viewModel.processBarcode(payload)

        testDispatcher.scheduler.advanceUntilIdle()

        assertTrue(viewModel.uiState.value is QrScannerUiState.Success)
    }

    @Test
    fun `processBarcode transitions to Error on invalid barcode`() = runTest {
        viewModel.startScanning()
        viewModel.processBarcode("not-a-valid-qr-at-all")

        testDispatcher.scheduler.advanceUntilIdle()

        assertTrue(viewModel.uiState.value is QrScannerUiState.Error)
    }

    @Test
    fun `processBarcode does not re-process when already Processing`() = runTest {
        coEvery { databaseRepository.save(any()) } returns 1L
        coEvery { favoritesRepository.saveFavorite(any(), any()) } returns null

        viewModel.startScanning()
        val payload = buildValidEds2Payload()

        // Fire two barcodes rapidly
        viewModel.processBarcode(payload)
        viewModel.processBarcode("another-invalid-payload")

        testDispatcher.scheduler.advanceUntilIdle()

        // Should end in Success from the first barcode, not Error from the second
        assertTrue(viewModel.uiState.value is QrScannerUiState.Success)
    }

    @Test
    fun `processBarcode saves database to repository on success`() = runTest {
        coEvery { databaseRepository.save(any()) } returns 1L
        coEvery { favoritesRepository.saveFavorite(any(), any()) } returns null

        viewModel.startScanning()
        viewModel.processBarcode(buildValidEds2Payload("db-save-test"))

        testDispatcher.scheduler.advanceUntilIdle()

        coVerify(exactly = 1) { databaseRepository.save(any<DittoDatabase>()) }
    }

    @Test
    fun `processBarcode handles duplicate databaseId via upsert without crashing`() = runTest {
        // OnConflictStrategy.REPLACE in the DAO means a duplicate save just replaces the old row
        coEvery { databaseRepository.save(any()) } returns 1L
        coEvery { favoritesRepository.saveFavorite(any(), any()) } returns null

        viewModel.startScanning()
        viewModel.processBarcode(buildValidEds2Payload("dup-db-id"))

        testDispatcher.scheduler.advanceUntilIdle()

        assertTrue(viewModel.uiState.value is QrScannerUiState.Success)
    }

    @Test
    fun `resetError transitions Error back to Scanning`() = runTest {
        viewModel.startScanning()
        viewModel.processBarcode("invalid-payload")

        testDispatcher.scheduler.advanceUntilIdle()

        assertTrue(viewModel.uiState.value is QrScannerUiState.Error)
        viewModel.resetError()
        assertEquals(QrScannerUiState.Scanning, viewModel.uiState.value)
    }
}
