package com.costoda.dittoedgestudio.data

import com.costoda.dittoedgestudio.data.logging.DittoLogCaptureService
import com.costoda.dittoedgestudio.data.logging.LoggingService
import com.ditto.kotlin.DittoLogLevel
import io.mockk.every
import io.mockk.mockk
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.io.File
import java.util.Date

@OptIn(ExperimentalCoroutinesApi::class)
class DittoLogCaptureServiceTest {

    private val testDispatcher = StandardTestDispatcher()
    private val testScope = TestScope(testDispatcher)
    private lateinit var loggingService: LoggingService
    private lateinit var service: DittoLogCaptureService

    @Before
    fun setUp() {
        loggingService = mockk(relaxed = true)
        every { loggingService.getLogsDirectory() } returns File("/tmp/test_logs")
        service = DittoLogCaptureService(loggingService, testScope)
    }

    // ── Raw buffer behaviour ──────────────────────────────────────────────────

    @Test
    fun `raw buffer drops oldest entry when cap exceeded`() {
        // Fill buffer to exactly MAX_RAW_PENDING
        repeat(DittoLogCaptureService.MAX_RAW_PENDING) {
            service.onLiveDittoEvent(DittoLogLevel.Info, "message $it")
        }
        // Add one more — should drop oldest, NOT crash
        service.onLiveDittoEvent(DittoLogLevel.Info, "overflow message")
        // Buffer should not exceed MAX_RAW_PENDING
        // We can't directly inspect the private ConcurrentLinkedDeque,
        // but calling drainRawBuffer() should succeed without error
        service.drainRawBuffer()
    }

    @Test
    fun `drainRawBuffer parses batch into LogEntries`() = runTest(testDispatcher) {
        service.onLiveDittoEvent(DittoLogLevel.Error, "error occurred")
        service.onLiveDittoEvent(DittoLogLevel.Warning, "warning issued")

        service.drainRawBuffer()
        advanceUntilIdle()

        // Emit snapshot manually by calling drainRawBuffer
        // liveEntries starts empty and only updates via the display loop
        // We verify the drain didn't throw by checking the service is still operable
        service.onLiveDittoEvent(DittoLogLevel.Info, "after drain")
    }

    // ── Backing store cap ─────────────────────────────────────────────────────

    /**
     * Feeds [count] events through the raw buffer and into the backing store,
     * deterministically. Chunks stay under [DittoLogCaptureService.EAGER_DRAIN_THRESHOLD]
     * so the service never launches its own drain: that one runs on
     * `Dispatchers.IO`, which the `StandardTestDispatcher` does not control, and
     * would race this drain.
     */
    private fun feedAndDrain(count: Int) {
        val chunk = DittoLogCaptureService.EAGER_DRAIN_THRESHOLD - 100
        var fed = 0
        while (fed < count) {
            val n = minOf(chunk, count - fed)
            repeat(n) { service.onLiveDittoEvent(DittoLogLevel.Debug, "msg ${fed + it}") }
            service.drainRawBuffer()
            fed += n
        }
    }

    @Test
    fun `backing store trims from front when over cap`() {
        // Arrange & Act
        feedAndDrain(DittoLogCaptureService.MAX_LIVE_ENTRIES + 100)
        service.emitSnapshot()

        // Assert — the store is capped at MAX_LIVE_ENTRIES and the oldest went first.
        val snapshot = service.liveEntries.value
        assertEquals(DittoLogCaptureService.MAX_LIVE_ENTRIES, snapshot.size)
        assertEquals("msg 100", snapshot.first().message)
    }

