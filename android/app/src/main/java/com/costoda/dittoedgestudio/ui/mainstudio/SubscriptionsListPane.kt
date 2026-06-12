package com.costoda.dittoedgestudio.ui.mainstudio

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.outlined.People
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.costoda.dittoedgestudio.domain.model.DittoSubscription
import com.costoda.dittoedgestudio.ui.theme.JetBlack
import com.costoda.dittoedgestudio.ui.theme.SulfurYellow
import com.costoda.dittoedgestudio.viewmodel.MainStudioViewModel

/**
 * List pane for the Presence (Subscriptions) section (Task 4.3c scene-driven shell).
 *
 * Renders the registered DQL subscriptions as a vertical scrollable list, extracted
 * faithfully from the [DataPanel] / [PhoneDrawerContent] SUBSCRIPTIONS block in the
 * legacy [MainStudioScreen]:
 *  - empty state label
 *  - per-subscription row with edit and delete actions
 *  - FAB to add a new subscription (opens [SubscriptionEditorSheet] via the VM)
 *
 * Subscription CRUD is wired through [MainStudioViewModel] — add/update/remove — with
 * [SubscriptionEditorSheet] managed by [PresenceListSection] so the sheet appears in
 * the correct composition scope regardless of layout breakpoint.
 *
 * This pane is the *list* side of the Presence entry. The *content* side (Connected
 * Peers tabs) is always visible in expanded layouts as the detail placeholder, and
 * reachable as a pushed key in compact layout via the "View Peers" button.
 *
 * @param onViewPeers When non-null a "View Peers" affordance is shown at the top of the
 *   list (compact-width only). At expanded widths the detail placeholder is always
 *   visible and this callback should be null so the button is hidden.
 */
@Composable
fun SubscriptionsListPane(
    viewModel: MainStudioViewModel,
    onViewPeers: (() -> Unit)? = null,
    modifier: Modifier = Modifier,
) {
    val subscriptions by viewModel.subscriptions.collectAsStateWithLifecycle()

    Box(modifier = modifier.fillMaxSize()) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(bottom = 88.dp),
        ) {
            // "View Peers" affordance — shown at compact widths so users can reach the
            // content pane (Connected Peers) from the list pane.
            if (onViewPeers != null) {
                FilledTonalButton(
                    onClick = onViewPeers,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 8.dp),
                ) {
                    Icon(
                        imageVector = Icons.Outlined.People,
                        contentDescription = null,
                    )
                    Spacer(modifier = Modifier.width(8.dp))
                    Text("View Peers")
                }
                HorizontalDivider()
            }

            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 12.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Text(
                    text = "Subscriptions",
                    style = MaterialTheme.typography.titleSmall,
                )
                Text(
                    text = "${subscriptions.size}",
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }

            if (subscriptions.isEmpty()) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(24.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        text = "No subscriptions registered. Tap + to add one.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            } else {
                subscriptions.forEach { sub ->
                    PresenceSubscriptionRow(
                        subscription = sub,
                        onEdit = { viewModel.editingSubscription = sub },
                        onDelete = { viewModel.removeSubscription(sub.id) },
                    )
                }
            }
        }

        // Add-subscription FAB: sets editingSubscription to a fresh DittoSubscription so the
        // SubscriptionEditorSheet hoisted in PresenceListSection triggers.
        FloatingActionButton(
            onClick = { viewModel.editingSubscription = DittoSubscription() },
            containerColor = SulfurYellow,
            contentColor = JetBlack,
            modifier = Modifier
                .align(Alignment.BottomEnd)
                .padding(16.dp),
        ) {
            Icon(
                imageVector = Icons.Filled.Add,
                contentDescription = "Add subscription",
            )
        }
    }
}

// ─── Private row ─────────────────────────────────────────────────────────────

@Composable
private fun PresenceSubscriptionRow(
    subscription: DittoSubscription,
    onEdit: () -> Unit,
    onDelete: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 2.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = subscription.name.ifBlank { subscription.query },
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurface,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            if (subscription.name.isNotBlank()) {
                Text(
                    text = subscription.query,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
        IconButton(onClick = onEdit) {
            Icon(
                imageVector = Icons.Outlined.Edit,
                contentDescription = "Edit subscription",
                modifier = Modifier
                    .height(16.dp)
                    .width(16.dp),
            )
        }
        IconButton(onClick = onDelete) {
            Icon(
                imageVector = Icons.Outlined.Delete,
                contentDescription = "Delete subscription",
                modifier = Modifier
                    .height(16.dp)
                    .width(16.dp),
            )
        }
    }
}
