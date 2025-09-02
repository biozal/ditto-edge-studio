package com.edgestudio

interface Platform {
    val name: String
}

expect fun getPlatform(): Platform

expect fun getAppDataDirectory(): String