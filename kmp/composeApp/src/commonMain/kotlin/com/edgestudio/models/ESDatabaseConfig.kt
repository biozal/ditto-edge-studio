package com.edgestudio.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

import com.ditto.kotlin.serialization.DittoCborSerializable
import com.ditto.kotlin.serialization.DittoCborSerializable.Utf8String
import com.ditto.kotlin.serialization.DittoCborSerializable.BooleanValue

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

fun ESDatabaseConfig.toDittoDictionary() = DittoCborSerializable.Dictionary(mapOf(
    Utf8String("_id") to Utf8String(id),
    Utf8String("name") to Utf8String(name),
    Utf8String("databaseId") to Utf8String(databaseId),
    Utf8String("authToken") to Utf8String(authToken),
    Utf8String("authURL") to Utf8String(authUrl),
    Utf8String("httpApiUrl") to Utf8String(httpApiUrl),
    Utf8String("httpApiKey") to Utf8String(httpApiKey),
    Utf8String("mode") to Utf8String(mode),
    Utf8String("allowUntrustedCerts") to BooleanValue(allowUntrustedCerts),
))