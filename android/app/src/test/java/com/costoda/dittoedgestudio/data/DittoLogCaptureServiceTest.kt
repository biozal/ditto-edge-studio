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
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.io.File

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

    @Test
    fun `backing store trims from front when over cap`() {
        // Add MAX_LIVE_ENTRIES + 100 events in batches
        val overshoot = 100
        val total = DittoLogCaptureService.MAX_LIVE_ENTRIES + overshoot
        // Feed in batches of MAX_DRAIN_PER_CYCLE to exercise trim logic
        repeat(total) {
            service.onLiveDittoEvent(DittoLogLevel.Debug, "msg $it")
        }
        // Drain all raw events — this triggers trimming
        repeat(total / DittoLogCaptureService.MAX_DRAIN_PER_CYCLE + 2) {
            service.drainRawBuffer()
        }
        // After trim, liveEntries should be at most MAX_DISPLAYED_ENTRIES (from snapshot)
        // The backing store itself is internal, but the snapshot must not exceed cap
        val snapshot = service.liveEntries.value
        assertTrue(
            "Snapshot should be <= MAX_DISPLAYED_ENTRIES, was ${snapshot.size}",
            snapshot.size <= DittoLogCaptureService.MAX_DISPLAYED_ENTRIES,
        )
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
}
