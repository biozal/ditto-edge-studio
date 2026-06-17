package com.costoda.dittoedgestudio.ui.mainstudio.profile

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.costoda.dittoedgestudio.domain.model.QueryProfile
import com.costoda.dittoedgestudio.domain.model.QueryProfileOperator

@Composable
fun ProfileCardListView(
    profile: QueryProfile,
    modifier: Modifier = Modifier,
) {
    val flatPlan = flatten(profile.plan)

    LazyColumn(
        modifier = modifier.fillMaxSize(),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        item(key = "header") {
            ProfileQueryHeaderCard(profile = profile)
        }
        item(key = "summary") {
            ProfileSummaryStrip(times = profile.times)
        }
        items(
            items = flatPlan,
            key = { (_, op) -> op.id },
        ) { (depth, op) ->
            ProfileOperatorCard(operator = op, depth = depth)
        }
        item(key = "footer") {
            ProfileFooterStrip(profile = profile)
        }
    }
}

private fun flatten(
    op: QueryProfileOperator,
    depth: Int = 0,
): List<Pair<Int, QueryProfileOperator>> =
    listOf(depth to op) + op.children.flatMap { flatten(it, depth + 1) }
