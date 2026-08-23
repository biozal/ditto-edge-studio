package com.costoda.dittoedgestudio.ui.mainstudio.profile

import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontFamily
import com.costoda.dittoedgestudio.domain.model.QueryProfile

/**
 * Subtle footer below the plan: profile UUID, app ID, state — matching the VS Code
 * profile page's trailing strip. Selectable so a user copying these into a bug
 * report doesn't need to retype the GUIDs.
 */
@Composable
fun ProfileFooterStrip(
    profile: QueryProfile,
    modifier: Modifier = Modifier,
) {
    SelectionContainer {
        Text(
            text = "profile: ${profile.id.ifEmpty { "—" }}" +
                " · db: ${profile.appId.ifEmpty { "—" }}" +
                " · state: ${profile.state.ifEmpty { "—" }}",
            style = MaterialTheme.typography.labelSmall,
            fontFamily = FontFamily.Monospace,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = modifier.fillMaxWidth().testTag("ProfileFooter"),
        )
    }
}
