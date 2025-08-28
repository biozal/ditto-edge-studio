package com.ditto.edgestudio.kmp.dittoedgestudio.ui.theme

import androidx.compose.runtime.*

enum class ThemeMode {
    LIGHT,
    DARK,
    SYSTEM
}

class ThemeManager {
    private var _themeMode by mutableStateOf(ThemeMode.SYSTEM)
    
    val themeMode: ThemeMode
        get() = _themeMode
    
    fun setThemeMode(mode: ThemeMode) {
        _themeMode = mode
    }
    
    fun toggleTheme() {
        _themeMode = when (_themeMode) {
            ThemeMode.LIGHT -> ThemeMode.DARK
            ThemeMode.DARK -> ThemeMode.LIGHT
            ThemeMode.SYSTEM -> ThemeMode.DARK // If system, go to dark first
        }
    }
    
    @Composable
    fun isDarkTheme(systemInDarkTheme: Boolean = androidx.compose.foundation.isSystemInDarkTheme()): Boolean {
        return when (_themeMode) {
            ThemeMode.LIGHT -> false
            ThemeMode.DARK -> true
            ThemeMode.SYSTEM -> systemInDarkTheme
        }
    }
}

// Global theme manager instance
val LocalThemeManager = compositionLocalOf { ThemeManager() }