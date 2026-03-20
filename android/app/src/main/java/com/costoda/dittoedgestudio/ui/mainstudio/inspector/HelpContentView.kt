package com.costoda.dittoedgestudio.ui.mainstudio.inspector

import android.text.method.LinkMovementMethod
import android.view.ViewGroup
import android.widget.TextView
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.widget.NestedScrollView
import io.noties.markwon.Markwon
import io.noties.markwon.ext.tables.TablePlugin
import io.noties.markwon.html.HtmlPlugin
import io.noties.markwon.linkify.LinkifyPlugin
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Renders a help markdown file from assets/help/{assetFileName} using Markwon.
 *
 * Supports: headings, bold/italic, code blocks, tables, links, lists.
 * Links open in the system browser via LinkifyPlugin.
 *
 * Scroll is handled by NestedScrollView (implements NestedScrollingChild3) so that
 * touch events participate correctly in Compose's nested scroll protocol. A plain
 * TextView with LinkMovementMethod has no scroll container and absorbs all touch
 * events, producing no visible scroll movement.
 */
@Composable
fun HelpContentView(
    assetFileName: String,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current

    var markdown by remember { mutableStateOf("") }
    LaunchedEffect(assetFileName) {
        markdown = withContext(Dispatchers.IO) {
            runCatching {
                context.assets.open("help/$assetFileName").bufferedReader().readText()
            }.getOrDefault("# Help\n\nDocumentation not found.")
        }
    }

    val markwon = remember {
        Markwon.builder(context)
            .usePlugin(HtmlPlugin.create())
            .usePlugin(TablePlugin.create(context))
            .usePlugin(LinkifyPlugin.create())
            .build()
    }

    AndroidView(
        modifier = modifier.fillMaxSize(),
        factory = { ctx ->
            val p = (16 * ctx.resources.displayMetrics.density).toInt()
            val tv = TextView(ctx).apply {
                movementMethod = LinkMovementMethod.getInstance()
                setTextIsSelectable(true)
                setPadding(p, p, p, p)
            }
            NestedScrollView(ctx).apply {
                addView(tv, ViewGroup.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                ))
            }
        },
        update = { sv ->
            val tv = sv.getChildAt(0) as TextView
            markwon.setMarkdown(tv, markdown)
        },
    )
}
