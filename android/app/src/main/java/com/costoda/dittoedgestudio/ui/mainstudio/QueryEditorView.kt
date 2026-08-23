package com.costoda.dittoedgestudio.ui.mainstudio

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.isCtrlPressed
import androidx.compose.ui.input.key.isMetaPressed
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * DQL query text editor.
 *
 * @param onRunQuery When non-null, Ctrl+Enter (and Cmd+Enter) triggers this callback to
 *   execute the current query. Pass null (or omit) to disable the shortcut — the caller
 *   is responsible for disabling it while a query is already executing.
 */
@Composable
fun QueryEditorView(
    queryText: String,
    onQueryTextChange: (String) -> Unit,
    modifier: Modifier = Modifier,
    onRunQuery: (() -> Unit)? = null,
) {
    val highlighter = remember { DqlSyntaxHighlighter() }

    // Ctrl+Enter / Cmd+Enter shortcut modifier — only attached when a run callback is
    // provided (i.e. the query is not currently executing).
    val keyEventModifier = if (onRunQuery != null) {
        Modifier.onPreviewKeyEvent { event ->
            if (event.type == KeyEventType.KeyDown &&
                event.key == Key.Enter &&
                (event.isCtrlPressed || event.isMetaPressed)
            ) {
                onRunQuery()
                true
            } else {
                false
            }
        }
    } else {
        Modifier
    }

    Box(
        modifier = modifier
            .fillMaxSize()
            .padding(horizontal = 12.dp, vertical = 8.dp)
            .then(keyEventModifier),
    ) {
        if (queryText.isEmpty()) {
            Text(
                text = "Enter DQL query…",
                style = TextStyle(
                    fontFamily = FontFamily.Monospace,
                    fontSize = 13.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f),
                ),
            )
        }
        BasicTextField(
            value = queryText,
            onValueChange = onQueryTextChange,
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState()),
            textStyle = TextStyle(
                fontFamily = FontFamily.Monospace,
                fontSize = 13.sp,
                color = MaterialTheme.colorScheme.onSurface,
            ),
            cursorBrush = SolidColor(MaterialTheme.colorScheme.primary),
            visualTransformation = highlighter,
        )
    }
}
