package com.costoda.dittoedgestudio.ui.mainstudio.profile

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.costoda.dittoedgestudio.data.repository.ProfileTimeFormatter
import com.costoda.dittoedgestudio.domain.model.QueryProfile
import java.text.NumberFormat

/**
 * Six-cell stats strip at the top of the Profile view: ELAPSED, PARSE, PLAN,
 * RESULT COUNT, FEATUREFLAGS, QUERYTYPE — bordered cards with a small caps label
 * over a bold value, matching the VS Code extension's profile page. Cells wrap to
 * multiple rows on narrow screens via [FlowRow].
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun ProfileSummaryStrip(
    profile: QueryProfile,
    modifier: Modifier = Modifier,
) {
    FlowRow(
        modifier = modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        SummaryCard("ELAPSED", ProfileTimeFormatter.format(profile.times.elapsedNs))
        SummaryCard("PARSE", ProfileTimeFormatter.format(profile.times.parseNs))
        SummaryCard("PLAN", ProfileTimeFormatter.format(profile.times.planNs))
        SummaryCard(
            "RESULT COUNT",
            NumberFormat.getIntegerInstance().format(profile.resultCount),
        )
        SummaryCard("FEATUREFLAGS", profile.featureFlags.ifEmpty { "—" })
        SummaryCard("QUERYTYPE", profile.queryType.ifEmpty { "—" })
    }
}

@Composable
private fun SummaryCard(label: String, value: String) {
    Surface(
        shape = MaterialTheme.shapes.small,
        color = MaterialTheme.colorScheme.surfaceContainerLow,
        border = BorderStroke(0.5.dp, MaterialTheme.colorScheme.outlineVariant),
        modifier = Modifier
            .widthIn(min = 140.dp)
            .testTag("ProfileSummaryCard_$label"),
    ) {
        Column(modifier = Modifier.padding(10.dp)) {
            Text(
                text = label,
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Text(
                text = value,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
                modifier = Modifier.padding(top = 2.dp),
            )
        }
    }
}
