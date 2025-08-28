package com.ditto.edgestudio.kmp.dittoedgestudio

import androidx.compose.ui.window.Window
import androidx.compose.ui.window.application

fun main() {
    // Set macOS application name (affects menu bar and About/Quit menu items)
    System.setProperty("apple.awt.application.name", "Ditto Edge Studio")
    
    application {
        Window(
            onCloseRequest = ::exitApplication,
            title = "Ditto Edge Studio",
        ) {
            App()
        }
    }
}