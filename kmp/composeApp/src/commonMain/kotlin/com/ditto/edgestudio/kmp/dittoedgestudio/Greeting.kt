package com.ditto.edgestudio.kmp.dittoedgestudio

class Greeting {
    private val platform = getPlatform()

    fun greet(): String {
        return "Hello, ${platform.name}!"
    }
}