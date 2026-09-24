package com.costoda.dittoedgestudio.data.logging

import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.snapshotFlow
import androidx.compose.runtime.snapshots.Snapshot
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * The second half of the A11 confirmation.
 *
 * `DittoLogCaptureServiceTest` shows that the live buffer's **size** stops moving
 * once the store is at [DittoLogCaptureService.MAX_LIVE_ENTRIES] while its
 * contents keep rolling. This test shows what that does to the rescan trigger:
 * `snapshotFlow` is distinct-until-changed, so a key built from a collection size
 * goes silent at exactly that point, and the pattern scan / analytics /
 * histograms / badges that hang off it freeze.
 *
 * It drives `snapshotFlow` directly rather than a composable, so it is a
 * statement about the mechanism, not about any particular screen — but it is the
 * mechanism `LoggingScreen`'s rescan is built on.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class SizeKeyedRescanStallTest {

    private fun entries(from: Int, count: Int): List<String> =
        (from until from + count).map { "line $it" }

    @Test
    fun `a size-keyed snapshotFlow goes silent once the buffer is pinned at its cap`() =
        runTest(UnconfinedTestDispatcher()) {
            // Arrange — a capped ring buffer modelled as Compose state.
            val cap = 50
            val buffer = mutableStateOf(entries(0, 10))
            val emissions = mutableListOf<Int>()
            val job = launch { snapshotFlow { buffer.value.size }.collect { emissions.add(it) } }
            Snapshot.sendApplyNotifications()

            // Act 1 — grow towards the cap: size changes, so the key fires.
            var next = 10
            while (buffer.value.size < cap) {
                buffer.value = (buffer.value + entries(next, 10)).takeLast(cap)
                next += 10
                Snapshot.sendApplyNotifications()
            }
            val emissionsWhileFilling = emissions.size

            // Act 2 — at cap: the contents roll completely, the size cannot move.
            val contentsAtCap = buffer.value
            repeat(5) {
                buffer.value = (buffer.value + entries(next, 10)).takeLast(cap)
                next += 10
                Snapshot.sendApplyNotifications()
            }

            // Assert
            assertEquals("buffer must still be at its cap", cap, buffer.value.size)
            org.junit.Assert.assertNotEquals(
                "buffer contents must actually have changed",
                contentsAtCap,
                buffer.value,
            )
            assertEquals(
                "size-keyed snapshotFlow emitted again after the cap — the stall would not be real",
                emissionsWhileFilling,
                emissions.size,
            )
            assertEquals(
                "last value seen by the consumer is frozen at the cap",
                cap,
                emissions.last(),
            )

            job.cancel()
        }

    @Test
    fun `a monotonic-counter key keeps firing past the cap`() =
        runTest(UnconfinedTestDispatcher()) {
            // Arrange — same buffer, but the key is an ingest counter of the kind
            // DittoLogCaptureService.ingestSequence provides.
            val cap = 50
            val buffer = mutableStateOf(entries(0, cap))
            val ingestSequence = mutableStateOf(0L)
            val emissions = mutableListOf<Long>()
            val job = launch { snapshotFlow { ingestSequence.value }.collect { emissions.add(it) } }
            Snapshot.sendApplyNotifications()
            val emissionsAtCap = emissions.size

            // Act — five publishes that all leave the size at the cap.
            var next = cap
            repeat(5) {
                buffer.value = (buffer.value + entries(next, 10)).takeLast(cap)
                ingestSequence.value += 1
                next += 10
                Snapshot.sendApplyNotifications()
            }

            // Assert
            assertEquals(cap, buffer.value.size)
            assertEquals(emissionsAtCap + 5, emissions.size)

            job.cancel()
        }
}
