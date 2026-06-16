package com.costoda.dittoedgestudio.data.repository

import com.costoda.dittoedgestudio.domain.model.ConnectionsByTransport
import com.costoda.dittoedgestudio.domain.model.LocalPeerInfo
import com.costoda.dittoedgestudio.domain.model.MeshTopology
import com.costoda.dittoedgestudio.domain.model.SyncStatusInfo
import com.ditto.kotlin.Ditto
import kotlinx.coroutines.flow.StateFlow

interface SystemRepository {
    val peers: StateFlow<List<SyncStatusInfo>>
    val localPeer: StateFlow<LocalPeerInfo?>
    val connectionsByTransport: StateFlow<ConnectionsByTransport>

    /**
     * Unfiltered presence-graph snapshot — the full mesh (all peers + all edges with
     * endpoint identities). Surfaces only what the Presence Viewer needs when the
     * user toggles "Direct Connected" off; the rest of the UI should continue to use
     * [peers] which is direct-only per the project-wide presence-graph pitfall rule.
     */
    val meshTopology: StateFlow<MeshTopology>

    fun startObserving(ditto: Ditto)
    fun stopObserving()
}
