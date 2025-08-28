package com.ditto.edgestudio.kmp.dittoedgestudio

class JVMPlatform : Platform {
    override val name: String = "Ditto Edge Studio"
}

actual fun getPlatform(): Platform = JVMPlatform()