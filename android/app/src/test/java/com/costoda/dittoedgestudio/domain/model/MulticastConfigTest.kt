package com.costoda.dittoedgestudio.domain.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Validation rules for the multicast (beta) transport config.
 *
 * Ported from the Zava Retail demo's `MulticastConfigTests`, where these rules
 * were verified on-device against Ditto SDK 5.1.0. The port-0 rejection is
 * load-bearing: the SDK treats 0 as "pick any port", which silently breaks group
 * rendezvous between peers.
 */
class MulticastConfigTest {

    @Test
    fun `defaults match the SDK defaults`() {
        val config = MulticastConfig()
        assertFalse(config.enabled)
        assertEquals("224.1.2.3", config.groupAddress)
        assertEquals(6003, config.port)
        assertNull(config.interfaceName)
    }

    @Test
    fun `valid class-D group addresses are accepted`() {
        assertTrue(MulticastConfig.isValidGroupAddress("224.0.0.1"))
        assertTrue(MulticastConfig.isValidGroupAddress("224.1.2.3"))
        assertTrue(MulticastConfig.isValidGroupAddress("239.255.255.255"))
    }

    @Test
    fun `addresses outside the class-D range are rejected`() {
        assertFalse(MulticastConfig.isValidGroupAddress("223.255.255.255"))
        assertFalse(MulticastConfig.isValidGroupAddress("240.0.0.1"))
        assertFalse(MulticastConfig.isValidGroupAddress("192.168.1.1"))
    }

    @Test
    fun `malformed group addresses are rejected`() {
        assertFalse(MulticastConfig.isValidGroupAddress(""))
        assertFalse(MulticastConfig.isValidGroupAddress("1.2.3"))
        assertFalse(MulticastConfig.isValidGroupAddress("1.2.3.4.5"))
        assertFalse(MulticastConfig.isValidGroupAddress("a.b.c.d"))
        assertFalse(MulticastConfig.isValidGroupAddress("256.1.1.1"))
        assertFalse(MulticastConfig.isValidGroupAddress("224.-1.2.3"))
    }

    @Test
    fun `group address validation trims surrounding whitespace`() {
        assertTrue(MulticastConfig.isValidGroupAddress("  224.1.2.3  "))
    }

    @Test
    fun `valid ports parse`() {
        assertEquals(6003, MulticastConfig.parsePort("6003"))
        assertEquals(1, MulticastConfig.parsePort("1"))
        assertEquals(65535, MulticastConfig.parsePort("65535"))
        assertEquals(6003, MulticastConfig.parsePort(" 6003 "))
    }

    @Test
    fun `port 0 is rejected — SDK reads it as any port and rendezvous breaks`() {
        assertNull(MulticastConfig.parsePort("0"))
    }

    @Test
    fun `out-of-range and non-numeric ports are rejected`() {
        assertNull(MulticastConfig.parsePort("65536"))
        assertNull(MulticastConfig.parsePort("-1"))
        assertNull(MulticastConfig.parsePort("abc"))
        assertNull(MulticastConfig.parsePort(""))
        assertNull(MulticastConfig.parsePort("6003.5"))
    }
}
