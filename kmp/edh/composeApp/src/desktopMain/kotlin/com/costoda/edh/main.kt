package com.costoda.edh

import androidx.compose.ui.window.Window
import androidx.compose.ui.window.application

fun main() = application {
    Window(
        onCloseRequest = ::exitApplication,
        title = "Edge Debug Helper",
    ) {
        App()
    }
}