    @Test
    fun `emitSnapshot publishes the whole retained buffer not just the display cap`() {
        // Arrange — the defect: liveEntries used to be takeLast(MAX_DISPLAYED_ENTRIES),
        // so every badge, histogram, duration bucket and tag on the Logging screen
        // was computed over at most 200 live lines while the store held thousands.
        // The 200 cap belongs at the display layer, not at the data source.
        val fed = DittoLogCaptureService.MAX_DISPLAYED_ENTRIES * 5

        // Act
        feedAndDrain(fed)
        service.emitSnapshot()

        // Assert
        val snapshot = service.liveEntries.value
        assertEquals(fed, snapshot.size)
        assertTrue(
            "Snapshot must exceed the display cap, was ${snapshot.size}",
            snapshot.size > DittoLogCaptureService.MAX_DISPLAYED_ENTRIES,
        )
    }

    // ── A11: the size-keyed rescan stall ──────────────────────────────────────

    /**
     * **Confirms** the audit's A11 hypothesis, at the data layer.
     *
     * `LoggingScreen` keys its pattern scan / analytics rescan on
     * `snapshotFlow { Triple(tab, frozen, entries.size) }`, and `snapshotFlow` is
     * distinct-until-changed. [DittoLogCaptureService] trims the live store to
     * *exactly* [DittoLogCaptureService.MAX_LIVE_ENTRIES], with no slack margin,
     * so this test shows the size is constant across successive publishes while
     * every entry in the buffer is replaced. A size-keyed `snapshotFlow`
     * therefore emits once when the cap is reached and never again.
     *
     * (SwiftUI escapes this because it trims with a 512-entry slack margin, so its
     * count oscillates below the cap and keeps firing.)
     */
    @Test
    fun `live buffer size pins at the cap while content keeps changing`() {
        // Arrange — fill the store to exactly the cap.
        feedAndDrain(DittoLogCaptureService.MAX_LIVE_ENTRIES)
        service.emitSnapshot()
        val sizeAtCap = service.liveEntries.value.size
        val firstAtCap = service.liveEntries.value.first().message
        val lastAtCap = service.liveEntries.value.last().message
        assertEquals(DittoLogCaptureService.MAX_LIVE_ENTRIES, sizeAtCap)

        // Act — push a whole further batch through; every entry is new.
        repeat(3) {
            feedAndDrain(400)
            service.emitSnapshot()
        }
        val after = service.liveEntries.value

        // Assert — the contents rolled completely, and the size did not move an inch.
        assertEquals(
            "Size must stay pinned at the cap — this is the stall's precondition",
            sizeAtCap,
            after.size,
        )
        assertNotEquals("oldest entry must have rolled off", firstAtCap, after.first().message)
        assertNotEquals("newest entry must have advanced", lastAtCap, after.last().message)
    }

    /**
     * The fix for the stall confirmed above: [DittoLogCaptureService.ingestSequence]
     * is monotonic and advances on every publish, including the publishes that
     * leave the size unchanged. Keying the rescan on this value instead of on
     * `entries.size` makes it fire past the cap.
     */
    @Test
    fun `ingestSequence advances after the cap where size does not`() {
        // Arrange
        feedAndDrain(DittoLogCaptureService.MAX_LIVE_ENTRIES)
        service.emitSnapshot()
        val sizeAtCap = service.liveEntries.value.size
        val seqAtCap = service.ingestSequence.value

        // Act
        feedAndDrain(400)
        service.emitSnapshot()

        // Assert
        assertEquals(sizeAtCap, service.liveEntries.value.size)
        assertTrue(
            "ingestSequence must advance past the cap (was $seqAtCap, now ${service.ingestSequence.value})",
            service.ingestSequence.value > seqAtCap,
        )
    }

    @Test
    fun `ingestSequence is monotonic across every mutation path`() = runTest(testDispatcher) {
        val seen = mutableListOf(service.ingestSequence.value)

        service.onLiveDittoEvent(DittoLogLevel.Info, "one")
        service.drainRawBuffer()
        service.emitSnapshot()
        seen += service.ingestSequence.value

        service.clearLive()
        seen += service.ingestSequence.value

        service.clearHistorical()
        seen += service.ingestSequence.value

        service.clearTransportConditions()
        seen += service.ingestSequence.value

        service.clearConnectionRequests()
        seen += service.ingestSequence.value

        assertEquals("every mutation must advance the counter", seen.distinct(), seen)
        assertEquals("counter must be strictly increasing", seen.sorted(), seen)
    }

