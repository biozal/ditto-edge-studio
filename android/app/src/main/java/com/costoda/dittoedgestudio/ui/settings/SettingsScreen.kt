package com.costoda.dittoedgestudio.ui.settings

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.costoda.dittoedgestudio.viewmodel.SettingsViewModel
import org.koin.androidx.compose.koinViewModel

/**
 * App-wide settings. Currently a single "Collect Metrics" toggle — the Android
 * counterpart of SwiftUI's Settings → General → "Collect Metrics"
 * (`AppPreferencesView`). The preference gates metrics capture and the visibility
 * of the App Metrics / Query Metrics rail items in the studio.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
    viewModel: SettingsViewModel = koinViewModel(),
) {
    val metricsEnabled by viewModel.metricsEnabled.collectAsStateWithLifecycle()
    val presenceSplitView by viewModel.presenceSplitView.collectAsStateWithLifecycle()

    Scaffold(
        modifier = modifier,
        topBar = {
            TopAppBar(
                title = { Text("Settings") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Outlined.ArrowBack,
                            contentDescription = "Back",
                        )
                    }
                },
            )
        },
    ) { paddingValues ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(paddingValues),
        ) {
            Text(
                text = "Metrics",
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
            )
            ListItem(
                headlineContent = { Text("Collect Metrics") },
                supportingContent = {
                    Text(
                        "When disabled, no performance data is collected and the " +
                            "Metrics sections are hidden from the navigation menu.",
                    )
                },
                trailingContent = {
                    Switch(
                        checked = metricsEnabled,
                        onCheckedChange = { viewModel.setMetricsEnabled(it) },
                    )
                },
            )
            HorizontalDivider()

            Text(
                text = "Layout",
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
            )
            ListItem(
                headlineContent = { Text("Split Presence view") },
                supportingContent = {
                    Text(
                        "Show the subscriptions list beside the peers view on wide screens. " +
                            "When off, Presence uses the full width and subscriptions open " +
                            "from the Presence toolbar.",
                    )
                },
                trailingContent = {
                    Switch(
                        checked = presenceSplitView,
                        onCheckedChange = { viewModel.setPresenceSplitView(it) },
                    )
                },
            )
            HorizontalDivider()
        }
    }
}
