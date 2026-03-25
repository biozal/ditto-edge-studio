package com.costoda.dittoedgestudio.ui.mainstudio.inspector

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import org.json.JSONObject

@Composable
fun QueryJsonInspector(
    selectedDocument: Map<String, Any?>?,
    modifier: Modifier = Modifier,
) {
    if (selectedDocument == null) {
        Box(modifier = modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            Text(
                text = "Select a result to inspect",
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                style = MaterialTheme.typography.bodySmall,
            )
        }
        return
    }

    val jsonString = remember(selectedDocument) {
        runCatching {
            JSONObject(selectedDocument as Map<*, *>).toString(2)
        }.getOrElse {
            selectedDocument.entries.joinToString(",\n") { (k, v) -> "  \"$k\": $v" }
                .let { "{\n$it\n}" }
        }
    }

    SelectionContainer(modifier = modifier.fillMaxSize()) {
        Text(
            text = jsonString,
            style = MaterialTheme.typography.bodySmall.copy(
                fontFamily = FontFamily.Monospace,
                fontSize = 11.sp,
            ),
            modifier = Modifier
                .verticalScroll(rememberScrollState())
                .padding(12.dp),
        )
    }
}
