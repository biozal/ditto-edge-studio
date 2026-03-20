@file:OptIn(ExperimentalMaterial3Api::class)

package com.costoda.dittoedgestudio.ui.mainstudio.inspector

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Analytics
import androidx.compose.material.icons.outlined.BookmarkBorder
import androidx.compose.material.icons.outlined.Code
import androidx.compose.material.icons.outlined.History
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.SecondaryTabRow
import androidx.compose.material3.Tab
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import com.costoda.dittoedgestudio.viewmodel.QueryEditorViewModel
import com.costoda.dittoedgestudio.viewmodel.QueryInspectorTab

@Composable
fun QueryInspectorView(
    viewModel: QueryEditorViewModel,
    modifier: Modifier = Modifier,
) {
    val selectedTab by viewModel.selectedInspectorTab.collectAsState()
    val history by viewModel.history.collectAsState()
    val favorites by viewModel.favorites.collectAsState()
    val selectedDocument by viewModel.selectedDocument.collectAsState()
    val metrics by viewModel.queryMetrics.collectAsState()

    val tabs = QueryInspectorTab.entries

    Column(modifier = modifier.fillMaxSize()) {
        SecondaryTabRow(selectedTabIndex = selectedTab.ordinal) {
            tabs.forEach { tab ->
                val (icon, label) = tabIcon(tab)
                Tab(
                    selected = selectedTab == tab,
                    onClick = { viewModel.setInspectorTab(tab) },
                    icon = {
                        Icon(
                            imageVector = icon,
                            contentDescription = label,
                            modifier = Modifier.size(20.dp),
                        )
                    },
                )
            }
        }

        when (selectedTab) {
            QueryInspectorTab.HISTORY -> QueryHistoryInspector(
                viewModel = viewModel,
                history = history,
                modifier = Modifier.weight(1f),
            )
            QueryInspectorTab.FAVORITES -> QueryFavoritesInspector(
                viewModel = viewModel,
                favorites = favorites,
                modifier = Modifier.weight(1f),
            )
            QueryInspectorTab.JSON -> QueryJsonInspector(
                selectedDocument = selectedDocument,
                modifier = Modifier.weight(1f),
            )
            QueryInspectorTab.METRICS -> QueryMetricsInspector(
                metrics = metrics,
                modifier = Modifier.weight(1f),
            )
        }
    }
}

private fun tabIcon(tab: QueryInspectorTab): Pair<ImageVector, String> = when (tab) {
    QueryInspectorTab.HISTORY -> Pair(Icons.Outlined.History, "History")
    QueryInspectorTab.FAVORITES -> Pair(Icons.Outlined.BookmarkBorder, "Favorites")
    QueryInspectorTab.JSON -> Pair(Icons.Outlined.Code, "JSON")
    QueryInspectorTab.METRICS -> Pair(Icons.Outlined.Analytics, "Metrics")
}
