package com.costoda.dittoedgestudio.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable

private val LightColorScheme = lightColorScheme(
    background = PapyrusWhite,
    surface = TrafficWhite,
    primary = SulfurYellow,
    onPrimary = TrafficBlack,
    secondary = PearlLightGrey,
    onBackground = JetBlack,
    onSurface = JetBlack,
)

private val DarkColorScheme = darkColorScheme(
    background = JetBlack,
    surface = TrafficBlack,
    primary = SulfurYellow,
    onPrimary = JetBlack,
    secondary = PearlLightGrey,
    onBackground = TrafficWhite,
    onSurface = TrafficWhite,
)

@Composable
fun EdgeStudioTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit,
) {
    val colorScheme = if (darkTheme) DarkColorScheme else LightColorScheme

    MaterialTheme(
        colorScheme = colorScheme,
        typography = Typography,
        content = content,
    )
}
