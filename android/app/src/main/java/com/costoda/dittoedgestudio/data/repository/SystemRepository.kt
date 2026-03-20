package com.costoda.dittoedgestudio.data.repository

import com.costoda.dittoedgestudio.domain.model.ConnectionsByTransport
import com.costoda.dittoedgestudio.domain.model.LocalPeerInfo
import com.costoda.dittoedgestudio.domain.model.SyncStatusInfo
import com.ditto.kotlin.Ditto
import kotlinx.coroutines.flow.StateFlow

interface SystemRepository {
    val peers: StateFlow<List<SyncStatusInfo>>
    val localPeer: StateFlow<LocalPeerInfo?>
    val connectionsByTransport: StateFlow<ConnectionsByTransport>
    fun startObserving(ditto: Ditto)
    fun stopObserving()
}
