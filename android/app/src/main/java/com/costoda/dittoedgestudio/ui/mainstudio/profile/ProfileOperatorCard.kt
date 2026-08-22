package com.costoda.dittoedgestudio.ui.mainstudio.profile

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.costoda.dittoedgestudio.domain.model.QueryProfileOperator

/**
 * One operator in the execution plan — matched to the VS Code extension's profile
 * page: bold monospaced name followed by the solid stat chips, then dimmed-key /
 * bold-value attribute rows. Values that are JSON documents (e.g. `descriptor`)
 * render as a syntax-highlighted code block.
 *
 * Children are NOT drawn here — [ProfileCardListView] handles recursion.
 */
@Composable
fun ProfileOperatorCard(
    operator: QueryProfileOperator,
    modifier: Modifier = Modifier,
) {
    Surface(
        modifier = modifier.fillMaxWidth().testTag("ProfileOperatorCard_${operator.name}"),
        shape = RoundedCornerShape(8.dp),
        color = MaterialTheme.colorScheme.surfaceContainerLow,
        border = BorderStroke(0.5.dp, MaterialTheme.colorScheme.outlineVariant),
    ) {
        Column(modifier = Modifier.padding(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    text = operator.name,
                    style = MaterialTheme.typography.bodyLarge,
                    fontWeight = FontWeight.Bold,
                    fontFamily = FontFamily.Monospace,
                )
                if (operator.stats != null) {
                    Spacer(modifier = Modifier.width(10.dp))
                    ProfileStatsBadges(stats = operator.stats)
                }
            }

            if (operator.attributes.isNotEmpty()) {
                Spacer(modifier = Modifier.height(8.dp))
                Column(modifier = Modifier.fillMaxWidth().padding(start = 4.dp)) {
                    operator.attributes.forEach { (key, value) ->
                        AttributeRow(key = key, value = value)
                    }
                }
            }
        }
    }
}

@Composable
private fun AttributeRow(
    key: String,
    value: String,
    modifier: Modifier = Modifier,
) {
    Row(modifier = modifier.padding(vertical = 1.dp)) {
        Text(
            text = key,
            style = MaterialTheme.typography.labelSmall,
            fontFamily = FontFamily.Monospace,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.width(110.dp),
        )
        val json = prettyPrintedJson(value)
        if (json != null) {
            Surface(
                shape = RoundedCornerShape(6.dp),
                color = MaterialTheme.colorScheme.surfaceContainerHighest,
                modifier = Modifier.padding(top = 2.dp),
            ) {
                SelectionContainer {
                    Text(
                        text = JsonProfileHighlighter.highlight(
                            json,
                            keywordColor = ProfileSyntaxColors.keyword,
                            stringColor = ProfileSyntaxColors.string,
                        ),
                        style = MaterialTheme.typography.labelSmall,
                        fontFamily = FontFamily.Monospace,
                        modifier = Modifier.padding(8.dp),
                    )
                }
            }
        } else {
            SelectionContainer {
                Text(
                    text = value,
                    style = MaterialTheme.typography.labelSmall,
                    fontWeight = FontWeight.Bold,
                    fontFamily = FontFamily.Monospace,
                )
            }
        }
    }
}
