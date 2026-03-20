package com.costoda.dittoedgestudio.domain.model

data class ConnectionsByTransport(
    val bluetooth: Int = 0,
    val lan: Int = 0,
    val p2pWifi: Int = 0,
    val webSocket: Int = 0,
    val dittoServer: Int = 0,
) {
    val total: Int get() = bluetooth + lan + p2pWifi + webSocket + dittoServer

    companion object {
        val Empty = ConnectionsByTransport()
    }
}
