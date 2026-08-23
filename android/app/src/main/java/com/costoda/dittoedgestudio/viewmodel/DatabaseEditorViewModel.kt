package com.costoda.dittoedgestudio.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.costoda.dittoedgestudio.data.ditto.DittoManager
import com.costoda.dittoedgestudio.data.repository.DatabaseRepository
import com.costoda.dittoedgestudio.domain.model.AdvancedSettingsValidator
import com.costoda.dittoedgestudio.domain.model.AuthMode
import com.costoda.dittoedgestudio.domain.model.CollectionSyncScope
import com.costoda.dittoedgestudio.domain.model.DittoDatabase
import com.costoda.dittoedgestudio.domain.model.StartupSetting
import com.costoda.dittoedgestudio.domain.model.StartupSettingType
import com.costoda.dittoedgestudio.domain.model.SyncScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

class DatabaseEditorViewModel(
    private val editId: Long,
    private val repository: DatabaseRepository,
    private val dittoManager: DittoManager? = null,
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

    // MARK: Advanced Configuration

    val collectionSyncScopes = MutableStateFlow<List<CollectionSyncScope>>(emptyList())
    val startupSettings = MutableStateFlow<List<StartupSetting>>(emptyList())

    /** Disclosure state, not persisted — collapsed on every open. */
    val isAdvancedExpanded = MutableStateFlow(false)

    /** Human-readable "name — reason" lines for settings the last open skipped. */
    val lastApplyFailures = MutableStateFlow<List<String>>(emptyList())

    /** True when the last open applied scopes it could not verify. */
    val lastApplyScopesUnverified = MutableStateFlow(false)

    /** True when the stored sync-scope JSON could not be read for this database. */
    val hasCorruptSyncScopes = MutableStateFlow(false)

    /** Set by the user to accept losing the unreadable scopes. */
    val discardCorruptSyncScopes = MutableStateFlow(false)

    /**
     * Set by "Reset to SDK defaults". When the edited database is the one currently
     * open, saving issues `ALTER SYSTEM RESET ALL` against the live instance and
     * re-applies everything the app manages.
     */
    val resetToDefaultsRequested = MutableStateFlow(false)

    /** Non-fatal save follow-on failure (e.g. live reset) to surface in the UI. */
    val saveWarning = MutableStateFlow<String?>(null)

    /** Lists captured by "Reset to SDK Defaults" so the action can be undone. */
    private var preResetSyncScopes: List<CollectionSyncScope> = emptyList()
    private var preResetStartupSettings: List<StartupSetting> = emptyList()

    private val basicsValid = combine(name, databaseId, token) { n, d, t ->
        n.isNotBlank() && d.isNotBlank() && t.isNotBlank()
    }

    /** True while the unreadable scopes have neither been replaced nor explicitly discarded. */
    private fun blocksSaveForCorruptScopes(
        corrupt: Boolean,
        scopes: List<CollectionSyncScope>,
        discard: Boolean,
    ) = corrupt && scopes.isEmpty() && !discard

    private fun advancedErrors(
        scopes: List<CollectionSyncScope>,
        settings: List<StartupSetting>,
        corrupt: Boolean,
        discard: Boolean,
    ): Boolean {
        if (blocksSaveForCorruptScopes(corrupt, scopes, discard)) return true
        if (scopes.any { syncScopeError(it.id, scopes) != null }) return true
        if (settings.any { startupSettingError(it.id, settings) != null }) return true
        if (scopes.size > AdvancedSettingsValidator.MAX_ROW_COUNT) return true
        if (settings.size > AdvancedSettingsValidator.MAX_ROW_COUNT) return true
        return false
    }

    val hasAdvancedValidationErrors: StateFlow<Boolean> =
        combine(collectionSyncScopes, startupSettings, hasCorruptSyncScopes, discardCorruptSyncScopes) {
                scopes, settings, corrupt, discard,
            ->
            advancedErrors(scopes, settings, corrupt, discard)
        }.stateIn(viewModelScope, SharingStarted.Eagerly, false)

    val canSave: StateFlow<Boolean> =
        combine(
            basicsValid,
            collectionSyncScopes,
            startupSettings,
            hasCorruptSyncScopes,
            discardCorruptSyncScopes,
        ) { valid, scopes, settings, corrupt, discard ->
            valid && !advancedErrors(scopes, settings, corrupt, discard)
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
        collectionSyncScopes.value = database.collectionSyncScopes
        // Canonicalised on the way in: a stored Boolean row spelled `true`/`FALSE` is
        // valid but unrenderable — the value dropdown's tags are exactly
        // "True"/"False", so no tag matches and it draws blank.
        startupSettings.value = database.startupSettings.map(::canonicalizingBooleanValue)
        hasCorruptSyncScopes.value = database.hasCorruptSyncScopes
        loadLastApplyOutcome()
    }

    /**
     * Pulls the outcome of the most recent apply for this database, if it is the one
     * currently open, so skipped settings are visible in the UI rather than only in
     * the log output.
     */
    fun loadLastApplyOutcome() {
        val manager = dittoManager
        val active = manager?.currentDatabase()
        val result = manager?.lastAdvancedApplyResult
        if (active == null || active.id != editId || result == null) {
            lastApplyFailures.value = emptyList()
            lastApplyScopesUnverified.value = false
            return
        }
        lastApplyFailures.value = result.skippedSettings.map { "${it.name} — ${it.reason}" }
        lastApplyScopesUnverified.value = result.scopesUnverified
    }

    fun switchMode(newMode: AuthMode) {
        mode.value = newMode
        if (newMode == AuthMode.SMALL_PEERS_ONLY) {
            authUrl.value = ""
            httpApiUrl.value = ""
        }
    }

    // MARK: - Row validation

    /** Validation error for a scope row, if any. */
    fun syncScopeError(id: String, scopes: List<CollectionSyncScope> = collectionSyncScopes.value):
        AdvancedSettingsValidator.CollectionError? {
        val row = scopes.firstOrNull { it.id == id } ?: return null
        val others = scopes.filter { it.id != id }.map { it.collection }
        return AdvancedSettingsValidator.validateCollection(row.collection, others)
    }

    /** Validation error for a startup-setting row, if any. */
    fun startupSettingError(id: String, settings: List<StartupSetting> = startupSettings.value):
        AdvancedSettingsValidator.ParameterError? {
        val row = settings.firstOrNull { it.id == id } ?: return null
        val others = settings.filter { it.id != id }.map { it.parameter }
        return AdvancedSettingsValidator.validateSetting(row, others)
    }

    /** True when the row is risky, whether or not it has been acknowledged — the
     * switch stays visible once ticked so the user can withdraw it. */
    fun isSensitiveRow(id: String): Boolean {
        val setting = startupSettings.value.firstOrNull { it.id == id } ?: return false
        val name = setting.syncKey
        return name.isNotEmpty() && AdvancedSettingsValidator.isSensitiveParameter(name)
    }

    // MARK: - Row mutations

    fun updateScopeCollection(id: String, newValue: String) {
        collectionSyncScopes.value = collectionSyncScopes.value.map {
            if (it.id == id) it.copy(collection = newValue) else it
        }
    }

    fun updateScope(id: String, newValue: SyncScope) {
        collectionSyncScopes.value = collectionSyncScopes.value.map {
            if (it.id == id) it.copy(scope = newValue) else it
        }
    }

    /**
     * Acknowledgement is stored ON the row (and persisted), so it survives a
     * rename-free round trip and, critically, is re-checked on the apply path for
     * settings that never passed through this editor.
     */
    fun setAcknowledged(id: String, acknowledged: Boolean) {
        startupSettings.value = startupSettings.value.map {
            if (it.id == id) it.copy(isAcknowledged = acknowledged) else it
        }
    }

    /** Renaming revokes the acknowledgement: it approved a specific parameter, so
     * turning `foo_port` into `additional_p2p_trusted_ca_certs` must re-prompt. */
    fun setParameter(id: String, newValue: String) {
        startupSettings.value = startupSettings.value.map {
            if (it.id != id) return@map it
            val previous = it.syncKey.lowercase()
            val renamed = it.copy(parameter = newValue)
            if (renamed.syncKey.lowercase() != previous) renamed.copy(isAcknowledged = false) else renamed
        }
    }

    /** Editing the value revokes it too — approving `127.0.0.1:9000` is not approval
     * for `0.0.0.0:9000`, which listens on every interface. */
    fun setValue(id: String, newValue: String) {
        startupSettings.value = startupSettings.value.map {
            if (it.id != id || it.value == newValue) return@map it
            val updated = it.copy(value = newValue)
            if (AdvancedSettingsValidator.isSensitiveParameter(updated.syncKey)) {
                updated.copy(isAcknowledged = false)
            } else {
                updated
            }
        }
    }

    /**
     * Changes a row's type, seeding a valid default when switching to Boolean but
     * never clearing a typed value otherwise — silently discarding a pasted blob
     * because the dropdown was brushed has no undo.
     */
    fun setType(id: String, newValue: StartupSettingType) {
        startupSettings.value = startupSettings.value.map {
            if (it.id != id || it.type == newValue) return@map it
            var updated = it.copy(type = newValue)
            if (newValue == StartupSettingType.Boolean) {
                // A boolean row's value must be one of the dropdown's exact tags. An
                // existing boolean is kept — only its spelling is canonicalised.
                val canonical = StartupSetting.canonicalBooleanValue(updated.value)
                val seeded = canonical ?: "True"
                if (seeded != updated.value) {
                    updated = updated.copy(value = seeded)
                    // Seeding — as opposed to re-spelling — is a real value change, and
                    // an acknowledgement approved a (name, value) pair. Canonicalising
                    // `true` → `True` is NOT a value change and must not re-prompt.
                    if (canonical == null &&
                        AdvancedSettingsValidator.isSensitiveParameter(updated.syncKey)
                    ) {
                        updated = updated.copy(isAcknowledged = false)
                    }
                }
            }
            updated
        }
    }

    fun addSyncScope() {
        if (collectionSyncScopes.value.size >= AdvancedSettingsValidator.MAX_ROW_COUNT) return
        collectionSyncScopes.value = collectionSyncScopes.value + CollectionSyncScope()
    }

    fun removeSyncScope(id: String) {
        collectionSyncScopes.value = collectionSyncScopes.value.filterNot { it.id == id }
    }

    fun addStartupSetting() {
        if (startupSettings.value.size >= AdvancedSettingsValidator.MAX_ROW_COUNT) return
        startupSettings.value = startupSettings.value + StartupSetting()
    }

    fun removeStartupSetting(id: String) {
        startupSettings.value = startupSettings.value.filterNot { it.id == id }
    }

    // MARK: - Reset to SDK Defaults

    /**
     * Clears both lists and marks the config so a live instance is reset to SDK
     * defaults on save. On a database that isn't open there is nothing to reset —
     * `ALTER SYSTEM` state dies with the instance, so the next open is already at
     * defaults.
     */
    fun resetAdvancedToDefaults() {
        // Snapshot so the user can back out. Only on the FIRST reset: re-snapshotting
        // after the user re-entered a row would replace the original lists with that
        // one new row, losing the real data with no undo.
        if (!resetToDefaultsRequested.value) {
            preResetSyncScopes = collectionSyncScopes.value
            preResetStartupSettings = startupSettings.value
        }
        collectionSyncScopes.value = emptyList()
        startupSettings.value = emptyList()
        resetToDefaultsRequested.value = true
    }

    /** True while Undo Reset is safe to offer — once the user has started re-entering
     * rows, restoring the snapshot would silently discard that work. */
    val canUndoResetToDefaults: Boolean
        get() = resetToDefaultsRequested.value &&
            collectionSyncScopes.value.isEmpty() &&
            startupSettings.value.isEmpty()

    /** Restores the lists the reset cleared and cancels the pending `RESET ALL`. */
    fun undoResetToDefaults() {
        if (!canUndoResetToDefaults) return
        collectionSyncScopes.value = preResetSyncScopes
        startupSettings.value = preResetStartupSettings
        preResetSyncScopes = emptyList()
        preResetStartupSettings = emptyList()
        resetToDefaultsRequested.value = false
    }

    /** Summary shown in the disclosure header. */
    fun advancedSummary(): String {
        val scopes = collectionSyncScopes.value.size
        val settings = startupSettings.value.size
        val scopeText = if (scopes == 1) "1 scope" else "$scopes scopes"
        val settingText = if (settings == 1) "1 startup setting" else "$settings startup settings"
        return "$scopeText · $settingText"
    }

    // MARK: - Save

    /** Trimmed rows, dropping fully-blank ones so a half-typed row doesn't get persisted. */
    private fun normalizedSyncScopes(): List<CollectionSyncScope> =
        collectionSyncScopes.value.mapNotNull { row ->
            val name = row.syncKey
            if (name.isEmpty()) null else row.copy(collection = name)
        }

    private fun normalizedStartupSettings(): List<StartupSetting> =
        startupSettings.value.mapNotNull { row ->
            val name = row.syncKey
            if (name.isEmpty()) null else row.copy(parameter = name)
        }

    /**
     * Saves the config. Returns true when the editor may dismiss. A failed live
     * `RESET ALL` leaves the (committed) save in place but returns false and sets
     * [saveWarning] so the user sees what happened.
     */
    suspend fun save(): Boolean {
        saveWarning.value = null
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
            collectionSyncScopes = normalizedSyncScopes(),
            startupSettings = normalizedStartupSettings(),
        )
        val savedId = repository.save(database)
        val saved = database.copy(id = if (isNewItem) savedId else database.id)

        if (!isNewItem) {
            val manager = dittoManager
            if (manager != null) {
                // Keep the manager's copy of the active config current, or a later
                // sync restart would re-apply the settings this database was opened
                // with — silently reverting the scope the user just changed.
                manager.refreshActiveConfigIfMatching(saved)

                // "Reset to SDK defaults" only has an observable effect on a live
                // instance; for a closed database the next open already starts at
                // defaults. Surfaced rather than swallowed: a failed RESET ALL means
                // the saved config says "defaults" while the running instance still
                // has the old parameters — including transports the user disabled.
                if (resetToDefaultsRequested.value) {
                    try {
                        manager.resetSystemSettingsToDefaults(saved)
                    } catch (e: Exception) {
                        saveWarning.value =
                            "Settings were saved, but restoring Ditto's defaults on the " +
                            "running database failed: ${e.message} " +
                            "Close and reopen the database to apply them."
                        return false
                    }
                }
            }
        }
        // The write committed, so the pending reset is no longer pending.
        resetToDefaultsRequested.value = false
        return true
    }

    companion object {
        /** Returns [setting] with a Boolean value spelled the way the dropdown tags it.
         * Non-boolean rows and unrecognised text are returned untouched. */
        private fun canonicalizingBooleanValue(setting: StartupSetting): StartupSetting {
            if (setting.type != StartupSettingType.Boolean) return setting
            val canonical = StartupSetting.canonicalBooleanValue(setting.value) ?: return setting
            if (canonical == setting.value) return setting
            return setting.copy(value = canonical)
        }
    }
}
