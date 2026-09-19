package com.costoda.dittoedgestudio.domain.model

/**
 * Settings for the reliable UDP multicast transport (beta, Ditto SDK 5.1.0 —
 * `DittoTransportConfig.PeerToPeer.MulticastBeta`).
 *
 * Persisted per database (four `databaseConfigs` columns, Room v7). Defaults match
 * the SDK defaults, so a config equal to `MulticastConfig()` is a no-op.
 *
 * Field-proven rules (from the Zava Retail demo, verified on-device with 5.1.0):
 * - The SDK **defers multicast changes while sync is active** — callers must stop
 *   sync, apply, then restart sync (the existing transport-apply path already does).
 * - Port 0 is rejected: the SDK treats it as "pick any port", which silently breaks
 *   group rendezvous between peers.
 */
data class MulticastConfig(
    val enabled: Boolean = false,
    val groupAddress: String = DEFAULT_GROUP_ADDRESS,
    val port: Int = DEFAULT_PORT,
    val interfaceName: String? = null,
) {
    companion object {
        const val DEFAULT_GROUP_ADDRESS = "224.1.2.3"
        const val DEFAULT_PORT = 6003

        /**
         * IPv4 class-D dotted-quad: four octets 0..255, first in 224..239.
         *
         * Strict octet parsing, mirroring SwiftUI's validator and the SDK's
         * Rust `Ipv4Addr::parse` (the validator the SDK runs at
         * `sync.start()`): Kotlin's `toIntOrNull` accepts leading zeros,
         * a leading `+`, and non-ASCII digits, all of which the SDK rejects.
         * A value that only fails at sync start is persisted first and then
         * fails on every open — it must be rejected here, at the boundary.
         * Note `parsePort` is intentionally NOT strictened: the port crosses
         * the FFI as an integer, so "+6003"/"06003" parse to the same value.
         */
        fun isValidGroupAddress(address: String): Boolean {
            val parts = address.trim().split(".")
            if (parts.size != 4) return false
            val octets = parts.map { part ->
                if (part.isEmpty() || part.any { it !in '0'..'9' }) return false
                if (part.length > 1 && part.startsWith("0")) return false
                part.toIntOrNull()?.takeIf { it in 0..255 } ?: return false
            }
            return octets.first() in 224..239
        }

        /** Parses [text] as a UDP port; null unless a whole number in 1..65535. */
        fun parsePort(text: String): Int? =
            text.trim().toIntOrNull()?.takeIf { it in 1..65535 }
    }
}
