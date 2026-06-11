package com.costoda.dittoedgestudio.ui.mainstudio

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.costoda.dittoedgestudio.ui.mainstudio.metrics.AppMetricsScreen
import com.costoda.dittoedgestudio.ui.mainstudio.metrics.DiskUsageScreen
import com.costoda.dittoedgestudio.viewmodel.AppMetricsViewModel
import com.costoda.dittoedgestudio.viewmodel.DiskUsageViewModel
import com.costoda.dittoedgestudio.viewmodel.MainStudioViewModel
import org.koin.androidx.compose.koinViewModel

/**
 * Scene-driven section composables for the three single-pane rail sections:
 * Log Analyzer, App Metrics, and Database Metrics.
 *
 * Each composable is the `content` lambda passed to [StudioSectionContainer] in
 * [com.costoda.dittoedgestudio.ui.navigation.AppNavGraph]. They resolve their
 * dependencies exactly as the legacy [MainStudioScreen] ContentPlaceholder `when`
 * branches did — no internals of the leaf screens are changed.
 */

/**
 * Log Analyzer section content.
 *
 * [viewModel.loggingCaptureService] is the session-scoped [com.costoda.dittoedgestudio.data.logging.DittoLogCaptureService],
 * forwarded directly to [LoggingScreen] — the same resolution used in the legacy monolith.
 */
@Composable
fun LoggingSection(
    viewModel: MainStudioViewModel,
    modifier: Modifier = Modifier,
) {
    LoggingScreen(
        captureService = viewModel.loggingCaptureService,
        modifier = modifier.fillMaxSize(),
    )
}

/**
 * App Metrics section content.
 *
 * [AppMetricsViewModel] is resolved via [koinViewModel] with no parameters — identical to
 * `koinViewModel()` in the legacy ContentPlaceholder branch.
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
 * `koinViewModel()` in the legacy ContentPlaceholder branch.
 */
@Composable
fun DiskUsageSection(
    modifier: Modifier = Modifier,
) {
    val diskUsageViewModel: DiskUsageViewModel = koinViewModel()
    DiskUsageScreen(
        viewModel = diskUsageViewModel,
        modifier = modifier.fillMaxSize(),
    )
}
