package com.costoda.dittoedgestudio.data.repository

import com.costoda.dittoedgestudio.domain.model.NetworkInterfaceInfo
import com.costoda.dittoedgestudio.domain.model.P2PTransportInfo

interface NetworkDiagnosticsRepository {
    suspend fun fetchInterfaces(): List<NetworkInterfaceInfo>
    suspend fun fetchP2PTransports(): List<P2PTransportInfo>
    fun hasLocationOrNearbyPermission(): Boolean
}
