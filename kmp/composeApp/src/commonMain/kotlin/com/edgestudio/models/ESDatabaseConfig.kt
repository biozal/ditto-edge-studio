package com.edgestudio.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class ESDatabaseConfig (
    @SerialName("_id") val id: String,
    @SerialName("name") val name: String,
    @SerialName("databaseId") val databaseId: String,
    @SerialName("authToken") val authToken: String,
    @SerialName("authURL") val authUrl: String,
    @SerialName("httpApiUrl") val httpApiUrl: String,
    @SerialName("httpApiKey") val httpApiKey: String,
    @SerialName("mode") val mode: String,
    @SerialName("allowUntrustedCerts") val allowUntrustedCerts: Boolean
)