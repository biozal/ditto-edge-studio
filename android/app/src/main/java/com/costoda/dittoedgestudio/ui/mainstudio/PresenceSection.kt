package com.costoda.dittoedgestudio.ui.mainstudio

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.SecondaryTabRow
import androidx.compose.material3.Tab
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.costoda.dittoedgestudio.viewmodel.MainStudioViewModel

/**
 * Scene-driven section composables for the Presence (canonical: Subscriptions) section
 * (Task 4.3c).
 *
 * Two entry-point variants:
 *  - [PresenceListSection]    — list-pane content (subscriptions list + FAB + editor sheet).
 *                               Used by `entry<SubscriptionsKey>` as the list pane.
 *  - [PresenceContentSection] — content/detail pane: Peers List / Presence Viewer tabs +
 *                               transport-config gear button. Used as both the
 *                               `detailPlaceholder` (expanded) and the pushed
 *                               `entry<PresenceContentKey>` (compact).
 *
 * Design rationale (vs. pure Observers list-detail):
 * The content pane (Connected Peers) is NOT driven by list-item selection — it shows peer
 * state for the entire mesh and is always relevant. At ≥600dp both panes are visible
 * side-by-side via [ListDetailSceneStrategy.listPane] with a `detailPlaceholder` that
 * renders [PresenceContentSection] directly. At compact widths the user starts on the
 * content pane (peers are the primary view) and reaches the subscriptions list via a
 * pushed entry ([PresenceContentKey] → back-stack push of the list pane is not needed
 * because the scaffold's compact drawer already exposes the list pane via the rail drawer
 * — but this section is entry<SubscriptionsKey> with the list pane as the primary, so
 * compact users see the list first with the peers view as the pushed detail — matching
 * today's phone behavior where the drawer holds the list and content shows peers).
 */

// ── List-pane entry-point ─────────────────────────────────────────────────────

/**
 * List-pane content for the Presence section.
 *
 * Renders [SubscriptionsListPane] and hoists the [SubscriptionEditorSheet] so the sheet
 * appears as a child of this pane regardless of layout breakpoint.
 *
 * @param onViewPeers Called when the user taps "View Peers" (compact-width only). The
 *   caller pushes [PresenceContentKey] onto the back stack. At expanded widths the detail
 *   placeholder already shows [PresenceContentSection] and this callback is never needed.
 */
@Composable
fun PresenceListSection(
    viewModel: MainStudioViewModel,
    onViewPeers: (() -> Unit)? = null,
    modifier: Modifier = Modifier,
) {
    SubscriptionsListPane(
        viewModel = viewModel,
        onViewPeers = onViewPeers,
        modifier = modifier,
    )

    // Editor sheet: opens whenever editingSubscription is non-null. Reuses the existing sheet.
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

// ── Content/detail-pane entry-point ──────────────────────────────────────────

/**
 * Content/detail-pane for the Presence section: the Peers List / Presence Viewer tab
 * selector plus [ConnectedPeersScreen].
 *
 * Mirrors the `viewModel.selectedNavItem == StudioNavItem.SUBSCRIPTIONS` branch in the
 * legacy [ContentPlaceholder] exactly:
 *  - [SecondaryTabRow] with "Peers List" (tab 0) and "Presence Viewer" (tab 1)
 *  - Settings gear → transport-config sheet
 *  - [DittoPermissionHandler] + [ConnectedPeersScreen] on tab 0
 *  - Tab 1: placeholder (Presence Graph is a future feature, not yet implemented in legacy)
 *
 * Tab selection is persisted with [rememberSaveable] (matches legacy `rememberSaveable` in
 * [ContentPlaceholder]).
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
        // Tab row + transport-config gear
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.fillMaxWidth(),
        ) {
            SecondaryTabRow(
                selectedTabIndex = selectedTabIndex,
                modifier = Modifier.weight(1f),
            ) {
                Tab(
                    selected = selectedTabIndex == 0,
                    onClick = { selectedTabIndex = 0 },
                    text = { Text("Peers List") },
                )
                Tab(
                    selected = selectedTabIndex == 1,
                    onClick = { selectedTabIndex = 1 },
                    text = { Text("Presence Viewer") },
                )
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
}
