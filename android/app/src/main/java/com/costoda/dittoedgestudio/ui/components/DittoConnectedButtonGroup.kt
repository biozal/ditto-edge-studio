package com.costoda.dittoedgestudio.ui.components

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.ButtonGroupDefaults
import androidx.compose.material3.ExperimentalMaterial3ExpressiveApi
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.ToggleButton
import androidx.compose.material3.ToggleButtonDefaults
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import com.costoda.dittoedgestudio.ui.theme.JetBlack
import com.costoda.dittoedgestudio.ui.theme.SulfurYellow
import com.costoda.dittoedgestudio.ui.theme.TrafficWhite

/**
 * Brand-styled M3 Expressive **connected button group** (single-select) — the current
 * Material 3 replacement for segmented buttons
 * (https://m3.material.io/components/button-groups/guidelines), and the Android counterpart
 * of the segmented controls used in the SwiftUI app and the VS Code plugin.
 *
 * Selected segment (dark mode): SulfurYellow container, JetBlack content, leading checkmark,
 * M3 shape morph. Unselected segments: JetBlack container with TrafficWhite content.
 * In light mode the group uses the Material 3 default colours — see [dittoToggleButtonColors].
 */
@OptIn(ExperimentalMaterial3ExpressiveApi::class)
@Composable
fun DittoConnectedButtonGroup(
    options: List<String>,
    selectedIndex: Int,
    onSelect: (Int) -> Unit,
    modifier: Modifier = Modifier,
) {
    // IntrinsicSize.Max + equal weights: every segment gets the width of the WIDEST
    // label — uniform like a segmented control — while the group wraps its content
    // instead of stretching to fill the row.
    Row(
        modifier = modifier.width(IntrinsicSize.Max),
        horizontalArrangement = Arrangement.spacedBy(ButtonGroupDefaults.ConnectedSpaceBetween),
    ) {
        options.forEachIndexed { index, label ->
            ToggleButton(
                checked = index == selectedIndex,
                onCheckedChange = { onSelect(index) },
                modifier = Modifier.weight(1f),
                shapes = when (index) {
                    0 -> ButtonGroupDefaults.connectedLeadingButtonShapes()
                    options.lastIndex -> ButtonGroupDefaults.connectedTrailingButtonShapes()
                    else -> ButtonGroupDefaults.connectedMiddleButtonShapes()
                },
                colors = dittoToggleButtonColors(),
            ) {
                if (index == selectedIndex) {
                    Icon(
                        imageVector = Icons.Filled.Check,
                        contentDescription = null,
                        modifier = Modifier.size(ToggleButtonDefaults.IconSize),
                    )
                    Spacer(Modifier.width(ToggleButtonDefaults.IconSpacing))
                }
                Text(label)
            }
        }
    }
}

/**
 * Icon-only variant of [DittoConnectedButtonGroup] for narrow spaces (e.g. the 300-400dp
 * inspector column).  Each segment shows a single icon; selection is communicated by the
 * SulfurYellow container + M3 shape morph alone — no checkmark overlay is added, as placing
 * two icons in one segment adds visual noise.
 *
 * @param icons              One [ImageVector] per segment; must be the same size as
 *                           [contentDescriptions].
 * @param contentDescriptions Accessibility label for each icon (used as the node's content
 *                           description in UI tests via [onNodeWithContentDescription]).
 * @param selectedIndex      Zero-based index of the currently selected segment.
 * @param onSelect           Callback invoked with the tapped segment index.
 */
@OptIn(ExperimentalMaterial3ExpressiveApi::class)
@Composable
fun DittoConnectedIconButtonGroup(
    icons: List<ImageVector>,
    contentDescriptions: List<String>,
    selectedIndex: Int,
    onSelect: (Int) -> Unit,
    modifier: Modifier = Modifier,
) {
    require(icons.size == contentDescriptions.size) {
        "icons and contentDescriptions must have the same size"
    }
    Row(
        modifier = modifier.width(IntrinsicSize.Max),
        horizontalArrangement = Arrangement.spacedBy(ButtonGroupDefaults.ConnectedSpaceBetween),
    ) {
        icons.forEachIndexed { index, icon ->
            ToggleButton(
                checked = index == selectedIndex,
                onCheckedChange = { onSelect(index) },
                modifier = Modifier.weight(1f),
                shapes = when (index) {
                    0 -> ButtonGroupDefaults.connectedLeadingButtonShapes()
                    icons.lastIndex -> ButtonGroupDefaults.connectedTrailingButtonShapes()
                    else -> ButtonGroupDefaults.connectedMiddleButtonShapes()
                },
                colors = dittoToggleButtonColors(),
            ) {
                Icon(
                    imageVector = icon,
                    contentDescription = contentDescriptions[index],
                    modifier = Modifier.size(ToggleButtonDefaults.IconSize),
                )
            }
        }
    }
}

/**
 * Segment colours for the connected button groups.
 *
 * The brand palette is applied **only in dark mode**. SulfurYellow reads as a
 * bright accent against dark chrome, but in light mode a yellow fill with black
 * text — sitting next to JetBlack *unselected* segments on a light surface — is
 * heavy and muddy, and looks nothing like the rest of the system UI. In light
 * mode the group therefore falls back to the Material 3 defaults, so it matches
 * whatever colour scheme the app is already using.
 *
 * Mirrors `DittoSegmentedPicker` in the SwiftUI app, which makes the same
 * dark-only choice for the same reason.
 */
@OptIn(ExperimentalMaterial3ExpressiveApi::class)
@Composable
private fun dittoToggleButtonColors() = if (isSystemInDarkTheme()) {
    ToggleButtonDefaults.toggleButtonColors(
        containerColor = JetBlack,
        contentColor = TrafficWhite,
        checkedContainerColor = SulfurYellow,
        checkedContentColor = JetBlack,
    )
} else {
    ToggleButtonDefaults.toggleButtonColors()
}
