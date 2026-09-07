package com.costoda.dittoedgestudio.ui.mainstudio

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ViewList
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Surface
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.costoda.dittoedgestudio.data.preferences.AppPreferencesGateway
import com.costoda.dittoedgestudio.ui.adaptive.studioMultiPane
import com.costoda.dittoedgestudio.ui.adaptive.studioWindowSizeClass
import com.costoda.dittoedgestudio.ui.components.DittoConnectedButtonGroup
import com.costoda.dittoedgestudio.ui.mainstudio.presence.PresenceGraphView
import com.costoda.dittoedgestudio.ui.mainstudio.presence.PresencePeerSearch
import com.costoda.dittoedgestudio.ui.mainstudio.presence.PresencePeerSearchBar
import com.costoda.dittoedgestudio.ui.mainstudio.presence.PresencePeerSearchResults
import com.costoda.dittoedgestudio.viewmodel.MainStudioViewModel
import org.koin.compose.koinInject

/**
 * Scene-driven section composables for the Presence (canonical: Subscriptions) section
 * (Task 4.3c).
 *
 * Two entry-point variants:
 *  - [PresenceListSection]    — list-pane content (subscriptions list + FAB + editor sheet).
 *                               Used by `entry<SubscriptionsKey>` as the list pane at ≥840dp,
 *                               and rendered inside the modal Nav Drawer below 840dp.
 *  - [PresenceContentSection] — content/detail pane: Peers List / Presence Viewer tabs +
 *                               transport-config gear button. Used as both the
 *                               `detailPlaceholder` (≥840dp) and the section-entry content
 *                               below 840dp (Content Pane is the default view).
 *
 * Design rationale: the content pane (Connected Peers / Presence Viewer) is NOT driven by
 * list-item selection — it shows peer state for the entire mesh and is always relevant, so
 * it is the default view at every width. The "Split Presence view" setting
 * (`AppPreferences.presenceSplitView`, default OFF) controls whether the subscriptions list
 * sits beside the peers view at ≥600dp via [ListDetailSceneStrategy.listPane] +
 * `detailPlaceholder`. When OFF, the peers content gets the full width and the
 * subscriptions list is reached via the modal Nav Drawer (drawer-mode widths) or the
 * header's Subscriptions dialog (rail-mode widths). Below 600dp the user always sees the
 * peers content immediately on entering Presence, with the list in the drawer.
 */

// ── List-pane entry-point ─────────────────────────────────────────────────────

/**
 * List-pane content for the Presence section.
 *
 * Renders [SubscriptionsListPane]. The [SubscriptionEditorSheet] is hoisted into
 * [PresenceContentSection] (the always-composed body) so it survives drawer dismiss
 * below 840dp.
 */
@Composable
fun PresenceListSection(
    viewModel: MainStudioViewModel,
    modifier: Modifier = Modifier,
    onAfterAddOrEditTriggered: (() -> Unit)? = null,
    onScanSubscriptionsQr: (() -> Unit)? = null,
) {
    SubscriptionsListPane(
        viewModel = viewModel,
        modifier = modifier,
        onAfterAddOrEditTriggered = onAfterAddOrEditTriggered,
        onScanQr = onScanSubscriptionsQr,
    )
}

// ── Content/detail-pane entry-point ──────────────────────────────────────────

