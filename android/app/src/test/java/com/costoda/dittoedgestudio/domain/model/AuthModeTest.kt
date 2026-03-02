package com.costoda.dittoedgestudio.domain.model

import org.junit.Assert.assertEquals
import org.junit.Test

class AuthModeTest {

    @Test
    fun `fromValue returns SERVER for 'server'`() {
        assertEquals(AuthMode.SERVER, AuthMode.fromValue("server"))
    }

    @Test
    fun `fromValue returns SMALL_PEERS_ONLY for 'smallpeersonly'`() {
        assertEquals(AuthMode.SMALL_PEERS_ONLY, AuthMode.fromValue("smallpeersonly"))
    }

    @Test
    fun `fromValue returns SERVER as default for unknown value`() {
        assertEquals(AuthMode.SERVER, AuthMode.fromValue("unknown"))
    }

    @Test
    fun `value round-trip`() {
        AuthMode.entries.forEach { mode ->
            assertEquals(mode, AuthMode.fromValue(mode.value))
        }
    }
}
