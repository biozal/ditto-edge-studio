package com.costoda.dittoedgestudio.ui.mainstudio.profile

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.costoda.dittoedgestudio.domain.model.QueryProfile
import com.costoda.dittoedgestudio.ui.components.DittoConnectedButtonGroup

@Composable
fun ProfileViewerView(
    profile: QueryProfile?,
    metricsEnabled: Boolean,
    lastQueryText: String,
    modifier: Modifier = Modifier,
) {
    when {
        !metricsEnabled -> CenteredMessage(
            title = "Profiling is turned off",
            subtitle = "Enable \"Capture profiling data\" in the toolbar options.",
            modifier = modifier,
        )
        profile != null -> ProfilePopulated(profile = profile, modifier = modifier)
        lastQueryText.isBlank() -> CenteredMessage(
            title = "Run a SELECT query to capture an execution profile.",
            subtitle = null,
            modifier = modifier,
        )
        !isSelectStatement(lastQueryText) -> CenteredMessage(
            title = "Profiles are only captured for SELECT statements.",
            subtitle = null,
            modifier = modifier,
        )
        else -> CenteredMessage(
            title = "Run the query to capture an execution profile.",
            subtitle = null,
            modifier = modifier,
        )
    }
}

@Composable
private fun CenteredMessage(
    title: String,
    subtitle: String?,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier.padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(title, style = MaterialTheme.typography.titleSmall)
        if (subtitle != null) {
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                text = subtitle,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun ProfilePopulated(profile: QueryProfile, modifier: Modifier = Modifier) {
    var mode by remember { mutableStateOf("Card") }
    Column(modifier = modifier.fillMaxSize()) {
        DittoConnectedButtonGroup(
            options = listOf("Card", "Plan"),
            selectedIndex = if (mode == "Card") 0 else 1,
            onSelect = { mode = if (it == 0) "Card" else "Plan" },
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
        )
        when (mode) {
            "Card" -> ProfileCardListView(profile = profile, modifier = Modifier.fillMaxSize())
            else -> ProfilePlanTreeView(plan = profile.plan, modifier = Modifier.fillMaxSize())
        }
    }
}

private fun isSelectStatement(q: String): Boolean {
    val upper = q.trimStart().uppercase()
    return upper.startsWith("SELECT ") || upper == "SELECT"
}
