package com.costoda.dittoedgestudio.ui.mainstudio

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.costoda.dittoedgestudio.ui.components.DittoConnectedButtonGroup
import com.costoda.dittoedgestudio.viewmodel.MainStudioViewModel

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
 * Design rationale: the content pane (Connected Peers) is NOT driven by list-item selection
 * — it shows peer state for the entire mesh and is always relevant, so it is the default
 * view at every width. At ≥840dp both panes are visible side-by-side via
 * [ListDetailSceneStrategy.listPane] + `detailPlaceholder`. Below 840dp the user sees the
 * peers content immediately on entering Presence; the subscriptions list lives in the drawer
 * (Rail + Data Panel) and tapping an item closes the drawer.
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
) {
    SubscriptionsListPane(
        viewModel = viewModel,
        modifier = modifier,
        onAfterAddOrEditTriggered = onAfterAddOrEditTriggered,
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

    Column(modifier = modifier.fillMaxSize()) {
        // Connected button group (view switcher) + transport-config gear
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 8.dp),
        ) {
            DittoConnectedButtonGroup(
                options = listOf("Peers List", "Presence Viewer"),
                selectedIndex = selectedTabIndex,
                onSelect = { selectedTabIndex = it },
            )
            Spacer(modifier = Modifier.weight(1f))
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
                    // Presence Viewer — future feature; placeholder matches legacy "Coming Soon"
                    Box(
                        modifier = Modifier.fillMaxSize(),
                        contentAlignment = Alignment.Center,
                    ) {
                        Text(
                            text = "Presence Viewer — Coming Soon",
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
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
                if (sub.id == 0L) viewModel.addSubscription(name, query)
                else viewModel.updateSubscription(sub.copy(name = name, query = query))
            },
            onDismiss = { viewModel.editingSubscription = null },
        )
    }
}
