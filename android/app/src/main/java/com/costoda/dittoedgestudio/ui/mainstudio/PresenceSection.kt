package com.costoda.dittoedgestudio.ui.mainstudio

import androidx.compose.foundation.layout.Box
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
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Surface
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
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
        // Connected button group (view switcher) + transport-config gear
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 8.dp),
        ) {
            // Short labels: M3 Expressive connected groups morph the selected segment
            // wider on tap, which squeezed the gear icon to the right when the label was
            // "Presence Viewer". "Peers" / "Viewer" keep both segments visually balanced.
            DittoConnectedButtonGroup(
                options = listOf("Peers", "Viewer"),
                selectedIndex = selectedTabIndex,
                onSelect = { selectedTabIndex = it },
            )
            Spacer(modifier = Modifier.weight(1f))
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
                    val showDirectOnly by viewModel.showDirectConnectedOnly
                        .collectAsStateWithLifecycle()
                    val controlsVisible by viewModel.presenceControlsVisible
                        .collectAsStateWithLifecycle()
                    // Hoisted so an active focus session survives the Peers ↔
                    // Viewer tab switch (the tab `when` disposes the subtree).
                    val focusedPeerId by viewModel.presenceFocusedPeerId
                        .collectAsStateWithLifecycle()
                    PresenceGraphView(
                        peersUiState = peersUiState,
                        showDirectConnectedOnly = showDirectOnly,
                        onToggleDirectConnectedOnly = { viewModel.toggleDirectConnectedOnly() },
                        focusedPeerId = focusedPeerId,
                        onFocusedPeerChange = { viewModel.setPresenceFocusedPeer(it) },
                        controlsVisible = controlsVisible,
                        onToggleControlsVisible = { viewModel.togglePresenceControlsVisible() },
                        modifier = Modifier.fillMaxSize(),
                    )
                }
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
