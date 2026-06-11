package com.costoda.dittoedgestudio.ui.adaptive

import androidx.compose.material3.adaptive.currentWindowAdaptiveInfoV2
import androidx.compose.runtime.Composable
import androidx.window.core.layout.WindowSizeClass
import androidx.window.core.layout.WindowSizeClass.Companion.WIDTH_DP_EXPANDED_LOWER_BOUND
import androidx.window.core.layout.WindowSizeClass.Companion.WIDTH_DP_LARGE_LOWER_BOUND
import androidx.window.core.layout.WindowSizeClass.Companion.WIDTH_DP_MEDIUM_LOWER_BOUND

/**
 * Single source of truth for window size class decisions.
 *
 * Uses [currentWindowAdaptiveInfoV2] (material3-adaptive 1.3.0-beta02), which is the
 * non-deprecated replacement for `currentWindowAdaptiveInfo(supportLargeAndXLargeWidth = true)`.
 * The boolean-param overload carries a `@Deprecated(WARNING)` annotation in beta02 with
 * replaceWith pointing to V2. V2 always opts in Large/XL breakpoints via BREAKPOINTS_V2.
 *
 * Never read `Configuration.screenWidthDp` elsewhere in the codebase.
 */
@Composable
fun studioWindowSizeClass(): WindowSizeClass =
    currentWindowAdaptiveInfoV2().windowSizeClass

/** Medium and up: NavigationRail visible (below: modal Nav Drawer). */
val WindowSizeClass.showsRail: Boolean
    get() = isWidthAtLeastBreakpoint(WIDTH_DP_MEDIUM_LOWER_BOUND)

/** Expanded and up: Data Panel defaults to visible. */
val WindowSizeClass.dataPanelDefaultVisible: Boolean
    get() = isWidthAtLeastBreakpoint(WIDTH_DP_EXPANDED_LOWER_BOUND)

/** Large and up (external monitor / desktop window): Inspector defaults to visible. */
val WindowSizeClass.inspectorDefaultVisible: Boolean
    get() = isWidthAtLeastBreakpoint(WIDTH_DP_LARGE_LOWER_BOUND)
