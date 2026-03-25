package com.costoda.dittoedgestudio.domain.model

data class LocalPeerInfo(
    val peerId: String,
    val deviceName: String,
    val sdkLanguage: String,
    val sdkPlatform: String,
    val sdkVersion: String,
)
