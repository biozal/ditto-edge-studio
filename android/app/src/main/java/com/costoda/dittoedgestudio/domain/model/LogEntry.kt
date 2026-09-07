package com.costoda.dittoedgestudio.domain.model

import com.ditto.kotlin.DittoLogLevel
import java.util.Date
import java.util.UUID

data class LogEntry(
    val id: UUID = UUID.randomUUID(),
    val timestamp: Date,
    val level: DittoLogLevel,
    val message: String,
    val component: LogComponent,
    val source: LogEntrySource,
    val rawLine: String,
)

enum class LogComponent(val displayName: String) {
    ALL("All"),
    SYNC("Sync"),
    STORE("Store"),
    QUERY("Query"),
    OBSERVER("Observer"),
    TRANSPORT("Transport"),
    AUTH("Auth"),
    OTHER("Other");

    companion object {
        /**
         * Maps a Ditto SDK `target` field (e.g. `ditto_discovery_mdns`) to a component.
         *
         * **The substring list and its order are normative** — they mirror
         * `SwiftUI/EdgeStudio/Models/LogEntry.swift` `LogComponent.from(target:)`
         * one-for-one. Order is load-bearing: a target such as
         * `ditto_sync::query_planner` must resolve to [SYNC] because `sync` is
         * tested first, and `service=blob` must resolve to [STORE] before any
         * later transport token can claim it. Reordering these branches silently
         * reclassifies records.
         *
         * Before this list matched the Swift one, 866 of 746 282 real captured
         * records classified differently — every one of them Transport on
         * SwiftUI and [OTHER] here (`ditto_discovery_mdns`,
         * `ditto_discovery_multicast[::interface]`,
         * `ditto_presence::multihop::manager`).
         */
        fun from(target: String): LogComponent {
            val lower = target.lowercase()
            return when {
                "sync" in lower -> SYNC
                "replication" in lower -> SYNC
                "subscription" in lower -> SYNC
                "store" in lower -> STORE
                "service=blob" in lower -> STORE
                "query" in lower -> QUERY
                "sqlparser" in lower || "sql_parser" in lower -> QUERY
                "observer" in lower -> OBSERVER
                "transport" in lower -> TRANSPORT
                "discovery" in lower -> TRANSPORT
                "presence" in lower -> TRANSPORT
                "multihop" in lower -> TRANSPORT
                "network" in lower -> TRANSPORT
                "ble" in lower -> TRANSPORT
                "tcp" in lower -> TRANSPORT
                "awdl" in lower -> TRANSPORT
                "virtual_connection" in lower -> TRANSPORT
                "router" in lower -> TRANSPORT
                "auth" in lower -> AUTH
                else -> OTHER
            }
        }

        /**
         * Heuristic component detection from the flattened live-callback message
         * body, which carries no `target` field.
         *
         * Mirrors `LogComponent.heuristic(from:)` in the SwiftUI reference,
         * including its order. The transport branches ahead of `query` are
         * deliberate: SDK operation names such as `start_tcp_server` and
         * `add_awdl_transport` appear in long message bodies that also happen to
         * contain the word "query", and without the transport-first probes those
         * lines would be filed under [QUERY].
         */
        fun heuristic(message: String): LogComponent {
            val lower = message.lowercase()
            return when {
                "sync" in lower -> SYNC
                "replication" in lower -> SYNC
                "subscription" in lower -> SYNC
                "store" in lower || "insert" in lower || "document" in lower -> STORE
                "service=blob" in lower -> STORE
                // Transport-first: well-known SDK operation names that must not be
                // hijacked by a "query" substring appearing later in the body.
                lower.startsWith("add_ble_transport") ||
                    lower.startsWith("start_tcp_server") ||
                    lower.startsWith("add_awdl_transport") ||
                    lower.startsWith("add_wifi_transport") -> TRANSPORT
                "tcp" in lower -> TRANSPORT
                "awdl" in lower -> TRANSPORT
                "query" in lower || "select" in lower -> QUERY
                lower.startsWith("parsing sql") || "sql parser" in lower -> QUERY
                "observer" in lower -> OBSERVER
                "transport" in lower || "bluetooth" in lower || "wifi" in lower -> TRANSPORT
                "discovery" in lower || "mdns" in lower -> TRANSPORT
                "presence" in lower || "multihop" in lower -> TRANSPORT
                "ble_" in lower || " ble" in lower -> TRANSPORT
                "virtual_connection" in lower -> TRANSPORT
                "router_" in lower -> TRANSPORT
                "auth" in lower || "token" in lower -> AUTH
                else -> OTHER
            }
        }
    }
}

sealed class LogEntrySource {
    object DittoSDK : LogEntrySource()
    object Application : LogEntrySource()

    /** Transport-condition events from `Ditto.transportCondition` (SwiftUI parity). */
    object TransportConditions : LogEntrySource()

    /** Connection-request events from `presence.connectionRequestHandler` (SwiftUI parity). */
    object ConnectionRequests : LogEntrySource()
}

val DittoLogLevel.displayName: String
    get() = when (this) {
        DittoLogLevel.Error -> "Error"
        DittoLogLevel.Warning -> "Warning"
        DittoLogLevel.Info -> "Info"
        DittoLogLevel.Debug -> "Debug"
        DittoLogLevel.Verbose -> "Verbose"
    }

val DittoLogLevel.shortName: String
    get() = when (this) {
        DittoLogLevel.Error -> "ERR"
        DittoLogLevel.Warning -> "WARN"
        DittoLogLevel.Info -> "INFO"
        DittoLogLevel.Debug -> "DBG"
        DittoLogLevel.Verbose -> "VERB"
    }
