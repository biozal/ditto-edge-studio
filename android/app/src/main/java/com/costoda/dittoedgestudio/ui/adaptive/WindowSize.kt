package com.costoda.dittoedgestudio.ui.adaptive

import androidx.compose.material3.adaptive.currentWindowAdaptiveInfoV2
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.window.core.layout.WindowSizeClass
import androidx.window.core.layout.WindowSizeClass.Companion.WIDTH_DP_EXPANDED_LOWER_BOUND
import androidx.window.core.layout.WindowSizeClass.Companion.WIDTH_DP_EXTRA_LARGE_LOWER_BOUND
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

/** Medium and up: NavigationRail visible (below: modal Nav Drawer).
 *
 *  Used by [com.costoda.dittoedgestudio.ui.database.DatabaseListScreen] to switch between
 *  the tablet (multi-pane) database picker and the phone single-column layout. The studio
 *  no longer uses this property to decide between rail-mode and drawer-mode — see
 *  [studioMultiPane] for the studio-specific decision. */
val WindowSizeClass.showsRail: Boolean
    get() = isWidthAtLeastBreakpoint(WIDTH_DP_MEDIUM_LOWER_BOUND)

/**
 * Expanded and up (≥840dp): the studio renders its full multi-pane layout —
 * `NavigationRail | listPane | detailPane | Inspector`.
 *
 * Below this breakpoint (Compact AND Medium — phones, floating windows, narrow split-screen)
 * the studio switches to **drawer mode**:
 *  - No rail column. A hamburger button on the top bar opens a [ModalNavigationDrawer].
 *  - The drawer contains BOTH the rail items (section nav) AND the current section's Data
 *    Panel content (Subscriptions list / Collections list / Observers list / Executed
 *    queries list). Selecting anything in the drawer closes it.
 *  - The Content Pane is the DEFAULT view (peers tabs, query editor+results, observer
 *    events, EXPLAIN detail) — matches the original pre-migration phone UX and the iPad
 *    "MainView is always the default" semantics.
 *  - Sections without a Data Panel (Logging / AppMetrics / DiskUsage) show rail items only
 *    in the drawer.
 *
 * Keep [showsRail] for non-studio screens (e.g. DatabaseListScreen) that retain the 600dp
 * rail/no-rail behavior.
 */
val WindowSizeClass.studioMultiPane: Boolean
    get() = isWidthAtLeastBreakpoint(WIDTH_DP_EXPANDED_LOWER_BOUND)

/** Expanded and up: Data Panel defaults to visible. */
val WindowSizeClass.dataPanelDefaultVisible: Boolean
    get() = isWidthAtLeastBreakpoint(WIDTH_DP_EXPANDED_LOWER_BOUND)

/** Large and up (≥1200dp, external monitor / desktop window): Inspector defaults to visible. */
val WindowSizeClass.inspectorDefaultVisible: Boolean
    get() = isWidthAtLeastBreakpoint(WIDTH_DP_LARGE_LOWER_BOUND)

/**
 * Inspector column width, scaled to the window size class.
 *
 * Breakpoints (window-core 1.5.1 / BREAKPOINTS_V2):
 *  - Below Large (<1200dp): 300dp — standard side-sheet width
 *  - Large (1200–1599dp): 360dp — desktop window / external monitor
 *  - XL (≥1600dp): 400dp — wide external display, plenty of room
 *
 * Rationale: at Large+ widths the inspector is always visible by default
 * ([inspectorDefaultVisible]), so giving it more room improves readability
 * of help content, history, and query JSON without squeezing the detail pane.
 */
val WindowSizeClass.inspectorWidth: Dp
    get() = when {
        isWidthAtLeastBreakpoint(WIDTH_DP_EXTRA_LARGE_LOWER_BOUND) -> 400.dp
        isWidthAtLeastBreakpoint(WIDTH_DP_LARGE_LOWER_BOUND) -> 360.dp
        else -> 300.dp
    }
