package com.costoda.dittoedgestudio.domain.model

data class P2PTransportInfo(
    val kind: Kind,
    val isHardwareAvailable: Boolean,
    val isEnabled: Boolean,
    val statusDetail: String?,
) {
    enum class Kind { WifiAware, WifiDirect }
}
