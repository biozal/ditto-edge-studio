package com.costoda.dittoedgestudio.ui.mainstudio.presence

import androidx.compose.foundation.ScrollState
import androidx.compose.runtime.remember
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.layout.heightIn
import androidx.compose.material3.TextButton
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.costoda.dittoedgestudio.domain.model.PeerOS
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Fixed card width. Screen-space, so this is the real on-screen size at any camera zoom
 * — see [PEER_DETAIL_CARD_RATIONALE].
 */
internal val PEER_DETAIL_CARD_WIDTH = 260.dp

/**
 * Why this card is a screen-space overlay rather than a laid-out graph node.
 *
 * A focus orbit holds up to 12 peers (the SDK caps connections per peer for battery
 * reasons). Twelve nodes of width W on a ring need radius ≈ 1.93·(W+20), so the content
 * to frame is always ~6× the card width. The focus camera then fits that to the
 * viewport, which hands back a card of width ≈ viewport ÷ 4.9 — a number that depends
 * only on the screen, not on how big the card was drawn. Measured: on a 344 dp screen a
 * 145 dp card renders at 55 dp and a 240 dp card renders at 60 dp. Making the card
 * smaller does not help.
 *
 * So the card cannot be a graph node on a phone at any size. It is drawn at fixed dp on
 * top of the graph instead, which also keeps it out of `peerFootprints` — the moment its
 * size reaches the layout engine, ring radii start moving when a card opens, and the
 * width-only footprint model starts overlapping neighbours vertically.
 */
private const val PEER_DETAIL_CARD_RATIONALE = "see KDoc"

/**
 * Expanded detail for one peer in the presence graph.
 *
 * Renders every field the SDK exposes for a peer. All of it except the sync rows is
 * available for peers the local device cannot reach, which is most of a focus orbit —
 * the orbit is the *focused* peer's neighbourhood, not ours.
 *
 * Rows are always present, even when empty. A missing value shows an explicit reason
 * rather than disappearing: the absence is itself the information, and a fixed row set
 * keeps the card from resizing as the SDK fills fields in (`os` in particular is
 * documented as learned gradually).
 */
