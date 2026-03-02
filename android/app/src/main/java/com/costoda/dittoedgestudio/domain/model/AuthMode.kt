package com.costoda.dittoedgestudio.domain.model

enum class AuthMode(val value: String) {
    SERVER("server"),
    SMALL_PEERS_ONLY("smallpeersonly");

    companion object {
        fun fromValue(value: String): AuthMode =
            entries.firstOrNull { it.value == value } ?: SERVER
    }
}
