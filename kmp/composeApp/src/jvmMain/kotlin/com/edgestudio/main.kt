package com.edgestudio

import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Window
import androidx.compose.ui.window.WindowPlacement
import androidx.compose.ui.window.WindowState
import androidx.compose.ui.window.application
import androidx.compose.ui.window.rememberWindowState

fun main() {
    // Set macOS application name and performance properties
    System.setProperty("apple.awt.application.name", "Ditto Edge Studio")
    
    // Performance optimizations for window rendering
    System.setProperty("skiko.renderApi", "METAL")
    System.setProperty("skiko.fps.enabled", "true")
    System.setProperty("skiko.vsync.enabled", "true")
    
    application {
        val windowState = rememberWindowState(
            width = 1200.dp,
            height = 800.dp,
            placement = WindowPlacement.Floating
        )
        
        Window(
            onCloseRequest = ::exitApplication,
            title = "Ditto Edge Studio",
            state = windowState,
            resizable = true,
        ) {
            App()
        }
    }
}