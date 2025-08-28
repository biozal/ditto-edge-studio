package com.ditto.edgestudio.kmp.dittoedgestudio

import androidx.compose.ui.window.Window
import androidx.compose.ui.window.application

fun main() = application {
    Window(
        onCloseRequest = ::exitApplication,
        title = "Ditto Edge Studio",
    ) {
        App()
    }
}