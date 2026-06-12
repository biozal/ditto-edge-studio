package com.costoda.dittoedgestudio.ui.mainstudio

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
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
import androidx.compose.material3.FloatingActionButton
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
 * List pane for the Presence (Subscriptions) section.
 *
 * Renders the registered DQL subscriptions as a vertical scrollable list, extracted
 * faithfully from the SUBSCRIPTIONS block of the legacy data-panel / phone-drawer layout
 * in MainStudioScreen:
 *  - empty state label
 *  - per-subscription row with edit and delete actions
 *  - FAB to add a new subscription (opens [SubscriptionEditorSheet] via the VM)
 *
 * Subscription CRUD is wired through [MainStudioViewModel] — add/update/remove — with
 * [SubscriptionEditorSheet] managed by [PresenceListSection] so the sheet appears in
 * the correct composition scope regardless of layout breakpoint.
 *
 * This pane is the *list* side of the Presence entry. The *content* side (Connected
 * Peers tabs) is the default view; at ≥840dp the scene strategy renders both side-by-side,
 * and below 840dp the list pane lives inside the modal Nav Drawer (the drawer holds Rail +
 * Data Panel; tapping an item closes the drawer).
 */
@Composable
fun SubscriptionsListPane(
    viewModel: MainStudioViewModel,
    modifier: Modifier = Modifier,
    onAfterAddOrEditTriggered: (() -> Unit)? = null,
) {
    val subscriptions by viewModel.subscriptions.collectAsStateWithLifecycle()

    Box(modifier = modifier.fillMaxSize()) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(bottom = 88.dp),
        ) {
            Text(
                text = "Subscriptions",
                style = MaterialTheme.typography.titleSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp),
            )

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
                        onEdit = {
                            viewModel.editingSubscription = sub
                            onAfterAddOrEditTriggered?.invoke()
                        },
                        onDelete = { viewModel.removeSubscription(sub.id) },
                    )
                }
            }
        }

        // Add-subscription FAB: sets editingSubscription to a fresh DittoSubscription so the
        // SubscriptionEditorSheet hoisted in PresenceContentSection triggers.
        FloatingActionButton(
            onClick = {
                viewModel.editingSubscription = DittoSubscription()
                onAfterAddOrEditTriggered?.invoke()
            },
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
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier
                    .height(16.dp)
                    .width(16.dp),
            )
        }
        IconButton(onClick = onDelete) {
            Icon(
                imageVector = Icons.Outlined.Delete,
                contentDescription = "Delete subscription",
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier
                    .height(16.dp)
                    .width(16.dp),
            )
        }
    }
}
