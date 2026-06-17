package com.costoda.dittoedgestudio.ui.mainstudio.inspector

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Analytics
import androidx.compose.material.icons.outlined.BookmarkBorder
import androidx.compose.material.icons.outlined.Code
import androidx.compose.material.icons.outlined.History
import androidx.compose.material.icons.automirrored.outlined.HelpOutline
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import com.costoda.dittoedgestudio.ui.components.DittoConnectedIconButtonGroup
import com.costoda.dittoedgestudio.viewmodel.QueryEditorViewModel
import com.costoda.dittoedgestudio.viewmodel.QueryInspectorTab

private val INSPECTOR_TAB_ICONS: List<ImageVector> = listOf(
    Icons.Outlined.History,
    Icons.Outlined.BookmarkBorder,
    Icons.Outlined.Code,
    Icons.Outlined.Analytics,
    Icons.AutoMirrored.Outlined.HelpOutline,
)

private val INSPECTOR_TAB_DESCRIPTIONS: List<String> = listOf(
    "History",
    "Favorites",
    "JSON",
    "Metrics",
    "Help",
)

@Composable
fun QueryInspectorView(
    viewModel: QueryEditorViewModel,
    modifier: Modifier = Modifier,
) {
    val selectedTab by viewModel.selectedInspectorTab.collectAsStateWithLifecycle()
    val history by viewModel.history.collectAsStateWithLifecycle()
    val favorites by viewModel.favorites.collectAsStateWithLifecycle()
    val selectedDocument by viewModel.selectedDocument.collectAsStateWithLifecycle()
    val metrics by viewModel.queryMetrics.collectAsStateWithLifecycle()
    val cachedAtt by viewModel.cachedAttachments.collectAsStateWithLifecycle()

    Column(modifier = modifier.fillMaxSize()) {
        // Icon-only connected button group — fits the narrow 300-400dp inspector column
        // without wrapping; selection is conveyed by SulfurYellow container + shape morph.
        DittoConnectedIconButtonGroup(
            icons = INSPECTOR_TAB_ICONS,
            contentDescriptions = INSPECTOR_TAB_DESCRIPTIONS,
            selectedIndex = selectedTab.ordinal,
            onSelect = { viewModel.setInspectorTab(QueryInspectorTab.entries[it]) },
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
        )

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
                cachedAttachments = cachedAtt,
                onViewAttachment = { viewModel.viewAttachment(it) },
                onDeleteAttachment = {
                    // Stubbed for QWP-13 — Delete sheet lands in QWP-15.
                    android.util.Log.w("QueryInspector", "Delete (QWP-15) $it")
                },
                modifier = Modifier.weight(1f),
            )
            QueryInspectorTab.METRICS -> QueryMetricsInspector(
                metrics = metrics,
                modifier = Modifier.weight(1f),
            )
            QueryInspectorTab.HELP -> HelpContentView(
                assetFileName = "query.md",
                modifier = Modifier.weight(1f),
            )
        }
    }
}
