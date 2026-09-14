package com.costoda.dittoedgestudio.domain.model

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Cross-platform parity tests for [LogComponent].
 *
 * The expectations here are transcribed from
 * `SwiftUI/EdgeStudio/Models/LogEntry.swift` (`LogComponent.from(target:)` and
 * `LogComponent.heuristic(from:)`). If a case here fails, Android and SwiftUI
 * are filing the same log line under different components — which shows up as a
 * different row count behind the same component filter on the two platforms.
 */
class LogComponentTest {

    // ── from(target) — the 866-record regression ─────────────────────────────

    /**
     * The exact target strings that used to classify as `Other` on Android while
     * SwiftUI classified them as `Transport`.
     *
     * Measured over the 33 real captures under
     * `~/Library/Containers/com.costoda.dittoedgestudio/…/ditto_logs/` — the
     * `.log` files and their rotated `.log.gz` siblings
     * (746 282 JSON Lines records, gzipped files decompressed and included):
     * 866 records in total, distributed as noted per case. Android's list matched
     * only `sync`/`store`/`query`/`observer`/`transport`/`network`/`bluetooth`/
     * `wifi`/`auth`, so every `discovery`, `presence` and `multihop` target fell
     * through to `Other`.
     */
    @Test
    fun `previously misclassified SDK targets now classify as Transport`() {
        val regressed = listOf(
            "ditto_discovery_mdns", // 571 records
            "ditto_discovery_multicast::interface", // 157 records
            "ditto_discovery_multicast", // 119 records
            "ditto_presence::multihop::manager", // 18 records
            "ditto_discovery_mdns::platform::bonjour::browser", // 1 record
        )
        regressed.forEach { target ->
            assertEquals(
                "target=$target must be Transport (SwiftUI parity)",
                LogComponent.TRANSPORT,
                LogComponent.from(target),
            )
        }
    }

    @Test
    fun `from target covers every substring in the SwiftUI list`() {
        val cases = listOf(
            "ditto_sync::coordinator" to LogComponent.SYNC,
            "ditto_replication::engine" to LogComponent.SYNC,
            "ditto_subscription::manager" to LogComponent.SYNC,
            "ditto_store::write" to LogComponent.STORE,
            "service=blob" to LogComponent.STORE,
            "ditto_query::planner" to LogComponent.QUERY,
            "dittosqlparser" to LogComponent.QUERY,
            "ditto_sql_parser::lexer" to LogComponent.QUERY,
            "ditto_observer::live" to LogComponent.OBSERVER,
            "ditto_transport::tcp_server" to LogComponent.TRANSPORT,
            "ditto_discovery_mdns" to LogComponent.TRANSPORT,
            "ditto_presence::manager" to LogComponent.TRANSPORT,
            "ditto_multihop::router" to LogComponent.TRANSPORT,
            "ditto_network::stack" to LogComponent.TRANSPORT,
            "ditto_ble::central" to LogComponent.TRANSPORT,
            "ditto_tcp::listener" to LogComponent.TRANSPORT,
            "ditto_awdl::browser" to LogComponent.TRANSPORT,
            "ditto_virtual_connection" to LogComponent.TRANSPORT,
            "ditto_router::table" to LogComponent.TRANSPORT,
            "ditto_auth::client" to LogComponent.AUTH,
            "ditto_unknown_subsystem" to LogComponent.OTHER,
        )
        cases.forEach { (target, expected) ->
            assertEquals("target=$target", expected, LogComponent.from(target))
        }
    }

    /**
     * Match **order** is part of the contract, not an implementation detail —
     * these targets contain two or more tokens from the list and only the Swift
     * ordering resolves them this way.
     */
    @Test
    fun `from target resolves overlapping tokens in the SwiftUI order`() {
        // `sync` is tested before `query`
        assertEquals(LogComponent.SYNC, LogComponent.from("ditto_sync::query_planner"))
        // `store` is tested before `transport`
        assertEquals(LogComponent.STORE, LogComponent.from("ditto_store::tcp_writer"))
        // `query` is tested before `observer` and every transport token
        assertEquals(LogComponent.QUERY, LogComponent.from("ditto_query::observer_hook"))
        assertEquals(LogComponent.QUERY, LogComponent.from("ditto_query::ble_scan"))
        // `transport` is tested before `auth`
        assertEquals(LogComponent.TRANSPORT, LogComponent.from("ditto_transport::auth_handshake"))
    }

    @Test
    fun `from target is case insensitive`() {
        assertEquals(LogComponent.TRANSPORT, LogComponent.from("Ditto_Discovery_MDNS"))
        assertEquals(LogComponent.SYNC, LogComponent.from("DITTO::SYNC"))
    }

