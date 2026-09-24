package com.costoda.dittoedgestudio.ui.welcome

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.OpenInNew
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.costoda.dittoedgestudio.data.preferences.AppPreferencesGateway
import com.costoda.dittoedgestudio.ui.adaptive.showsListDetail
import com.costoda.dittoedgestudio.ui.adaptive.studioWindowSizeClass
import com.costoda.dittoedgestudio.ui.theme.SulfurYellow
import kotlinx.coroutines.launch
import org.koin.compose.koinInject

/**
 * Welcome tour for a freshly-opened database (port of the SwiftUI `WelcomeView`).
 *
 * Shown full-screen (no studio chrome) when a database is opened with no
 * subscriptions and no query history — subject to the "show on new database"
 * preference in the footer — or manually from the studio top bar's help action.
 */
@Composable
fun WelcomeScreen(onClose: () -> Unit) {
    val preferences: AppPreferencesGateway = koinInject()
    val showOnNewDatabase by preferences.showWelcomeOnNewDatabase
        .collectAsState(initial = true)
    val scope = rememberCoroutineScope()
    val isWide = studioWindowSizeClass().showsListDetail

    Scaffold(
        topBar = {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 8.dp, vertical = 4.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Spacer(modifier = Modifier.weight(1f))
                IconButton(onClick = onClose) {
                    Icon(Icons.Filled.Close, contentDescription = "Close welcome screen")
                }
            }
        },
    ) { padding ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
            contentAlignment = if (isWide) Alignment.Center else Alignment.TopStart,
        ) {
            Column(
                modifier = Modifier
                    .widthIn(max = 900.dp)
                    .fillMaxWidth()
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = 24.dp, vertical = 16.dp),
                verticalArrangement = Arrangement.spacedBy(24.dp),
            ) {
                WelcomeHero()
                WhatIsDittoSection()
                FeatureSection(isWide)
                GetStartedSection()
                LearnMoreSection()
                WelcomeFooter(
                    showOnNewDatabase = showOnNewDatabase,
                    onToggle = { scope.launch { preferences.setShowWelcomeOnNewDatabase(it) } },
                    onClose = onClose,
                )
            }
        }
    }
}

@Composable
private fun WelcomeHero() {
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Box(
                modifier = Modifier
                    .size(64.dp)
                    .background(SulfurYellow, RoundedCornerShape(14.dp)),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    Icons.Filled.Bolt,
                    contentDescription = null,
                    tint = androidx.compose.ui.graphics.Color.Black,
                    modifier = Modifier.size(32.dp),
                )
            }
            Column {
                Text(
                    text = "Welcome to Ditto Edge Studio",
                    style = MaterialTheme.typography.headlineMedium,
                    fontWeight = FontWeight.SemiBold,
                )
                Text(
                    text = "A quick tour of what this app does and how to get the most out of your Ditto database.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        HorizontalDivider()
    }
}

@Composable
private fun QuoteBlock(content: @Composable () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(
                MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f),
                RoundedCornerShape(6.dp),
            ),
    ) {
        Box(modifier = Modifier.width(3.dp).height(72.dp).background(SulfurYellow))
        Box(modifier = Modifier.padding(horizontal = 14.dp, vertical = 12.dp)) {
            content()
        }
    }
}

@Composable
private fun WhatIsDittoSection() {
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text("What is Ditto?", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold)
        Text(
            text = "Ditto is a peer-to-peer, offline-first database. Apps that embed the Ditto SDK sync data " +
                "directly with each other over Bluetooth LE, peer-to-peer Wi-Fi, and local LAN — no internet " +
                "required. When a network is available, devices can also sync to the Ditto cloud " +
                "for durability and global reach.",
            style = MaterialTheme.typography.bodyMedium,
        )
        QuoteBlock {
            Text(
                text = "The mesh keeps working when Wi-Fi goes down, devices roam in and out of range, or the " +
                    "cloud is unreachable. Every device holds a full replica of the data it cares about, and " +
                    "conflicts are resolved automatically using CRDTs — no merge UI, no lost writes.",
                style = MaterialTheme.typography.bodyMedium,
            )
        }
        WelcomeLink("About Ditto", "https://docs.ditto.live/home/about-ditto")
    }
}

private data class WelcomeFeature(val title: String, val body: String)

