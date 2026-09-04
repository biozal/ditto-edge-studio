package com.costoda.dittoedgestudio.data.repository

import com.costoda.dittoedgestudio.domain.model.ConnectionsByTransport
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SystemRepositoryTest {

    private fun makeRepo() = SystemRepositoryImpl(
        CoroutineScope(SupervisorJob() + Dispatchers.Unconfined)
    )

    @Test
    fun `initial state has empty peers and null localPeer`() {
        val repo = makeRepo()

        assertTrue(repo.peers.value.isEmpty())
        assertNull(repo.localPeer.value)
        assertEquals(ConnectionsByTransport.Empty, repo.connectionsByTransport.value)
    }

    @Test
    fun `stopObserving resets all flows to empty`() {
        val repo = makeRepo()

        // stopObserving when nothing is observing should safely no-op
        repo.stopObserving()

        assertTrue(repo.peers.value.isEmpty())
        assertNull(repo.localPeer.value)
        assertEquals(ConnectionsByTransport.Empty, repo.connectionsByTransport.value)
    }
}
