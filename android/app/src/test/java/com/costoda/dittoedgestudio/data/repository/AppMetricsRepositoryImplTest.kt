package com.costoda.dittoedgestudio.data.repository

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.LinkedList
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors

class AppMetricsRepositoryImplTest {

    private fun makeRepo() = AppMetricsRepositoryImpl()

    // -------------------------------------------------------------------------
    // Reflection helper — access private latencySamples field
    // -------------------------------------------------------------------------

    @Suppress("UNCHECKED_CAST")
    private fun getLatencySamples(repo: AppMetricsRepositoryImpl): LinkedList<Double> {
        val field = AppMetricsRepositoryImpl::class.java.getDeclaredField("latencySamples")
        field.isAccessible = true
        return field.get(repo) as LinkedList<Double>
    }

    // -------------------------------------------------------------------------
    // incrementQueryCount
    // -------------------------------------------------------------------------

    @Test
    fun `incrementQueryCount does not throw on single call`() {
        val repo = makeRepo()
        repo.incrementQueryCount()
    }

    @Test
    fun `incrementQueryCount does not throw on many calls`() {
        val repo = makeRepo()
        repeat(100) { repo.incrementQueryCount() }
    }

    // -------------------------------------------------------------------------
    // recordQueryLatency — basic behaviour
    // -------------------------------------------------------------------------

    @Test
    fun `recordQueryLatency zero does not throw`() {
        val repo = makeRepo()
        repo.recordQueryLatency(0.0)
    }

    @Test
    fun `recordQueryLatency positive value does not throw`() {
        val repo = makeRepo()
        repo.recordQueryLatency(42.5)
    }

    @Test
    fun `recordQueryLatency large value does not throw`() {
        val repo = makeRepo()
        repo.recordQueryLatency(Double.MAX_VALUE)
    }

    @Test
    fun `recordQueryLatency stores sample in buffer`() {
        val repo = makeRepo()
        repo.recordQueryLatency(10.0)

        val samples = getLatencySamples(repo)
        synchronized(samples) {
            assertEquals(1, samples.size)
            assertEquals(10.0, samples.first(), 0.0001)
        }
    }

    @Test
    fun `recordQueryLatency 5 samples are all stored`() {
        val repo = makeRepo()
        listOf(10.0, 20.0, 30.0, 40.0, 50.0).forEach { repo.recordQueryLatency(it) }

        val samples = getLatencySamples(repo)
        synchronized(samples) {
            assertEquals(5, samples.size)
        }
    }

    // -------------------------------------------------------------------------
    // Ring buffer: maxSamples = 120
    // -------------------------------------------------------------------------

    @Test
    fun `recordQueryLatency buffer size is capped at 120`() {
        val repo = makeRepo()
        repeat(120) { i -> repo.recordQueryLatency(i.toDouble()) }

        val samples = getLatencySamples(repo)
        synchronized(samples) {
            assertEquals(120, samples.size)
        }
    }

    @Test
    fun `recordQueryLatency 121st sample trims buffer to 120`() {
        val repo = makeRepo()
        repeat(121) { i -> repo.recordQueryLatency(i.toDouble()) }

        val samples = getLatencySamples(repo)
        synchronized(samples) {
            assertEquals(120, samples.size)
        }
    }

    @Test
    fun `recordQueryLatency ring buffer keeps newest samples`() {
        val repo = makeRepo()
        // Record 121 samples: 0.0 through 120.0
        repeat(121) { i -> repo.recordQueryLatency(i.toDouble()) }

        val samples = getLatencySamples(repo)
        synchronized(samples) {
            // First element (0.0) should have been evicted; newest 120 remain (1.0..120.0)
            assertEquals(120, samples.size)
            assertEquals(1.0, samples.first(), 0.0001)
            assertEquals(120.0, samples.last(), 0.0001)
        }
    }

    @Test
    fun `recordQueryLatency buffer stays at 120 after many excess samples`() {
        val repo = makeRepo()
        repeat(500) { i -> repo.recordQueryLatency(i.toDouble()) }

        val samples = getLatencySamples(repo)
        synchronized(samples) {
            assertEquals(120, samples.size)
        }
    }

    // -------------------------------------------------------------------------
    // Thread safety
    // -------------------------------------------------------------------------

    @Test
    fun `recordQueryLatency concurrent calls do not throw`() {
        val repo = makeRepo()
        val threads = 8
        val callsPerThread = 50
        val latch = CountDownLatch(threads)
        val executor = Executors.newFixedThreadPool(threads)

        repeat(threads) {
            executor.submit {
                repeat(callsPerThread) { i -> repo.recordQueryLatency(i.toDouble()) }
                latch.countDown()
            }
        }

        latch.await()
        executor.shutdown()

        val samples = getLatencySamples(repo)
        synchronized(samples) {
            assertTrue(samples.size <= 120)
        }
    }

    @Test
    fun `incrementQueryCount concurrent calls do not throw`() {
        val repo = makeRepo()
        val threads = 8
        val latch = CountDownLatch(threads)
        val executor = Executors.newFixedThreadPool(threads)

        repeat(threads) {
            executor.submit {
                repeat(100) { repo.incrementQueryCount() }
                latch.countDown()
            }
        }

        latch.await()
        executor.shutdown()
    }
}