private val features = listOf(
    WelcomeFeature(
        "Multiple databases",
        "Register every Ditto database you work with — dev, staging, prod — and switch between them from the database list.",
    ),
    WelcomeFeature(
        "DQL Query Editor",
        "Run Ditto Query Language statements with history, favorites, and EXPLAIN plans. Page through large result sets without locking up the UI.",
    ),
    WelcomeFeature(
        "Subscriptions",
        "Manage the queries that keep data flowing to this device. Import existing subscriptions via QR code or from a peer that's already configured.",
    ),
    WelcomeFeature(
        "Presence Graph",
        "Visualise the live mesh in real time: every connected peer, the transports they're using (LAN, Bluetooth, Wi-Fi Aware, WebSocket), and how data routes through them.",
    ),
    WelcomeFeature(
        "Query & Database Metrics",
        "Per-database dashboards that surface query execution plans, recent run history, and storage breakdown by collection — handy for diagnosing slow queries or runaway disk usage.",
    ),
    WelcomeFeature(
        "Import & Export",
        "Move JSON datasets between collections, peers, or environments. Export the entire result of a query (not just the visible page) to a portable JSON file.",
    ),
    WelcomeFeature(
        "Attachments",
        "Add, fetch, preview, and save binary attachments (images, audio, video, PDFs) right from the query results.",
    ),
    WelcomeFeature(
        "Logging",
        "Live and historical SDK logs with pattern-match problem detection, filtered by level, component, and date range. Share the logs straight from the app for bug reports.",
    ),
)

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun FeatureSection(isWide: Boolean) {
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text("What this app does", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold)
        Text(
            text = "Ditto Edge Studio is a control panel for your Ditto databases — inspect their live state, " +
                "manage subscriptions, run DQL queries, and move data in and out without leaving the app.",
            style = MaterialTheme.typography.bodyMedium,
        )
        FlowRow(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
            maxItemsInEachRow = if (isWide) 2 else 1,
        ) {
            features.forEach { feature ->
                Column(
                    modifier = Modifier
                        .weight(1f, fill = true)
                        .widthIn(min = 260.dp)
                        .background(
                            MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.4f),
                            RoundedCornerShape(8.dp),
                        )
                        .padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    Text(feature.title, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
                    Text(
                        feature.body,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
    }
}

@Composable
private fun GetStartedSection() {
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text("Get started in three steps", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold)
        Column {
            StepRow(
                number = 1,
                title = "Add your first subscription",
                details = "Subscriptions are the queries that pull data from the Ditto cloud (and your peers) " +
                    "down to this device. Open the Presence section and tap the add button in the " +
                    "Subscriptions list. Without at least one, your local replica stays empty.",
                linkLabel = "About subscriptions",
                linkUrl = "https://docs.ditto.live/sdk/latest/sync/syncing-data",
            )
            HorizontalDivider()
            StepRow(
                number = 2,
                title = "Explore your data",
                details = "Open the Query Workbench section to write DQL against any collection in this " +
                    "database. Results appear in the detail pane — switch between JSON and Table views.",
                linkLabel = "DQL reference",
                linkUrl = "https://docs.ditto.live/dql/dql",
            )
            HorizontalDivider()
            StepRow(
                number = 3,
                title = "Visualise the mesh",
                details = "The Presence section includes a Presence Graph view that draws every connected " +
                    "peer in real time. Useful for confirming peers see each other and identifying which " +
                    "transports (LAN, Bluetooth, Wi-Fi Aware, WebSocket) are carrying data.",
                linkLabel = "Mesh Presence guide",
                linkUrl = "https://docs.ditto.live/sdk/latest/sync/using-mesh-presence",
            )
        }
    }
}

@Composable
private fun StepRow(
    number: Int,
    title: String,
    details: String,
    linkLabel: String,
    linkUrl: String,
) {
    Row(
        modifier = Modifier.padding(vertical = 12.dp),
        horizontalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Box(
            modifier = Modifier.size(36.dp).background(SulfurYellow, CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                "$number",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
                color = androidx.compose.ui.graphics.Color.Black,
            )
        }
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
            Text(details, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            WelcomeLink(linkLabel, linkUrl)
        }
    }
}

@Composable
private fun LearnMoreSection() {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        HorizontalDivider()
        Text(
            text = "Want more depth?",
            style = MaterialTheme.typography.titleSmall,
            fontWeight = FontWeight.SemiBold,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
            WelcomeLink("Ditto documentation", "https://docs.ditto.live/home/about-ditto")
            WelcomeLink("DQL reference", "https://docs.ditto.live/dql/dql")
            WelcomeLink("Mesh Presence guide", "https://docs.ditto.live/sdk/latest/sync/using-mesh-presence")
        }
    }
}

@Composable
private fun WelcomeFooter(
    showOnNewDatabase: Boolean,
    onToggle: (Boolean) -> Unit,
    onClose: () -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        HorizontalDivider()
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                text = "Show this screen when opening a new database",
                style = MaterialTheme.typography.bodySmall,
                modifier = Modifier.weight(1f),
            )
            Switch(checked = showOnNewDatabase, onCheckedChange = onToggle)
        }
        TextButton(onClick = onClose, modifier = Modifier.align(Alignment.End)) {
            Text("Close")
        }
    }
}

@Composable
private fun WelcomeLink(title: String, url: String) {
    val uriHandler = LocalUriHandler.current
    TextButton(onClick = { uriHandler.openUri(url) }) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Text(title, style = MaterialTheme.typography.bodySmall)
            Icon(
                Icons.AutoMirrored.Outlined.OpenInNew,
                contentDescription = null,
                modifier = Modifier.size(14.dp),
            )
        }
    }
}
