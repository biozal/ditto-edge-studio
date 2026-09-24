package com.costoda.dittoedgestudio.domain.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonNames

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
    // ── SDK 5 renames ───────────────────────────────────────────────────────
    // SwiftUI's `DittoConfigForDatabase` renamed `token` -> `developmentToken`
    // and `authUrl` -> `url` for SDK 5, and dropped `websocketUrl` entirely
    // (the cloud WebSocket is derived from the auth URL now). It keeps the old
    // spellings only as *decode* fallbacks, so every QR it produces carries the
    // new names.
    //
    // This decoder still required the old ones. With `ignoreUnknownKeys = true`
    // the new keys were silently dropped and kotlinx then threw
    // `MissingFieldException` for the three it could not find, which surfaced
    // as "Invalid QR code — not a valid database config" for every code the Mac
    // app generated. Both spellings are accepted here, new preferred, so codes
    // from either version import.
    @JsonNames("token") val developmentToken: String = "",
    @JsonNames("authUrl") val url: String = "",
    /// Dropped in SDK 5; still accepted so pre-5 codes keep importing.
    val websocketUrl: String = "",
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
) {
    /// Alias kept so call sites read naturally regardless of which spelling the
    /// payload used.
    val token: String get() = developmentToken

    val authUrl: String get() = url
}

@Serializable
data class QrFavoriteItem(
    val q: String,
)