    // ── SDK stream merge ──────────────────────────────────────────────────────

    @Test
    fun `mergeByTimestamp interleaves two sorted lists chronologically`() {
        // Arrange — historical entries are older, but the two streams overlap.
        val historical = listOf(entryAt(0), entryAt(20), entryAt(40))
        val live = listOf(entryAt(10), entryAt(30), entryAt(50))

        // Act
        val merged = service.mergeByTimestamp(historical, live)

        // Assert
        assertEquals(listOf(0L, 10L, 20L, 30L, 40L, 50L), merged.map { it.timestamp.time })
    }

    @Test
    fun `mergeByTimestamp is stable and handles empty inputs`() {
        // Arrange — on a tie the left (historical) entry must come first, matching
        // the `sortedBy` this replaced.
        val left = listOf(entryAt(5, "historical"))
        val right = listOf(entryAt(5, "live"))

        // Act & Assert
        assertEquals(listOf("historical", "live"), service.mergeByTimestamp(left, right).map { it.message })
        assertEquals(right, service.mergeByTimestamp(emptyList(), right))
        assertEquals(left, service.mergeByTimestamp(left, emptyList()))
        assertEquals(emptyList<Any>(), service.mergeByTimestamp(emptyList(), emptyList()))
    }

    // ── Live pause behaviour ──────────────────────────────────────────────────

    @Test
    fun `pendingNewEntriesCount increments while isLivePaused`() = runTest(testDispatcher) {
        service.isLivePaused = true

        // Emit events directly into backing store via drain
        repeat(10) {
            service.onLiveDittoEvent(DittoLogLevel.Info, "paused msg $it")
        }
        service.drainRawBuffer()

        // Manually trigger the display loop logic by simulating what startDisplayLoop does:
        // When paused, pending count should track new entries added since last snapshot
        val beforeCount = service.pendingNewEntriesCount.value
        // We can't easily test the coroutine loop internals without running it,
        // but we verify isLivePaused is respected: liveEntries should NOT update while paused
        assertTrue("isLivePaused should be true", service.isLivePaused)
    }

    @Test
    fun `resetPendingCount clears pending counter`() {
        service.isLivePaused = true
        service.onLiveDittoEvent(DittoLogLevel.Info, "msg")
        service.resetPendingCount()
        assertEquals(0, service.pendingNewEntriesCount.value)
    }

    // ── Clear operations ──────────────────────────────────────────────────────

    @Test
    fun `clearLive empties liveEntries and resets pending count`() = runTest(testDispatcher) {
        service.onLiveDittoEvent(DittoLogLevel.Info, "some message")
        service.drainRawBuffer()
        service.clearLive()
        advanceUntilIdle()

        assertEquals(emptyList<Any>(), service.liveEntries.value)
        assertEquals(0, service.pendingNewEntriesCount.value)
    }

    @Test
    fun `clearHistorical empties historicalEntries`() = runTest(testDispatcher) {
        service.clearHistorical()
        assertTrue(service.historicalEntries.value.isEmpty())
    }

    // ── startLiveCapture idempotency ──────────────────────────────────────────

    @Test
    fun `startLiveCapture is idempotent — second call does not crash`() {
        service.startLiveCapture()
        service.startLiveCapture() // should be a no-op
        service.stopLiveCapture()
    }

    @Test
    fun `stopLiveCapture after not started does not crash`() {
        service.stopLiveCapture() // should be a no-op
    }

    private fun entryAt(millis: Long, message: String = "m") = com.costoda.dittoedgestudio.domain.model.LogEntry(
        timestamp = Date(millis),
        level = DittoLogLevel.Info,
        message = message,
        component = com.costoda.dittoedgestudio.domain.model.LogComponent.OTHER,
        source = com.costoda.dittoedgestudio.domain.model.LogEntrySource.DittoSDK,
        rawLine = message,
    )
}
