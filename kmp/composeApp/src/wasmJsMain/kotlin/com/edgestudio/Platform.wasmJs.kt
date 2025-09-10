package com.edgestudio

class WasmPlatform : Platform {
    override val name: String = "Web with Kotlin/Wasm"
}

actual fun getPlatform(): Platform = WasmPlatform()

actual fun getAppDataDirectory(): String {
    throw IllegalStateException("Cannot access application support directory")
}