    @Test
    fun `from blank target is Other`() {
        assertEquals(LogComponent.OTHER, LogComponent.from(""))
    }

    // ── heuristic(message) ───────────────────────────────────────────────────

    @Test
    fun `heuristic covers every branch in the SwiftUI list`() {
        val cases = listOf(
            "sync session opened" to LogComponent.SYNC,
            "replication window advanced" to LogComponent.SYNC,
            "subscription registered" to LogComponent.SYNC,
            "store commit applied" to LogComponent.STORE,
            "insert completed" to LogComponent.STORE,
            "document evicted" to LogComponent.STORE,
            "add_ble_transport called with query args" to LogComponent.TRANSPORT,
            "start_tcp_server on port 4040" to LogComponent.TRANSPORT,
            "add_awdl_transport enabled" to LogComponent.TRANSPORT,
            "add_wifi_transport enabled" to LogComponent.TRANSPORT,
            "tcp peer connected" to LogComponent.TRANSPORT,
            "awdl browse started" to LogComponent.TRANSPORT,
            "query executed in 4ms" to LogComponent.QUERY,
            "select * from cars" to LogComponent.QUERY,
            "parsing sql statement" to LogComponent.QUERY,
            "sql parser recovered" to LogComponent.QUERY,
            "observer fired" to LogComponent.OBSERVER,
            "transport condition changed" to LogComponent.TRANSPORT,
            "bluetooth radio powered on" to LogComponent.TRANSPORT,
            "wifi aware session ready" to LogComponent.TRANSPORT,
            "discovery started" to LogComponent.TRANSPORT,
            "mdns browse response" to LogComponent.TRANSPORT,
            "presence graph updated" to LogComponent.TRANSPORT,
            "multihop route computed" to LogComponent.TRANSPORT,
            "ble_central scanning" to LogComponent.TRANSPORT,
            "peripheral ble radio ready" to LogComponent.TRANSPORT,
            "virtual_connection opened" to LogComponent.TRANSPORT,
            "router_table pruned" to LogComponent.TRANSPORT,
            "auth failed" to LogComponent.AUTH,
            "token refreshed" to LogComponent.AUTH,
            "nothing interesting happened" to LogComponent.OTHER,
        )
        cases.forEach { (message, expected) ->
            assertEquals("message=$message", expected, LogComponent.heuristic(message))
        }
    }

    /**
     * The reason the transport probes sit **above** `query` in the Swift
     * ordering: these SDK operation names carry a `query` substring in the same
     * flattened line, and without the transport-first branches they would all be
     * filed under Query.
     */
    @Test
    fun `heuristic keeps transport operation names ahead of the query token`() {
        assertEquals(
            LogComponent.TRANSPORT,
            LogComponent.heuristic("add_ble_transport: query_config=default"),
        )
        assertEquals(
            LogComponent.TRANSPORT,
            LogComponent.heuristic("start_tcp_server: query timeout 30s"),
        )
        // But a plain `query` mention with no transport token stays Query — the
        // ordering must not over-claim.
        assertEquals(LogComponent.QUERY, LogComponent.heuristic("query planner selected index"))
    }

    /**
     * SwiftUI parity, and the reason `LogFileParserTest` no longer asserts
     * "transport prefix beats a query substring": SwiftUI's heuristic tests
     * `query` **before** the generic `transport` branch, so a message that
     * mentions both and does not start with one of the four transport operation
     * names resolves to Query on both platforms.
     */
    @Test
    fun `heuristic files a bracketed transport tag containing query as Query like SwiftUI`() {
        assertEquals(
            LogComponent.QUERY,
            LogComponent.heuristic("[transport::bluetooth] Discovered query endpoint"),
        )
    }

    @Test
    fun `heuristic resolves overlapping tokens in the SwiftUI order`() {
        // `sync` beats everything
        assertEquals(LogComponent.SYNC, LogComponent.heuristic("sync failed: bluetooth off"))
        // `document` (store) beats `query`
        assertEquals(LogComponent.STORE, LogComponent.heuristic("document returned by query"))
        // `tcp` beats `query`
        assertEquals(LogComponent.TRANSPORT, LogComponent.heuristic("tcp read while query pending"))
        // `query` beats `observer`
        assertEquals(LogComponent.QUERY, LogComponent.heuristic("query registered an observer"))
        // `presence` beats `auth`
        assertEquals(LogComponent.TRANSPORT, LogComponent.heuristic("presence peer auth ok"))
    }

    @Test
    fun `heuristic is case insensitive`() {
        assertEquals(LogComponent.TRANSPORT, LogComponent.heuristic("MDNS Browse Response"))
        assertEquals(LogComponent.SYNC, LogComponent.heuristic("SYNC STARTED"))
    }
}
