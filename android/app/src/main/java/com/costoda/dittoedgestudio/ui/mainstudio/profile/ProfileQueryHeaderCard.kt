package com.costoda.dittoedgestudio.ui.mainstudio.profile

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.costoda.dittoedgestudio.domain.model.QueryProfile
import java.time.Instant

/**
 * Profile header, matched to the VS Code extension's profile page: a bold title on
 * the left, the dimmed `captured <ISO8601>` timestamp on the right, and the query
 * text below — syntax-highlighted, with no enclosing box.
 *
 * The query text has the PROFILE prefix stripped — users want to see what they
 * typed, not what we sent to Ditto.
 */
@Composable
fun ProfileQueryHeaderCard(
    profile: QueryProfile,
    modifier: Modifier = Modifier,
) {
    val displayText = profile.text
        .let { raw ->
            if (raw.trimStart().uppercase().startsWith("PROFILE ")) {
                raw.trimStart().drop("PROFILE ".length)
            } else {
                raw
            }
        }
        .trim()

    Column(modifier = modifier.fillMaxWidth().testTag("ProfileQueryHeader")) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.fillMaxWidth(),
        ) {
            Text(
                text = "Execution Profile",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
            )
            Spacer(modifier = Modifier.weight(1f))
            Text(
                text = "captured ${Instant.ofEpochMilli(profile.capturedAtMs)}",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        Spacer(modifier = Modifier.padding(top = 8.dp))
        SelectionContainer {
            Text(
                text = DqlProfileHighlighter.highlight(
                    displayText,
                    keywordColor = ProfileSyntaxColors.keyword,
                    stringColor = ProfileSyntaxColors.string,
                ),
                style = MaterialTheme.typography.bodyMedium,
                fontFamily = FontFamily.Monospace,
                modifier = Modifier.testTag("ProfileQueryText"),
            )
        }
    }
}
