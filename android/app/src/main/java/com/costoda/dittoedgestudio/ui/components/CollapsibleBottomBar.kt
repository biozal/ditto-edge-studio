package com.costoda.dittoedgestudio.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.KeyboardDoubleArrowLeft
import androidx.compose.material.icons.filled.KeyboardDoubleArrowRight
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp

/**
 * Floating bottom-bar chrome with collapse/expand, mirroring the SwiftUI
 * `DetailBottomBar`: the bar floats over detail content, so the user can fold it
 * away (e.g. while reading the Profile tab) via a collapse chevron at the trailing
 * edge, and bring it back via a small pill with an expand chevron.
 */
@Composable
fun CollapsibleBottomBar(
    modifier: Modifier = Modifier,
    content: @Composable RowScope.() -> Unit,
) {
    var isCollapsed by remember { mutableStateOf(false) }

    if (isCollapsed) {
        Row(
            modifier = modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.End,
        ) {
            Surface(
                shape = MaterialTheme.shapes.extraLarge,
                color = MaterialTheme.colorScheme.surfaceContainerHigh.copy(alpha = 0.92f),
                tonalElevation = 3.dp,
                shadowElevation = 4.dp,
            ) {
                IconButton(
                    onClick = { isCollapsed = false },
                    modifier = Modifier.testTag("ExpandBottomBar"),
                ) {
                    Icon(
                        imageVector = Icons.Filled.KeyboardDoubleArrowLeft,
                        contentDescription = "Expand toolbar",
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
        return
    }

    Surface(
        modifier = modifier,
        shape = MaterialTheme.shapes.extraLarge,
        color = MaterialTheme.colorScheme.surfaceContainerHigh.copy(alpha = 0.92f),
        tonalElevation = 3.dp,
        shadowElevation = 4.dp,
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 4.dp, vertical = 2.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(2.dp),
        ) {
            content()
            IconButton(
                onClick = { isCollapsed = true },
                modifier = Modifier.testTag("CollapseBottomBar"),
            ) {
                Icon(
                    imageVector = Icons.Filled.KeyboardDoubleArrowRight,
                    contentDescription = "Collapse toolbar",
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}
