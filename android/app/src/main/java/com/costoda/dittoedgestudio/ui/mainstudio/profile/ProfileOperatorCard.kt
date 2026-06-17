package com.costoda.dittoedgestudio.ui.mainstudio.profile

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.costoda.dittoedgestudio.domain.model.QueryProfileOperator

@Composable
fun ProfileOperatorCard(
    operator: QueryProfileOperator,
    depth: Int,
    modifier: Modifier = Modifier,
) {
    Card(
        modifier = modifier
            .fillMaxWidth()
            .padding(start = (depth * 16).dp),
    ) {
        Column(modifier = Modifier.padding(12.dp)) {
            Text(
                text = operator.name,
                style = MaterialTheme.typography.titleMedium,
            )

            if (operator.stats != null) {
                Spacer(modifier = Modifier.height(6.dp))
                ProfileStatsBadges(stats = operator.stats)
            }

            if (operator.attributes.isNotEmpty()) {
                Spacer(modifier = Modifier.height(8.dp))
                Column(modifier = Modifier.fillMaxWidth()) {
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
            text = "$key = ",
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Text(
            text = value,
            style = MaterialTheme.typography.labelSmall,
        )
    }
}
