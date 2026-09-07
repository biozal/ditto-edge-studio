package com.costoda.dittoedgestudio.ui.mainstudio.presence

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LocalTextStyle
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp

/**
 * The Presence Viewer's peer-search box.
 *
 * Rides in the Presence tab row beside the Peers/Viewer button group so it costs the
 * canvas **no vertical space** — the whole point is finding one peer in a mesh of
 * 100+ without shrinking the graph you are trying to read. The results card is
 * rendered separately by [PresencePeerSearchResults] as an overlay, so typing never
 * reflows the row or the canvas.
 */
@Composable
fun PresencePeerSearchBar(
    query: String,
    onQueryChange: (String) -> Unit,
    onSubmit: () -> Unit,
    modifier: Modifier = Modifier,
) {
    OutlinedTextField(
        value = query,
        onValueChange = onQueryChange,
        singleLine = true,
        textStyle = LocalTextStyle.current.copy(fontSize = MaterialTheme.typography.bodySmall.fontSize),
        placeholder = {
            Text(
                text = "Search peers…",
                style = MaterialTheme.typography.bodySmall,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        },
        leadingIcon = {
            Icon(imageVector = Icons.Outlined.Search, contentDescription = null)
        },
        trailingIcon = {
            if (query.isNotEmpty()) {
                IconButton(onClick = { onQueryChange("") }) {
                    Icon(
                        imageVector = Icons.Outlined.Close,
                        contentDescription = "Clear peer search",
                    )
                }
            }
        },
        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
        // Enter/Search jumps straight to the first focusable hit — the "find a peer
        // without hunting the canvas" path.
        keyboardActions = KeyboardActions(onSearch = { onSubmit() }),
        shape = RoundedCornerShape(8.dp),
        modifier = modifier
            .widthIn(min = 120.dp)
            .semantics { contentDescription = "Search peers in the mesh" }
            .testTag("PresencePeerSearchField"),
    )
}

/**
 * The results card that drops below the search box, over the canvas.
 *
 * Only rendered while the query is active. An empty [matches] here means "no peers
 * match" — a real state, distinct from "not searching", and the graph behind this
 * card is fully dimmed to say so.
 */
@Composable
fun PresencePeerSearchResults(
    query: String,
    matches: List<PeerSearchMatch>,
    onPick: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    Surface(
        shape = RoundedCornerShape(12.dp),
        tonalElevation = 6.dp,
        shadowElevation = 8.dp,
        modifier = modifier
            .widthIn(max = 360.dp)
            .testTag("PresencePeerSearchResults"),
    ) {
        if (matches.isEmpty()) {
            Text(
                text = "No peers match \"${query.trim()}\"",
                style = MaterialTheme.typography.bodySmall,
                fontStyle = FontStyle.Italic,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp),
            )
        } else {
            LazyColumn(
                modifier = Modifier.heightIn(max = 260.dp),
                contentPadding = androidx.compose.foundation.layout.PaddingValues(vertical = 4.dp),
            ) {
                items(matches, key = { it.key }) { match ->
                    PeerSearchResultRow(match = match, onPick = onPick)
                }
            }
        }
    }
}

@Composable
private fun PeerSearchResultRow(
    match: PeerSearchMatch,
    onPick: (String) -> Unit,
) {
    val content: @Composable () -> Unit = {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 10.dp),
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = match.displayName,
                    style = MaterialTheme.typography.bodyMedium,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                if (match.isLocal) {
                    // Listed so a full-opacity "Me" makes sense while the rest of the
                    // graph dims — but the graph rejects focusing the local peer, so
                    // this row is deliberately inert rather than a dead-looking button.
                    Text(
                        text = "This device — cannot be focused",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            Text(
                text = PresencePeerSearch.truncatedKey(match.key),
                style = MaterialTheme.typography.labelSmall,
                fontFamily = FontFamily.Monospace,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
            )
        }
    }

    if (match.isLocal) {
        Box(modifier = Modifier.testTag("PresenceSearchResult_${match.key}")) { content() }
    } else {
        Surface(
            onClick = { onPick(match.key) },
            color = MaterialTheme.colorScheme.surface,
            modifier = Modifier.testTag("PresenceSearchResult_${match.key}"),
        ) {
            content()
        }
    }
}