@Composable
internal fun PeerDetailCard(
    node: PeerNode,
    maxHeightPx: Float,
    onFocusPeer: (() -> Unit)?,
    modifier: Modifier = Modifier,
) {
    val detail = node.detail
    val density = LocalDensity.current
    // Cap to the viewport and scroll the overflow. At large system font scales every
    // labelSmall row grows, and without this the bottom of the card — the sync rows —
    // is silently clipped by the graph container's clipToBounds().
    val maxHeight = with(density) { maxHeightPx.coerceAtLeast(0f).toDp() }
    Card(
        modifier = modifier
            .width(PEER_DETAIL_CARD_WIDTH)
            .heightIn(max = maxHeight),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceContainerHighest,
        ),
        elevation = CardDefaults.cardElevation(defaultElevation = 8.dp),
    ) {
        // Keyed on the peer: the card swaps in place (same composition slot) when the
        // user taps a different peer, so an unkeyed scroll state would open B's card at
        // A's offset — past its own title, or clamped mid-card.
        val scrollState = remember(node.peerId) { ScrollState(0) }
        Column(
            modifier = Modifier
                .verticalScroll(scrollState)
                .padding(12.dp),
        ) {
            // No close button: tapping the card dismisses it, which is the gesture
            // people reach for anyway and leaves the card free of chrome.
            Text(
                text = node.displayName,
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.onSurface,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
                // Described here rather than on the Card. A contentDescription on the
                // card node suppresses the text payload of everything inside it, so a
                // screen reader announced "Details for <peer>" and nothing else — the
                // OS, SDK, cloud, metadata and sync rows all became unspeakable.
                modifier = Modifier.semantics {
                    contentDescription = "Details for ${node.displayName}"
                },
            )

            if (detail == null) {
                // Only the synthetic cloud node reaches this — it has no DittoPeer
                // behind it. The local peer gets a real record built from LocalPeerInfo.
                Spacer(Modifier.height(6.dp))
                Text(
                    text = "Synthetic node — no peer record",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                return@Column
            }

            Spacer(Modifier.height(8.dp))
            DetailRow("Peer key", detail.peerKey.ifBlank { null }, monospace = true, missing = "not reported")
            DetailRow("OS", detail.os.takeIf { it != PeerOS.Unknown }?.displayName, missing = "not yet known")
            DetailRow("Ditto SDK", detail.dittoSdkVersion, missing = "not yet known")
            DetailRow("Cloud link", detail.isConnectedToDittoServer?.let { if (it) "Connected" else "None" })
            DetailRow("Compatible", detail.isCompatible?.let { if (it) "Yes" else "No" }, missing = "not yet known")

            Spacer(Modifier.height(8.dp))
            HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
            Spacer(Modifier.height(8.dp))

            DetailRow("Peer metadata", metadataSummary(detail.peerMetadataKeyCount, detail.peerMetadata))
            DetailRow(
                "Identity metadata",
                metadataSummary(detail.identityServiceMetadataKeyCount, detail.identityServiceMetadata),
            )

            Spacer(Modifier.height(8.dp))
            HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
            Spacer(Modifier.height(8.dp))

            // Sync rows. system:data_sync_info is a local table computed from where this
            // device actually receives data, so it has no row at all for a peer we have
            // no session with. Say that, rather than showing a blank that reads as a bug.
            when {
                // This device. There is no data_sync_info row for ourselves — that table
                // records what REMOTE peers have confirmed of our commits — so saying
                // "not directly connected" here would be nonsense.
                node.isLocal -> {
                    Text(
                        text = "This device",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Spacer(Modifier.height(2.dp))
                    Text(
                        text = "Sync progress is tracked per remote peer, not for the local device.",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                detail.isDirectlyConnected -> {
                    DetailRow(
                        "Synced to commit",
                        detail.syncedUpToLocalCommitId?.toString(),
                        missing = "nothing yet",
                    )
                    DetailRow(
                        "Last update",
                        formatLastUpdate(detail.lastUpdateReceivedTime),
                        missing = "never",
                    )
                }
                else -> {
                    Text(
                        text = "No sync session — not directly connected",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Spacer(Modifier.height(2.dp))
                    Text(
                        text = "Commit progress is only tracked for peers this device syncs with directly.",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }

            // Refocusing used to be a bare tap on an orbit peer. Tap now opens this
            // card, so the traversal lives here, labelled rather than hidden.
            if (onFocusPeer != null) {
                Spacer(Modifier.height(4.dp))
                TextButton(
                    onClick = onFocusPeer,
                    modifier = Modifier.semantics { contentDescription = "Focus this peer" },
                ) {
                    Text("Focus this peer", style = MaterialTheme.typography.labelMedium)
                }
            }
        }
    }
}

/** Label + value row. [value] of null renders [missing] in a muted style. */
@Composable
private fun DetailRow(
    label: String,
    value: String?,
    monospace: Boolean = false,
    missing: String = "—",
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 2.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.Top,
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.width(96.dp),
        )
        Text(
            text = value ?: missing,
            style = MaterialTheme.typography.labelSmall,
            fontFamily = if (monospace) FontFamily.Monospace else null,
            // onSurfaceVariant, not `outline`: outline is a divider colour and lands at
            // ~2.1:1 against this card's surface in both themes, well under the 4.5:1 AA
            // floor for 11sp text — which would make the "why this is empty" copy
            // effectively invisible, i.e. the blank it was written to prevent.
            color = if (value == null) {
                MaterialTheme.colorScheme.onSurfaceVariant
            } else {
                MaterialTheme.colorScheme.onSurface
            },
            maxLines = if (monospace) 2 else 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f),
        )
    }
}

/**
 * Metadata is shown as a key count, never as the raw document. The SDK caps each
 * metadata object at 4 KB, which no card can hold, and rendering it inline would make
 * the card's height depend on the peer.
 */
private fun metadataSummary(keyCount: Int, raw: String?): String? = when {
    keyCount > 0 -> if (keyCount == 1) "1 key" else "$keyCount keys"
    // An empty SDK object stringifies to "{}" — non-blank but carrying nothing. Treating
    // that as "present" labelled every peer that never set metadata as having some.
    !raw.isNullOrBlank() && raw.trim() != "{}" -> "present"
    else -> null
}

private fun formatLastUpdate(epochMillis: Double?): String? {
    val ms = epochMillis?.toLong() ?: return null
    if (ms <= 0L) return null
    val diff = System.currentTimeMillis() - ms
    return when {
        diff < 0L -> SimpleDateFormat("MMM d, h:mm a", Locale.getDefault()).format(Date(ms))
        diff < 60_000L -> "Just now"
        diff < 3_600_000L -> "${diff / 60_000} min ago"
        diff < 86_400_000L -> "${diff / 3_600_000} hr ago"
        else -> SimpleDateFormat("MMM d, h:mm a", Locale.getDefault()).format(Date(ms))
    }
}
