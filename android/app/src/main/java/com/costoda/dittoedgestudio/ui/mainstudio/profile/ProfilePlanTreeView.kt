package com.costoda.dittoedgestudio.ui.mainstudio.profile

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.costoda.dittoedgestudio.domain.model.QueryProfileOperator

/**
 * Recursive vertical tree of [PlanNodeBox]es. Each child is indented `(depth * 24).dp`
 * relative to its parent. Uses a `verticalScroll` so deep trees stay reachable.
 */
@Composable
fun ProfilePlanTreeView(plan: QueryProfileOperator, modifier: Modifier = Modifier) {
    val totalExecNs = plan.subtreeExecNs
    Column(
        modifier = modifier
            .fillMaxWidth()
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
    ) {
        TreeNode(operator = plan, totalExecNs = totalExecNs, depth = 0)
    }
}

@Composable
private fun TreeNode(
    operator: QueryProfileOperator,
    totalExecNs: Long,
    depth: Int,
) {
    PlanNodeBox(
        operator = operator,
        totalExecNs = totalExecNs,
        modifier = Modifier
            .padding(start = (depth * 24).dp, top = 4.dp, bottom = 4.dp)
            .fillMaxWidth(),
    )
    for (child in operator.children) {
        TreeNode(operator = child, totalExecNs = totalExecNs, depth = depth + 1)
    }
}
