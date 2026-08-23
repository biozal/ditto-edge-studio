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
 * Expanded and up (≥840dp): the studio renders its full multi-pane CHROME —
 * `NavigationRail | listPane | detailPane | Inspector`.
 *
 * Below this breakpoint (Compact AND Medium — phones, floating windows, narrow split-screen)
 * the studio switches to **drawer mode** chrome:
 *  - No rail column. A hamburger button on the top bar opens a [ModalNavigationDrawer]
 *    with the rail items (section nav).
 *  - At Compact (<600dp) the drawer ALSO hosts the current section's Data Panel content
 *    (Subscriptions / Collections / Observers list) because the body is single-pane.
 *    At Medium (600–839dp) the body already shows list + detail side-by-side
 *    ([showsListDetail]), so the drawer carries section nav only.
 *
 * Keep [showsRail] for non-studio screens (e.g. DatabaseListScreen) that retain the 600dp
 * rail/no-rail behavior.
 */
val WindowSizeClass.studioMultiPane: Boolean
    get() = isWidthAtLeastBreakpoint(WIDTH_DP_EXPANDED_LOWER_BOUND)

/**
 * Medium and up (≥600dp — e.g. an open flip phone at ~690dp, tablets, split-screen
 * windows): section entries render their LIST pane and the `ListDetailSceneStrategy`
 * is allowed two horizontal partitions, so list + detail sit side-by-side (the iPad
 * `NavigationSplitView` two-column behavior).
 *
 * Below this breakpoint (Compact — phones, cover screens, narrow split-screen) each
 * section shows a single pane: list-first with drill-in detail (an Up arrow appears in
 * the top bar for pushed detail screens).
 *
 * This is deliberately separate from [studioMultiPane] (≥840dp), which only forks the
 * studio CHROME (NavigationRail vs modal drawer). A Medium window gets drawer chrome
 * with a two-pane list-detail body.
 */
val WindowSizeClass.showsListDetail: Boolean
    get() = isWidthAtLeastBreakpoint(WIDTH_DP_MEDIUM_LOWER_BOUND)

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
