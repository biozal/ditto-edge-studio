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
) {
    companion object {
        fun empty(): DittoDatabase = DittoDatabase()
    }
}
