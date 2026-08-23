package com.costoda.dittoedgestudio.domain.model

data class DittoDatabase(
    val id: Long = 0,
    val name: String = "",
    val databaseId: String = "",
    val token: String = "",
    val authUrl: String = "",
    val websocketUrl: String = "",
    val httpApiUrl: String = "",
    val httpApiKey: String = "",
    val mode: AuthMode = AuthMode.SERVER,
    val allowUntrustedCerts: Boolean = false,
    val secretKey: String = "",
    val isBluetoothLeEnabled: Boolean = true,
    val isLanEnabled: Boolean = true,
    val isAwdlEnabled: Boolean = false,
    val isCloudSyncEnabled: Boolean = true,
    val logLevel: String = "info",
    val isStrictModeEnabled: Boolean = false,
    val collectionSyncScopes: List<CollectionSyncScope> = emptyList(),
    val startupSettings: List<StartupSetting> = emptyList(),
    /**
     * True when the stored sync-scope JSON could not be decoded. Such a config is
     * unopenable — scopes are a containment control, so "probably applied" is not
     * good enough — and the editor blocks Save until the scopes are re-entered or
     * the loss is explicitly confirmed. Never persisted; derived at decode time.
     */
    val hasCorruptSyncScopes: Boolean = false,
) {
    companion object {
        fun empty(): DittoDatabase = DittoDatabase()
    }
}
