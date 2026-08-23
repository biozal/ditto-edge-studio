package com.costoda.dittoedgestudio.ui.mainstudio.profile

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import com.costoda.dittoedgestudio.domain.model.QueryProfileOperator

/**
 * Nested-card rendering of an execution plan. Each operator becomes a
 * [ProfileOperatorCard]; children are indented behind a vertical guide line —
 * the visual idiom of the VS Code profile page's nested plan.
 *
 * This is a plain [Column], not a LazyColumn: the whole Profile view scrolls as a
 * single container (SwiftUI parity), and plans are small (tens of nodes), so lazy
 * composition buys nothing and nested scrolling would break the outer scroll.
 */
@Composable
fun ProfileCardListView(
    plan: QueryProfileOperator,
    modifier: Modifier = Modifier,
) {
    val flatPlan = flatten(plan)

    Column(
        modifier = modifier.fillMaxWidth().testTag("ProfileCardList"),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        flatPlan.forEach { (depth, op) ->
            // IntrinsicSize.Min lets the guide line stretch to the card's height.
            Row(modifier = Modifier.height(IntrinsicSize.Min)) {
                if (depth > 0) {
                    Spacer(modifier = Modifier.width((depth * 12).dp))
                    Box(
                        modifier = Modifier
                            .width(1.dp)
                            .fillMaxHeight()
                            .background(MaterialTheme.colorScheme.outlineVariant),
                    )
                    Spacer(modifier = Modifier.width(11.dp))
                }
                ProfileOperatorCard(operator = op)
            }
        }
    }
}

private fun flatten(
    op: QueryProfileOperator,
    depth: Int = 0,
): List<Pair<Int, QueryProfileOperator>> =
    listOf(depth to op) + op.children.flatMap { flatten(it, depth + 1) }
