package com.costoda.dittoedgestudio.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.costoda.dittoedgestudio.data.repository.DatabaseRepository
import com.costoda.dittoedgestudio.domain.model.DittoDatabase
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

sealed class DatabaseListUiState {
    object Loading : DatabaseListUiState()
    object Empty : DatabaseListUiState()
    data class Databases(val items: List<DittoDatabase>) : DatabaseListUiState()
}

class DatabaseListViewModel(private val repository: DatabaseRepository) : ViewModel() {

    val uiState: StateFlow<DatabaseListUiState> = repository.observeAll()
        .map { databases ->
            if (databases.isEmpty()) DatabaseListUiState.Empty
            else DatabaseListUiState.Databases(databases)
        }
        .stateIn(
            scope = viewModelScope,
            started = SharingStarted.WhileSubscribed(5_000),
            initialValue = DatabaseListUiState.Loading,
        )

    fun deleteDatabase(id: Long) {
        viewModelScope.launch {
            repository.delete(id)
        }
    }
}
