package com.edgestudio

import java.lang.System

class JVMPlatform : Platform {
    override val name: String = "Ditto Edge Studio"
}

actual fun getPlatform(): Platform = JVMPlatform()

actual fun getAppDataDirectory(): String {
    val os = System.getProperty("os.name").lowercase()
    val userHome = System.getProperty("user.home")

    return when {
        os.contains("win") -> {
            System.getenv("APPDATA") ?: "$userHome\\AppData\\Roaming"
        }
        os.contains("mac") -> {
            "$userHome/Library/Application Support"
        }
        os.contains("linux") -> {
            System.getenv("XDG_CONFIG_HOME") ?: "$userHome/.config"
        }
        else -> {
            throw UnsupportedOperationException("Unsupported operating system: $os")
        }
    }
}