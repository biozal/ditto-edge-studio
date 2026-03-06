package com.costoda.dittoedgestudio.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.costoda.dittoedgestudio.data.repository.DatabaseRepository
import com.costoda.dittoedgestudio.domain.model.AuthMode
import com.costoda.dittoedgestudio.domain.model.DittoDatabase
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

class DatabaseEditorViewModel(
    private val editId: Long,
    private val repository: DatabaseRepository,
) : ViewModel() {

    val isNewItem: Boolean get() = editId <= 0L

    val name = MutableStateFlow("")
    val databaseId = MutableStateFlow("")
    val token = MutableStateFlow("")
    val authUrl = MutableStateFlow("")
    val httpApiUrl = MutableStateFlow("")
    val httpApiKey = MutableStateFlow("")
    val mode = MutableStateFlow(AuthMode.SERVER)
    val allowUntrustedCerts = MutableStateFlow(false)
    val secretKey = MutableStateFlow("")
    val logLevel = MutableStateFlow("info")
    val isStrictModeEnabled = MutableStateFlow(false)

    val canSave: StateFlow<Boolean> = combine(name, databaseId, token) { n, d, t ->
        n.isNotBlank() && d.isNotBlank() && t.isNotBlank()
    }.stateIn(viewModelScope, SharingStarted.Eagerly, false)

    init {
        if (!isNewItem) {
            viewModelScope.launch {
                val found = repository.getAll().firstOrNull { it.id == editId }
                found?.let { loadForEdit(it) }
            }
        }
    }

    fun loadForEdit(database: DittoDatabase) {
        name.value = database.name
        databaseId.value = database.databaseId
        token.value = database.token
        authUrl.value = database.authUrl
        httpApiUrl.value = database.httpApiUrl
        httpApiKey.value = database.httpApiKey
        mode.value = database.mode
        allowUntrustedCerts.value = database.allowUntrustedCerts
        secretKey.value = database.secretKey
        logLevel.value = database.logLevel
        isStrictModeEnabled.value = database.isStrictModeEnabled
    }

    fun switchMode(newMode: AuthMode) {
        mode.value = newMode
        if (newMode == AuthMode.SMALL_PEERS_ONLY) {
            authUrl.value = ""
            httpApiUrl.value = ""
        }
    }

    suspend fun save(): Long {
        val database = DittoDatabase(
            id = if (isNewItem) 0L else editId,
            name = name.value.trim(),
            databaseId = databaseId.value.trim(),
            token = token.value.trim(),
            authUrl = authUrl.value.trim(),
            httpApiUrl = httpApiUrl.value.trim(),
            httpApiKey = httpApiKey.value.trim(),
            mode = mode.value,
            allowUntrustedCerts = allowUntrustedCerts.value,
            secretKey = secretKey.value.trim(),
            logLevel = logLevel.value,
            isStrictModeEnabled = isStrictModeEnabled.value,
        )
        return repository.save(database)
    }
}
