package com.edgestudio.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.ColorScheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

// Ditto brand colors
private val DittoPrimary = Color(0xFF6366F1) // Indigo
private val DittoSecondary = Color(0xFF8B5CF6) // Purple
private val DittoTertiary = Color(0xFF06B6D4) // Cyan

// Light theme colors
private val LightColorScheme = lightColorScheme(
    primary = DittoPrimary,
    onPrimary = Color.White,
    primaryContainer = Color(0xFFEEF2FF),
    onPrimaryContainer = Color(0xFF1E1B4B),
    
    secondary = DittoSecondary,
    onSecondary = Color.White,
    secondaryContainer = Color(0xFFF3F4F6),
    onSecondaryContainer = Color(0xFF581C87),
    
    tertiary = DittoTertiary,
    onTertiary = Color.White,
    tertiaryContainer = Color(0xFFE0F7FA),
    onTertiaryContainer = Color(0xFF0E4A5C),
    
    background = Color(0xFFFEFEFE),
    onBackground = Color(0xFF1A1A1A),
    surface = Color.White,
    onSurface = Color(0xFF1A1A1A),
    surfaceVariant = Color(0xFFF5F5F5),
    onSurfaceVariant = Color(0xFF4A4A4A),
    
    error = Color(0xFFDC2626),
    onError = Color.White,
    errorContainer = Color(0xFFFEF2F2),
    onErrorContainer = Color(0xFF7F1D1D),
    
    outline = Color(0xFFD1D5DB),
    outlineVariant = Color(0xFFE5E7EB)
)

// Dark theme colors  
private val DarkColorScheme = darkColorScheme(
    primary = Color(0xFF818CF8), // Lighter indigo for dark mode
    onPrimary = Color(0xFF1E1B4B),
    primaryContainer = Color(0xFF3730A3),
    onPrimaryContainer = Color(0xFFEEF2FF),
    
    secondary = Color(0xFFA78BFA), // Lighter purple for dark mode
    onSecondary = Color(0xFF581C87),
    secondaryContainer = Color(0xFF7C3AED),
    onSecondaryContainer = Color(0xFFF3F4F6),
    
    tertiary = Color(0xFF67E8F9), // Lighter cyan for dark mode
    onTertiary = Color(0xFF0E4A5C),
    tertiaryContainer = Color(0xFF0891B2),
    onTertiaryContainer = Color(0xFFE0F7FA),
    
    background = Color(0xFF0F0F0F),
    onBackground = Color(0xFFE5E5E5),
    surface = Color(0xFF1A1A1A),
    onSurface = Color(0xFFE5E5E5),
    surfaceVariant = Color(0xFF2A2A2A),
    onSurfaceVariant = Color(0xFFB3B3B3),
    
    error = Color(0xFFF87171),
    onError = Color(0xFF7F1D1D),
    errorContainer = Color(0xFF991B1B),
    onErrorContainer = Color(0xFFFEF2F2),
    
    outline = Color(0xFF6B7280),
    outlineVariant = Color(0xFF4B5563)
)

@Composable
fun DittoEdgeStudioTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit
) {
    val colorScheme = if (darkTheme) {
        DarkColorScheme
    } else {
        LightColorScheme
    }

    MaterialTheme(
        colorScheme = colorScheme,
        typography = DittoTypography,
        content = content
    )
}