/**
 * Content/detail-pane for the Presence section: the Peers List / Presence Viewer tab
 * selector plus [ConnectedPeersScreen].
 *
 * Mirrors the `viewModel.selectedNavItem == StudioNavItem.SUBSCRIPTIONS` branch in the
 * legacy content-placeholder layout exactly:
 *  - [DittoConnectedButtonGroup] view switcher: "Peers List" (0) and "Presence Viewer" (1)
 *  - Settings gear → transport-config sheet
 *  - [DittoPermissionHandler] + [ConnectedPeersScreen] on tab 0
 *  - Tab 1: placeholder (Presence Graph is a future feature, not yet implemented in legacy)
 *
 * Tab selection is persisted with [rememberSaveable] (matches legacy `rememberSaveable` in
 * legacy content-placeholder layout).
 *
 * The transport-config [ModalBottomSheet] is surfaced here because this composable owns
 * the gear button that triggers it, keeping the sheet co-located with its trigger.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PresenceContentSection(
    viewModel: MainStudioViewModel,
    modifier: Modifier = Modifier,
) {
    var selectedTabIndex by rememberSaveable { mutableIntStateOf(0) }
    val peersUiState by viewModel.peersUiState.collectAsStateWithLifecycle()
    val networkInterfaces by viewModel.networkInterfaces.collectAsStateWithLifecycle()
    val p2pTransports by viewModel.p2pTransports.collectAsStateWithLifecycle()

    // ── Presence Viewer peer search ──────────────────────────────────────────
    // Hoisted to the view model so query, dimming and focus all survive the
    // Peers ↔ Viewer tab switch (the `when` below disposes the graph subtree).
    val showDirectOnly by viewModel.showDirectConnectedOnly.collectAsStateWithLifecycle()
    val focusedPeerId by viewModel.presenceFocusedPeerId.collectAsStateWithLifecycle()
    val pendingFocusPeerId by viewModel.presencePendingFocusPeerId.collectAsStateWithLifecycle()
    val searchQuery by viewModel.presenceSearchQuery.collectAsStateWithLifecycle()
    // Candidates come from the FULL mesh and are rebuilt per presence push, not per
    // keystroke: a multi-hop peer has to be findable while Direct is on, because
    // picking it is exactly how the user jumps the graph over to it.
    val searchCandidates by remember(peersUiState) {
        derivedStateOf { PresencePeerSearch.candidates(peersUiState) }
    }
    val searchMatches by remember(searchCandidates, searchQuery) {
        derivedStateOf { PresencePeerSearch.matches(searchCandidates, searchQuery) }
    }
    // derivedStateOf so an unchanged match set does not re-invalidate the graph on
    // every keystroke. `null` = box empty; EMPTY set = active query, no hits.
    val searchMatchIds by remember(searchCandidates, searchQuery) {
        derivedStateOf { PresencePeerSearch.matchIds(searchCandidates, searchQuery) }
    }
    val searchIsActive = PresencePeerSearch.isActive(searchQuery)
    // Narrow layouts collapse the box to an icon that takes over the row — it still
    // costs the canvas no height either way.
    var searchExpanded by rememberSaveable { mutableStateOf(false) }

    // Picking a result focuses that peer exactly as clicking its pill in the full
    // mesh would. With Direct on the peer is not in the scene yet, so this flips
    // Direct off and parks the request; PresenceGraphView consumes it once the
    // rebuilt layout has placed the peer (and owns the re-pick-to-toggle-off rule,
    // because only it can restore the pre-focus camera). The query is deliberately
    // kept so the user can hop between results.
    val onPickSearchResult: (String) -> Unit = { peerId ->
        viewModel.requestPresenceFocus(peerId)
        if (showDirectOnly) viewModel.toggleDirectConnectedOnly()
    }

    // Back clears the query. The graph's own BackHandler for the detail card is
    // nested deeper and therefore consumes back FIRST — which is exactly the
    // card-then-query unwind order, and why this one is not conditional on the card.
    BackHandler(enabled = selectedTabIndex == 1 && searchIsActive) {
        viewModel.setPresenceSearchQuery("")
    }

    // "Split Presence view" setting (Settings screen). When OFF at rail-mode widths
    // (≥840dp) there is no drawer to host the subscriptions list, so the header offers
    // a Subscriptions dialog instead. Below 840dp (drawer mode) the drawer already hosts
    // the list when split is off, so the button would be a redundant affordance.
    val appPreferences = koinInject<AppPreferencesGateway>()
    val presenceSplitView by appPreferences.presenceSplitView
        .collectAsStateWithLifecycle(initialValue = false)
    val showSubscriptionsButton = studioWindowSizeClass().studioMultiPane && !presenceSplitView
    var subscriptionsDialogVisible by remember { mutableStateOf(false) }

    Column(modifier = modifier.fillMaxSize()) {
        // Connected button group (view switcher) + peer search + transport-config gear.
        //
        // The peer search rides in THIS row rather than one of its own: the canvas
        // must keep its full height, which is the whole point of the feature.
        BoxWithConstraints(modifier = Modifier.fillMaxWidth()) {
            // The button group refuses to shrink (IntrinsicSize.Max, and M3
            // Expressive morphs the selected segment wider on tap), and the icon
            // buttons are fixed — so below this width there is no room to put a
            // usable field beside them and the search collapses to an icon that
            // takes over the row instead. Measured from the pane, not the window:
            // this content can sit in a detail pane far narrower than the display.
            val inlineSearch = maxWidth >= 600.dp
            val showSearch = selectedTabIndex == 1
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 8.dp),
            ) {
                if (showSearch && searchExpanded && !inlineSearch) {
                    // Narrow: the field owns the row until dismissed.
                    PresencePeerSearchBar(
                        query = searchQuery,
                        onQueryChange = { viewModel.setPresenceSearchQuery(it) },
                        onSubmit = {
                            searchMatches.firstOrNull { !it.isLocal }
                                ?.let { onPickSearchResult(it.key) }
                        },
                        modifier = Modifier.weight(1f),
                    )
                    IconButton(onClick = {
                        searchExpanded = false
                        viewModel.setPresenceSearchQuery("")
                    }) {
                        Icon(
                            imageVector = Icons.Outlined.Close,
                            contentDescription = "Close peer search",
                            tint = MaterialTheme.colorScheme.onSurface,
                        )
                    }
                } else {
                    // Short labels: M3 Expressive connected groups morph the selected segment
                    // wider on tap, which squeezed the gear icon to the right when the label was
                    // "Presence Viewer". "Peers" / "Viewer" keep both segments visually balanced.
                    DittoConnectedButtonGroup(
                        options = listOf("Peers", "Viewer"),
                        selectedIndex = selectedTabIndex,
                        onSelect = { selectedTabIndex = it },
                    )
                    if (showSearch && inlineSearch) {
                        PresencePeerSearchBar(
                            query = searchQuery,
                            onQueryChange = { viewModel.setPresenceSearchQuery(it) },
                            onSubmit = {
                                searchMatches.firstOrNull { !it.isLocal }
                                    ?.let { onPickSearchResult(it.key) }
                            },
                            modifier = Modifier
                                .weight(1f)
                                .padding(start = 12.dp),
                        )
                    } else {
                        Spacer(modifier = Modifier.weight(1f))
                    }
                    if (showSearch && !inlineSearch) {
                        IconButton(onClick = { searchExpanded = true }) {
                            Icon(
                                imageVector = Icons.Outlined.Search,
                                contentDescription = "Search peers",
                                tint = MaterialTheme.colorScheme.onSurface,
                            )
                        }
                    }
                    if (showSubscriptionsButton) {
                        IconButton(onClick = { subscriptionsDialogVisible = true }) {
                            Icon(
                                imageVector = Icons.AutoMirrored.Outlined.ViewList,
                                contentDescription = "Subscriptions",
                                tint = MaterialTheme.colorScheme.onSurface,
                            )
                        }
                    }
                    IconButton(onClick = { viewModel.transportConfigVisible = true }) {
                        Icon(
                            imageVector = Icons.Outlined.Settings,
                            contentDescription = "Transport config",
                            tint = MaterialTheme.colorScheme.onSurface,
                        )
                    }
                }
            }
        }

        Box(modifier = Modifier.weight(1f).fillMaxWidth()) {
            when (selectedTabIndex) {
                0 -> {
                    DittoPermissionHandler()
                    ConnectedPeersScreen(
                        peersUiState = peersUiState,
                        networkInterfaces = networkInterfaces,
                        p2pTransports = p2pTransports,
                        onLoadDiagnostics = { viewModel.loadNetworkDiagnostics() },
                    )
                }
                else -> {
                    val controlsVisible by viewModel.presenceControlsVisible
                        .collectAsStateWithLifecycle()
                    // showDirectOnly / focusedPeerId are collected at section level:
                    // the search results card, which lives outside this branch, has
                    // to route picks against the same state.
                    PresenceGraphView(
                        peersUiState = peersUiState,
                        showDirectConnectedOnly = showDirectOnly,
                        onToggleDirectConnectedOnly = { viewModel.toggleDirectConnectedOnly() },
                        focusedPeerId = focusedPeerId,
                        onFocusedPeerChange = { viewModel.setPresenceFocusedPeer(it) },
                        controlsVisible = controlsVisible,
                        onToggleControlsVisible = { viewModel.togglePresenceControlsVisible() },
                        searchMatchIds = searchMatchIds,
                        pendingFocusPeerId = pendingFocusPeerId,
                        onPendingFocusConsumed = { viewModel.requestPresenceFocus(null) },
                        modifier = Modifier.fillMaxSize(),
                    )
                }
            }

            // The results card floats over the canvas instead of sitting in the
            // layout flow, so typing never reflows the graph underneath it.
            if (selectedTabIndex == 1 && searchIsActive) {
                PresencePeerSearchResults(
                    query = searchQuery,
                    matches = searchMatches,
                    onPick = onPickSearchResult,
                    modifier = Modifier
                        .align(Alignment.TopEnd)
                        .padding(horizontal = 16.dp, vertical = 4.dp),
                )
            }
        }
    }

    // Subscriptions dialog — shown when the split view is off at ≥600dp. A Dialog (not a
    // ModalBottomSheet) so the SubscriptionEditorSheet bottom sheet can stack on top of it;
    // the dialog dismisses as soon as add/edit is triggered, leaving only the editor sheet.
    if (subscriptionsDialogVisible) {
        Dialog(
            onDismissRequest = { subscriptionsDialogVisible = false },
            properties = DialogProperties(usePlatformDefaultWidth = false),
        ) {
            Surface(
                modifier = Modifier
                    .width(400.dp)
                    .fillMaxHeight(0.85f),
                shape = RoundedCornerShape(16.dp),
                tonalElevation = 8.dp,
            ) {
                SubscriptionsListPane(
                    viewModel = viewModel,
                    onAfterAddOrEditTriggered = { subscriptionsDialogVisible = false },
                )
            }
        }
    }

    // Transport-config sheet: co-located with its trigger (gear button above).
    if (viewModel.transportConfigVisible) {
        ModalBottomSheet(
            onDismissRequest = { viewModel.transportConfigVisible = false },
            sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        ) {
            TransportConfigContent(viewModel = viewModel)
        }
    }

    // Subscription editor sheet — hoisted here (out of PresenceListSection) so the bottom
    // sheet remains in composition even when the list pane leaves it (e.g. when the Nav
    // Drawer dismisses below 840dp after the user taps the FAB or an edit button).
    viewModel.editingSubscription?.let { sub ->
        SubscriptionEditorSheet(
            initial = sub,
            onSave = { name, query ->
                // Suspend until the Room write commits — the editor sheet shows
                // a "Saving…" spinner and blocks dismissal until this returns.
                // On success the VM clears editingSubscription, removing this
                // composable from composition.
                if (sub.id == 0L) {
                    viewModel.addSubscription(name, query)
                } else {
                    viewModel.updateSubscription(sub.copy(name = name, query = query))
                }
            },
            onDismiss = { viewModel.editingSubscription = null },
        )
    }

    // Subscriptions share-QR dialog / server-import sheet — hoisted here so they survive
    // drawer dismiss below 840dp (same reasoning as the editor sheet above). Triggered via
    // StudioUiState flags set by the list pane's header icons.
    val subscriptions by viewModel.subscriptions.collectAsStateWithLifecycle()
    if (viewModel.session.uiState.showSubscriptionsQr) {
        SubscriptionsQrDisplayDialog(
            subscriptions = subscriptions,
            onDismiss = { viewModel.session.uiState.showSubscriptionsQr = false },
        )
    }
    if (viewModel.session.uiState.showImportSubscriptionsFromServer) {
        ImportSubscriptionsFromServerSheet(
            viewModel = viewModel,
            onDismiss = { viewModel.session.uiState.showImportSubscriptionsFromServer = false },
        )
    }
}
