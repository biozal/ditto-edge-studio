package com.costoda.dittoedgestudio.ui.qrcode

import android.graphics.Bitmap
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.costoda.dittoedgestudio.data.repository.FavoritesRepository
import com.costoda.dittoedgestudio.domain.model.DittoDatabase
import com.costoda.dittoedgestudio.util.QrCodeEncoder
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

class QrDisplayViewModel(
    private val database: DittoDatabase,
    private val favoritesRepository: FavoritesRepository,
) : ViewModel() {

    private val _bitmap = MutableStateFlow<Bitmap?>(null)
    val bitmap: StateFlow<Bitmap?> = _bitmap.asStateFlow()

    private val _isError = MutableStateFlow(false)
    val isError: StateFlow<Boolean> = _isError.asStateFlow()

    init {
        viewModelScope.launch {
            val favorites = favoritesRepository.loadFavorites(database.databaseId).map { it.query }
            val bmp = QrCodeEncoder.encode(database, favorites)
            if (bmp != null) {
                _bitmap.value = bmp
            } else {
                _isError.value = true
            }
        }
    }
}
