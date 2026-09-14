package com.costoda.dittoedgestudio.ui.mainstudio.presence

import com.costoda.dittoedgestudio.domain.model.ConnectionType
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Lock-in tests for the per-transport dash patterns.
 *
 * Note: the Android patterns diverge from iOS `ConnectionLine.swift` for accessibility —
 * iOS's [3,2] vs [6,3] are scalar variations of the same shape and look identical to a
 * colorblind user on a short edge. The Android values below are shape-distinct (dots,
 * long bars, even dashes, dash-dot, dash-circle) so each transport reads as its own
 * glyph regardless of color.
 *
 * If you change these arrays, also update the legend swatch examples in
 * `PresenceGraphView.ConnectionLegendCard` and the comment block above [DashBluetoothDp].
 */
class ConnectionStylesTest {

    @Test
    fun `bluetooth uses dotted pattern`() {
        assertArrayEquals(
            floatArrayOf(2f, 7f),
            dashIntervalsDp(ConnectionType.Bluetooth, isCloud = false),
            0f,
        )
    }

    @Test
    fun `lan uses long-bar pattern`() {
        assertArrayEquals(
            floatArrayOf(20f, 6f),
            dashIntervalsDp(ConnectionType.LAN, isCloud = false),
            0f,
        )
    }

    @Test
    fun `p2p wifi uses even dash-gap pattern`() {
        assertArrayEquals(
            floatArrayOf(6f, 6f),
            dashIntervalsDp(ConnectionType.P2PWiFi, isCloud = false),
            0f,
        )
    }

    @Test
    fun `websocket uses dash-dot pattern`() {
        assertArrayEquals(
            floatArrayOf(12f, 5f, 2f, 5f),
            dashIntervalsDp(ConnectionType.WebSocket, isCloud = false),
            0f,
        )
    }

    @Test
    fun `multicast uses dotted pattern matching the VS Code extension`() {
        assertArrayEquals(
            floatArrayOf(2f, 3f),
            dashIntervalsDp(ConnectionType.Multicast, isCloud = false),
            0f,
        )
    }

    @Test
    fun `cloud uses short-dash pattern regardless of nominal type`() {
        assertArrayEquals(
            floatArrayOf(10f, 5f),
            dashIntervalsDp(ConnectionType.WebSocket, isCloud = true),
            0f,
        )
        // isCloud=true overrides every nominal transport
        assertArrayEquals(
            floatArrayOf(10f, 5f),
            dashIntervalsDp(ConnectionType.Bluetooth, isCloud = true),
            0f,
        )
    }

    @Test
    fun `every transport has a distinct pattern shape`() {
        // Convert each pattern to a stable signature; ensure no two transports share one.
        val signatures = listOf(
            "bt" to dashIntervalsDp(ConnectionType.Bluetooth, false).toList(),
            "lan" to dashIntervalsDp(ConnectionType.LAN, false).toList(),
            "p2p" to dashIntervalsDp(ConnectionType.P2PWiFi, false).toList(),
            "ws" to dashIntervalsDp(ConnectionType.WebSocket, false).toList(),
            "multicast" to dashIntervalsDp(ConnectionType.Multicast, false).toList(),
            "cloud" to dashIntervalsDp(ConnectionType.WebSocket, true).toList(),
        )
        for (i in signatures.indices) {
            for (j in i + 1 until signatures.size) {
                assertTrue(
                    "${signatures[i].first} pattern collides with ${signatures[j].first}",
                    signatures[i].second != signatures[j].second,
                )
            }
        }
    }

    @Test
    fun `dark scheme palette differs from light for every transport`() {
        for (type in ConnectionType.entries) {
            val light = resolveColor(type, isCloud = false, dark = false)
            val dark = resolveColor(type, isCloud = false, dark = true)
            assertNotEquals("$type light should differ from dark", light, dark)
        }
        assertNotEquals(
            resolveColor(ConnectionType.WebSocket, isCloud = true, dark = false),
            resolveColor(ConnectionType.WebSocket, isCloud = true, dark = true),
        )
    }
}
