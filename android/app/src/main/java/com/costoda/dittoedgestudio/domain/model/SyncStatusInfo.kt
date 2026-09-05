package com.costoda.dittoedgestudio.domain.model

data class SyncStatusInfo(
    val peerId: String,
    val isDittoServer: Boolean = false,
    val deviceName: String?,
    val osInfo: PeerOS = PeerOS.Unknown,
    val dittoSdkVersion: String?,
    val connections: List<PeerConnectionInfo> = emptyList(),
    val peerMetadata: String? = null,
    /**
     * Top-level key count of [peerMetadata]. Carried from the SDK's typed object rather
     * than derived from the string: `ObjectValue.toString()` emits Kotlin map syntax,
     * not JSON, so parsing it back always fails.
     */
    val peerMetadataKeyCount: Int = 0,
    val identityServiceMetadata: String? = null,
    val identityServiceMetadataKeyCount: Int = 0,
    val syncedUpToLocalCommitId: Long? = null,
    val lastUpdateReceivedTime: Double? = null,
) {
    val formattedLastUpdate: String
        get() {
            val ms = lastUpdateReceivedTime ?: return "Never"
            val date = java.util.Date(ms.toLong())
            val diff = System.currentTimeMillis() - date.time
            return when {
                diff < 60_000L -> "Just now"
                diff < 3_600_000L -> "${diff / 60_000} min ago"
                diff < 86_400_000L -> "${diff / 3_600_000} hr ago"
                else -> java.text.SimpleDateFormat(
                    "MMM d, h:mm a", java.util.Locale.getDefault()
                ).format(date)
            }
        }
}

data class PeerConnectionInfo(
    val id: String,
    val type: ConnectionType,
)

enum class ConnectionType(val displayName: String) {
    Bluetooth("Bluetooth"),
    LAN("LAN"),
    P2PWiFi("P2P WiFi"),

    /** Reliable UDP multicast transport (beta, Ditto SDK 5.1.0). */
    Multicast("Multicast"),
    WebSocket("WebSocket"),
    Unknown("Unknown"),
}

enum class PeerOS(val displayName: String) {
    iOS("iOS"),
    Android("Android"),
    MacOS("macOS"),
    Linux("Linux"),
    Windows("Windows"),
    Unknown("Unknown"),
}
