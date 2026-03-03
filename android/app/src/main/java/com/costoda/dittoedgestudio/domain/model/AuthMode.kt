package com.costoda.dittoedgestudio.domain.model

enum class AuthMode(val value: String, val displayName: String) {
    SERVER("server", "Server"),
    SMALL_PEERS_ONLY("smallpeersonly", "Small Peers Only");

    companion object {
        fun fromValue(value: String): AuthMode =
            entries.firstOrNull { it.value == value } ?: SERVER
    }
}
