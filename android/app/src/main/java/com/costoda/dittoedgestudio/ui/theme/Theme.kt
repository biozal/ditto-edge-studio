package com.costoda.dittoedgestudio.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.ExperimentalMaterial3ExpressiveApi
import androidx.compose.material3.MaterialExpressiveTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable

private val LightColorScheme = lightColorScheme(
    primary = SulfurYellow,
    onPrimary = TrafficBlack,
    primaryContainer = SulfurYellowPale,
    onPrimaryContainer = OliveDeep,
    inversePrimary = SulfurYellowDeep,
    secondary = PearlLightGrey,
    onSecondary = JetBlack,
    secondaryContainer = LightSurfaceContainerHighest,
    onSecondaryContainer = TrafficBlack,
    tertiary = InkGrey,
    onTertiary = TrafficWhite,
    tertiaryContainer = LightSurfaceContainerHigh,
    onTertiaryContainer = TrafficBlack,
    background = PapyrusWhite,
    onBackground = JetBlack,
    surface = TrafficWhite,
    onSurface = JetBlack,
    surfaceVariant = LightSurfaceVariant,
    onSurfaceVariant = InkGrey,
    surfaceDim = PapyrusWhite,
    surfaceBright = LightSurfaceContainerLowest,
    surfaceContainerLowest = LightSurfaceContainerLowest,
    surfaceContainerLow = LightSurfaceContainerLow,
    surfaceContainer = LightSurfaceContainer,
    surfaceContainerHigh = LightSurfaceContainerHigh,
    surfaceContainerHighest = LightSurfaceContainerHighest,
    outline = PearlLightGrey,
    outlineVariant = LightOutlineVariant,
    inverseSurface = TrafficBlack,
    inverseOnSurface = TrafficWhite,
)

private val DarkColorScheme = darkColorScheme(
    primary = SulfurYellow,
    onPrimary = JetBlack,
    primaryContainer = SulfurYellowDeep,
    onPrimaryContainer = SulfurYellowPale,
    inversePrimary = SulfurYellowDeep,
    secondary = PearlLightGrey,
    onSecondary = JetBlack,
    secondaryContainer = DarkSurfaceContainerHighest,
    onSecondaryContainer = TrafficWhite,
    tertiary = MistGrey,
    onTertiary = JetBlack,
    tertiaryContainer = DarkSurfaceContainerHigh,
    onTertiaryContainer = TrafficWhite,
    background = JetBlack,
    onBackground = TrafficWhite,
    surface = TrafficBlack,
    onSurface = TrafficWhite,
    surfaceVariant = DarkSurfaceVariant,
    onSurfaceVariant = MistGrey,
    surfaceDim = DarkSurfaceContainerLowest,
    surfaceBright = DarkSurfaceContainerHighest,
    surfaceContainerLowest = DarkSurfaceContainerLowest,
    surfaceContainerLow = DarkSurfaceContainerLow,
    surfaceContainer = DarkSurfaceContainer,
    surfaceContainerHigh = DarkSurfaceContainerHigh,
    surfaceContainerHighest = DarkSurfaceContainerHighest,
    outline = DarkOutline,
    outlineVariant = DarkOutlineVariant,
    inverseSurface = TrafficWhite,
    inverseOnSurface = JetBlack,
)

@OptIn(ExperimentalMaterial3ExpressiveApi::class)
@Composable
fun EdgeStudioTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit,
) {
    // motionScheme and shapes are omitted so MaterialExpressiveTheme
    // supplies the expressive baseline defaults
    MaterialExpressiveTheme(
        colorScheme = if (darkTheme) DarkColorScheme else LightColorScheme,
        typography = Typography,
        content = content,
    )
}
