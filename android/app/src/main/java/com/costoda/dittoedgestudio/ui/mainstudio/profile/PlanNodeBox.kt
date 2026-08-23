package com.costoda.dittoedgestudio.ui.mainstudio.profile

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.costoda.dittoedgestudio.data.repository.ProfileTimeFormatter
import com.costoda.dittoedgestudio.domain.model.QueryProfileOperator
import kotlin.math.max

/**
 * Single operator node in the plan-tree view. Renders the operator name, exec time,
 * and a percentage share badge (`execNs / totalExecNs`). Hotspot color (errorContainer)
 * when the operator's share is >= 50% of the whole plan's exec time.
 */
@Composable
fun PlanNodeBox(
    operator: QueryProfileOperator,
    totalExecNs: Long,
    modifier: Modifier = Modifier,
) {
    val ownExec = operator.stats?.execNs ?: 0L
    val share = if (totalExecNs > 0L) (ownExec * 100L) / max(totalExecNs, 1L) else 0L
    val hotspot = share >= 50L
    val containerColor = if (hotspot) {
        MaterialTheme.colorScheme.errorContainer
    } else {
        MaterialTheme.colorScheme.surfaceContainerHigh
    }
    val contentColor = if (hotspot) {
        MaterialTheme.colorScheme.onErrorContainer
    } else {
        MaterialTheme.colorScheme.onSurface
    }

    Surface(
        modifier = modifier,
        shape = RoundedCornerShape(8.dp),
        color = containerColor,
        contentColor = contentColor,
    ) {
        Column(modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    text = operator.name,
                    style = MaterialTheme.typography.titleSmall,
                    modifier = Modifier,
                )
                Spacer(modifier = Modifier.width(8.dp))
                Text(
                    text = "$share%",
                    style = MaterialTheme.typography.labelMedium,
                )
            }
            if (ownExec > 0L) {
                Text(
                    text = "exec: ${ProfileTimeFormatter.format(ownExec)}",
                    style = MaterialTheme.typography.bodySmall,
                )
            }
        }
    }
}
