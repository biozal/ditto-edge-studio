package com.ditto.edgestudio.kmp.dittoedgestudio

interface Platform {
    val name: String
}

expect fun getPlatform(): Platform