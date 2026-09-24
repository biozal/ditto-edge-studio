package com.costoda.dittoedgestudio.domain.model

enum class AuthMode(val value: String, val displayName: String) {
    SERVER("server", "Server"),
    SMALL_PEERS_ONLY("smallpeersonly", "Small Peers Only");

    companion object {
        /// Accepted spellings for "small peers only", lower-cased.
        ///
        /// The Apple app encodes this mode as the SDK-5 raw value `smallPeerOnly`
        /// (`AuthMode.swift`), which matched neither the exact-comparison below nor the
        /// stored value `smallpeersonly`. It therefore fell through to the silent
        /// `?: SERVER` default, and a Small-Peer-Only (offline) database shared from
        /// macOS/iPadOS was imported here as a cloud-connecting Server database — where
        /// `DittoManager` requires a token and an authUrl the offline config does not have.
        ///
        /// The tolerance already existed in the other direction: Apple's
        /// `DittoAppConfigLoader.parseMode` lower-cases and accepts several spellings, so
        /// Android → Apple mapped correctly. This is the missing half.
        private val SMALL_PEER_ALIASES = setOf(
            "smallpeersonly", // this app's stored value
            "smallpeeronly", // SDK-5 raw value from Apple, lower-cased
            "offline",
            "sharedkey",
        )

        fun fromValue(value: String): AuthMode {
            val normalized = value.trim().lowercase()
            return when {
                normalized in SMALL_PEER_ALIASES -> SMALL_PEERS_ONLY
                else -> entries.firstOrNull { it.value == normalized } ?: SERVER
            }
        }
    }
}
