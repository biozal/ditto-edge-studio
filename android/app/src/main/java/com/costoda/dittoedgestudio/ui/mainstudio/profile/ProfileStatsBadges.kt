package com.costoda.dittoedgestudio.ui.mainstudio.profile

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.costoda.dittoedgestudio.data.repository.ProfileTimeFormatter
import com.costoda.dittoedgestudio.domain.model.QueryProfileStats
import java.text.NumberFormat

/**
 * Horizontal strip of stat chips summarising an operator's stats block.
 *
 * Colors and chip style match the VS Code extension's profile page: solid filled
 * rounded chips with white text — `in` blue, `out` green, `exec` red, `send` dark
 * grey — while `recv` is plain text, not a chip. A chip is suppressed entirely when
 * its underlying stat is absent.
 */
@Composable
fun ProfileStatsBadges(
    stats: QueryProfileStats,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier.horizontalScroll(rememberScrollState()),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        stats.documentsIn?.let { n ->
            StatChip(label = "in:", value = n.grouped(), fill = ProfileSyntaxColors.chipIn)
        }
        stats.documentsOut?.let { n ->
            StatChip(label = "out:", value = n.grouped(), fill = ProfileSyntaxColors.chipOut)
        }
        stats.execNs?.let { ns ->
            StatChip(label = "exec", value = ProfileTimeFormatter.format(ns), fill = ProfileSyntaxColors.chipExec)
        }
        stats.recvNs?.let { ns ->
            // Plain text, matching the VS Code page — recv is waiting time, not
            // operator work, so it doesn't get a chip.
            Text(
                text = "recv ${ProfileTimeFormatter.format(ns)}",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurface,
            )
        }
        stats.sendNs?.let { ns ->
            StatChip(label = "send", value = ProfileTimeFormatter.format(ns), fill = ProfileSyntaxColors.chipSend)
        }
    }
}

/** Single solid chip — dimmed white label, bold white value, saturated fill. */
@Composable
internal fun StatChip(
    label: String,
    value: String,
    fill: Color,
    modifier: Modifier = Modifier,
) {
    Surface(
        modifier = modifier.testTag("StatChip_${label.trimEnd(':')}"),
        shape = RoundedCornerShape(5.dp),
        color = fill,
    ) {
        Row(modifier = Modifier.padding(horizontal = 8.dp, vertical = 3.dp)) {
            Text(
                text = label,
                style = MaterialTheme.typography.labelSmall,
                fontWeight = FontWeight.SemiBold,
                color = Color.White.copy(alpha = 0.85f),
            )
            Text(
                text = " $value",
                style = MaterialTheme.typography.labelSmall,
                fontWeight = FontWeight.Bold,
                color = Color.White,
            )
        }
    }
}

private fun Int.grouped(): String = NumberFormat.getIntegerInstance().format(this)
