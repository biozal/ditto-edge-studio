package com.costoda.dittoedgestudio.ui.qrcode

import android.util.Log
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.costoda.dittoedgestudio.data.repository.DatabaseRepository
import com.costoda.dittoedgestudio.data.repository.FavoritesRepository
import com.costoda.dittoedgestudio.util.QrCodeDecoder
import com.costoda.dittoedgestudio.util.QrImportResult
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

private const val TAG = "QrScannerViewModel"

sealed interface QrScannerUiState {
    data object Idle : QrScannerUiState
    data object Scanning : QrScannerUiState
    data object Processing : QrScannerUiState
    data class Success(val result: QrImportResult) : QrScannerUiState
    data class Error(val message: String) : QrScannerUiState
}

class QrScannerViewModel(
    private val databaseRepository: DatabaseRepository,
    private val favoritesRepository: FavoritesRepository,
) : ViewModel() {

    private val _uiState = MutableStateFlow<QrScannerUiState>(QrScannerUiState.Idle)
    val uiState: StateFlow<QrScannerUiState> = _uiState.asStateFlow()

    fun startScanning() {
        if (_uiState.value is QrScannerUiState.Idle) {
            _uiState.value = QrScannerUiState.Scanning
        }
    }

    fun processBarcode(rawValue: String) {
        if (_uiState.value is QrScannerUiState.Processing) return
        _uiState.value = QrScannerUiState.Processing
        Log.d(TAG, "processBarcode: length=${rawValue.length} prefix=${rawValue.take(10)}")

        viewModelScope.launch {
            val result = QrCodeDecoder.decode(rawValue)
            if (result == null) {
                _uiState.value = QrScannerUiState.Error("Invalid QR code — not a valid database config")
                return@launch
            }
            try {
                databaseRepository.save(result.database)
                result.favorites.forEach { query ->
                    favoritesRepository.saveFavorite(result.database.databaseId, query)
                }
                _uiState.value = QrScannerUiState.Success(result)
            } catch (e: Exception) {
                _uiState.value = QrScannerUiState.Error(e.message ?: "Failed to save database config")
            }
        }
    }

    fun resetError() {
        _uiState.value = QrScannerUiState.Scanning
    }
}
