package com.costoda.dittoedgestudio.ui.mainstudio.inspector

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.HelpOutline
import androidx.compose.material.icons.outlined.Analytics
import androidx.compose.material.icons.outlined.BookmarkBorder
import androidx.compose.material.icons.outlined.Code
import androidx.compose.material.icons.outlined.History
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import com.costoda.dittoedgestudio.domain.model.AttachmentInfo
import com.costoda.dittoedgestudio.ui.components.DittoConnectedIconButtonGroup
import com.costoda.dittoedgestudio.ui.mainstudio.attachments.DeleteAttachmentSheet
import com.costoda.dittoedgestudio.ui.mainstudio.currentCollectionFromQuery
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

    // State: non-null while the Delete sheet is open. Holds the triggering AttachmentInfo so the
    // sheet can pre-populate; the sheet itself re-derives all attachments from selectedDocument.
    var pendingDeleteFor by remember { mutableStateOf<AttachmentInfo?>(null) }

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
                onDeleteAttachment = { pendingDeleteFor = it },
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

    // Delete sheet — shown when pendingDeleteFor is set. Derives all attachments from the current
    // document so the user sees the full list, not just the one row that was tapped.
    val pending = pendingDeleteFor
    if (pending != null) {
        val docId = (selectedDocument?.get("_id") as? String)
        val collectionGuess = currentCollectionFromQuery(viewModel.queryText.value)

        val allAttachments = remember(selectedDocument) {
            selectedDocument?.let { AttachmentInfo.detectTokens(it) } ?: emptyList()
        }

        if (docId == null || collectionGuess == null) {
            // Can't determine target document or collection — dismiss without acting.
            pendingDeleteFor = null
        } else {
            DeleteAttachmentSheet(
                attachments = allAttachments,
                onDismiss = { pendingDeleteFor = null },
                onConfirm = { selected ->
                    viewModel.deleteAttachments(
                        documentId = docId,
                        collection = collectionGuess!!,
                        attachments = selected,
                    )
                    pendingDeleteFor = null
                },
            )
        }
    }
}

// currentCollectionFromQuery is defined in AttachmentTargets.kt (same package) to avoid
// duplication with QueryResultsView. No import needed — same package.
