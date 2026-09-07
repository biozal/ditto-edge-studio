package com.costoda.dittoedgestudio.ui.mainstudio

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.costoda.dittoedgestudio.ui.mainstudio.metrics.AppMetricsScreen
import com.costoda.dittoedgestudio.ui.mainstudio.metrics.DiskUsageScreen
import com.costoda.dittoedgestudio.ui.mainstudio.metrics.SystemMetricsScreen
import com.costoda.dittoedgestudio.viewmodel.AppMetricsViewModel
import com.costoda.dittoedgestudio.viewmodel.DiskUsageViewModel
import com.costoda.dittoedgestudio.viewmodel.MainStudioViewModel
import org.koin.androidx.compose.koinViewModel

/**
 * Scene-driven section composables for the four single-pane rail sections:
 * Log Analyzer, App Metrics, Database Metrics, and System Metrics.
 *
 * Each composable is the `content` lambda passed to [StudioSectionContainer] in
 * [com.costoda.dittoedgestudio.ui.navigation.AppNavGraph]. They resolve their
 * dependencies exactly as the legacy MainStudioScreen content-placeholder `when`
 * branches did — no internals of the leaf screens are changed.
 */

/**
 * Log Analyzer section content.
 *
 * [viewModel.loggingCaptureService] is the session-scoped [com.costoda.dittoedgestudio.data.logging.DittoLogCaptureService],
 * forwarded directly to [LoggingScreen] — the same resolution used in the legacy monolith.
 *
 * The session's current database config is forwarded too, so the Logs toolbar's
 * SDK log level can be read from and written back to it (SwiftUI persists the
 * same choice via `DittoManager.changeDittoLogLevel`).
 */
@Composable
fun LoggingSection(
    viewModel: MainStudioViewModel,
    modifier: Modifier = Modifier,
) {
    LoggingScreen(
        captureService = viewModel.loggingCaptureService,
        modifier = modifier.fillMaxSize(),
        activeDatabase = viewModel.session.currentDatabase(),
    )
}

/**
 * App Metrics section content.
 *
 * [AppMetricsViewModel] is resolved via [koinViewModel] with no parameters — identical to
 * `koinViewModel()` in the legacy content-placeholder branch.
 */
@Composable
fun AppMetricsSection(
    modifier: Modifier = Modifier,
) {
    val appMetricsViewModel: AppMetricsViewModel = koinViewModel()
    AppMetricsScreen(
        viewModel = appMetricsViewModel,
        modifier = modifier.fillMaxSize(),
    )
}

/**
 * Database Metrics section content (canonical name for the Disk Usage rail item).
 *
 * [DiskUsageViewModel] is resolved via [koinViewModel] with no parameters — identical to
 * `koinViewModel()` in the legacy content-placeholder branch.
 */
@Composable
fun DiskUsageSection(
    modifier: Modifier = Modifier,
    // Session-scoped studio VM feeds the system:metrics dashboard (SDK 5.1).
    mainViewModel: com.costoda.dittoedgestudio.viewmodel.MainStudioViewModel? = null,
) {
    val diskUsageViewModel: DiskUsageViewModel = koinViewModel()
    DiskUsageScreen(
        viewModel = diskUsageViewModel,
        modifier = modifier.fillMaxSize(),
        mainViewModel = mainViewModel,
    )
}

/**
 * System Metrics section content (SDK 5.1 `system:metrics`).
 *
 * Everything it shows — the polled snapshot and the pinned series — is session
 * scoped, so the whole screen is driven by the studio VM; there is no separate
 * ViewModel to resolve.
 */
@Composable
fun SystemMetricsSection(
    mainViewModel: MainStudioViewModel,
    modifier: Modifier = Modifier,
) {
    SystemMetricsScreen(
        viewModel = mainViewModel,
        modifier = modifier.fillMaxSize(),
    )
}
