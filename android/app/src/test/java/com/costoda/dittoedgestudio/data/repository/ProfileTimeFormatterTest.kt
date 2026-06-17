package com.costoda.dittoedgestudio.data.repository

import org.junit.Assert.assertEquals
import org.junit.Test

class ProfileTimeFormatterTest {
    @Test fun `ns under 1000 renders as integer ns`() {
        assertEquals("209 ns", ProfileTimeFormatter.format(209L))
        assertEquals("0 ns", ProfileTimeFormatter.format(0L))
        assertEquals("999 ns", ProfileTimeFormatter.format(999L))
    }
    @Test fun `microseconds tier formats with two decimals`() {
        assertEquals("1.00 µs", ProfileTimeFormatter.format(1_000L))
        assertEquals("55.56 µs", ProfileTimeFormatter.format(55_560L))
        assertEquals("999.99 µs", ProfileTimeFormatter.format(999_999L))
    }
    @Test fun `milliseconds tier formats with two decimals`() {
        assertEquals("1.00 ms", ProfileTimeFormatter.format(1_000_000L))
        assertEquals("1.29 ms", ProfileTimeFormatter.format(1_294_166L))
        assertEquals("432.43 ms", ProfileTimeFormatter.format(432_430_000L))
    }
}
