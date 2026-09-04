package com.costoda.dittoedgestudio.domain.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class QrCodePayload(
    val version: Int,
    val config: QrConfigPayload,
    val favorites: List<QrFavoriteItem> = emptyList(),
)

@Serializable
data class QrConfigPayload(
    @SerialName("_id") val id: String = "",
    val name: String,
    val databaseId: String,
    val token: String,
    val authUrl: String,
    val websocketUrl: String,
    val httpApiUrl: String,
    val httpApiKey: String,
    val mode: String,
    val allowUntrustedCerts: Boolean,
    val secretKey: String,
    val isBluetoothLeEnabled: Boolean,
    val isLanEnabled: Boolean,
    val isAwdlEnabled: Boolean,
    val isCloudSyncEnabled: Boolean,
    // Multicast (beta) fields default so payloads written before SDK 5.1.0 support
    // still decode (missing key → default = multicast off, SDK-default group/port).
    val isMulticastEnabled: Boolean = false,
    val multicastGroupAddress: String = MulticastConfig.DEFAULT_GROUP_ADDRESS,
    val multicastPort: Int = MulticastConfig.DEFAULT_PORT,
    val multicastInterfaceName: String? = null,
    val logLevel: String,
    val isStrictModeEnabled: Boolean = false,
)

@Serializable
data class QrFavoriteItem(
    val q: String,
)
