package com.costoda.dittoedgestudio.ui.mainstudio.presence

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.remember
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.dp
import com.costoda.dittoedgestudio.domain.model.ConnectionType

/**
 * Per-transport visual styling for the presence graph.
 *
 * The dash patterns mirror iOS `ConnectionLine.swift` byte-for-byte so a peer sniffing
 * traffic looks the same on both platforms. Colors are tuned for AA contrast against
 * Material 3 light and dark surface tones.
 *
 * Constants are exposed at file scope so the renderer can build a single
 * `PathEffect.dashPathEffect` per `(ConnectionType, isCloud)` cell and reuse it for
 * every edge — no allocation in `drawBehind`.
 */

// Dash intervals in dp.
//
// Diverges from iOS `ConnectionLine.swift` for accessibility: iOS uses [3,2] vs [6,3]
// for Bluetooth vs P2P WiFi, which differ only in scalar length — colorblind users (and
// anyone looking at a short edge) can't distinguish them. The patterns below are
// shape-distinct so each transport reads as a different glyph along the line.
//
//   bluetooth   -> [2, 7]              tiny dots, wide gaps   ▪  ▪  ▪  ▪  ▪
//   accessPoint -> [20, 6]             long bars              ━━━━━ ━━━━━ ━━━━━
//   p2pWiFi     -> [6, 6]              equal dash + gap       ━━ ━━ ━━ ━━ ━━
//   webSocket   -> [12, 5, 2, 5]       dash-dot               ━━━━ • ━━━━ • ━━━━
//   cloud       -> [10, 5] + circles   short dash + glyphs    ━━ ● ━━ ● ━━ ● ━━
internal val DashBluetoothDp: FloatArray = floatArrayOf(2f, 7f)
internal val DashLanDp: FloatArray = floatArrayOf(20f, 6f)
internal val DashP2pWifiDp: FloatArray = floatArrayOf(6f, 6f)
internal val DashWebSocketDp: FloatArray = floatArrayOf(12f, 5f, 2f, 5f)
internal val DashCloudDp: FloatArray = floatArrayOf(10f, 5f)

// Light/dark hex pairs per the plan table.
private val BluetoothLight = Color(0xFF0066D9)
private val BluetoothDark = Color(0xFF3D8FE8)
private val LanLight = Color(0xFF0D8540)
private val LanDark = Color(0xFF1FA858)
private val P2pWifiLight = Color(0xFFC71A38)
private val P2pWifiDark = Color(0xFFE04657)
private val WebSocketLight = Color(0xFFD97A00)
private val WebSocketDark = Color(0xFFF09518)
private val CloudLight = Color(0xFF7326B8)
private val CloudDark = Color(0xFF9445D6)
private val FallbackLight = Color(0xFF666666)
private val FallbackDark = Color(0xFF999999)

/** Lookup key for the cached dash-effect table. */
@Immutable
internal data class DashKey(val type: ConnectionType, val isCloud: Boolean)

/**
 * Resolve the stroke color for a given transport. [isCloud] overrides [type] (any cloud
 * edge is purple regardless of its nominal WebSocket type).
 *
 * Theme awareness: uses `isSystemInDarkTheme()` so dashed lines stay readable on the
 * Material 3 surface tone that hosts them.
 */
@Composable
internal fun connectionColor(type: ConnectionType, isCloud: Boolean): Color {
    val dark = isSystemInDarkTheme()
    return resolveColor(type, isCloud, dark)
}

internal fun resolveColor(type: ConnectionType, isCloud: Boolean, dark: Boolean): Color {
    if (isCloud) return if (dark) CloudDark else CloudLight
    return when (type) {
        ConnectionType.Bluetooth -> if (dark) BluetoothDark else BluetoothLight
        ConnectionType.LAN -> if (dark) LanDark else LanLight
        ConnectionType.P2PWiFi -> if (dark) P2pWifiDark else P2pWifiLight
        ConnectionType.WebSocket -> if (dark) WebSocketDark else WebSocketLight
        ConnectionType.Unknown -> if (dark) FallbackDark else FallbackLight
    }
}

/**
 * Pure-Kotlin lookup of the dash intervals (still in dp). Exposed for unit testing —
 * the renderer goes through [rememberDashEffects] which already converts to px.
 */
internal fun dashIntervalsDp(type: ConnectionType, isCloud: Boolean): FloatArray = when {
    isCloud -> DashCloudDp
    type == ConnectionType.Bluetooth -> DashBluetoothDp
    type == ConnectionType.LAN -> DashLanDp
    type == ConnectionType.P2PWiFi -> DashP2pWifiDp
    type == ConnectionType.WebSocket -> DashWebSocketDp
    else -> DashP2pWifiDp
}

/**
 * Build a `(ConnectionType × isCloud) → PathEffect` table, memoized by `LocalDensity`
 * so density changes (e.g. folding from inner display to outer) rebuild only once. The
 * renderer pulls effects from this map inside `drawBehind` — there is no allocation
 * on the hot path.
 */
@Composable
internal fun rememberDashEffects(): Map<DashKey, PathEffect> {
    val density = LocalDensity.current
    return remember(density) {
        buildMap {
            for (type in ConnectionType.entries) {
                for (isCloud in listOf(false, true)) {
                    val intervals = dashIntervalsDp(type, isCloud)
                    val px = FloatArray(intervals.size) { i ->
                        with(density) { intervals[i].dp.toPx() }
                    }
                    put(DashKey(type, isCloud), PathEffect.dashPathEffect(px, 0f))
                }
            }
        }
    }
}
