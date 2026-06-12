package com.costoda.dittoedgestudio.ui.components

import androidx.compose.foundation.layout.Arrangement
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
 * Selected segment: SulfurYellow container, JetBlack content, leading checkmark, M3 shape morph.
 * Unselected segments: JetBlack container with TrafficWhite content.
 */
@OptIn(ExperimentalMaterial3ExpressiveApi::class)
@Composable
fun DittoConnectedButtonGroup(
    options: List<String>,
    selectedIndex: Int,
    onSelect: (Int) -> Unit,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier,
        horizontalArrangement = Arrangement.spacedBy(ButtonGroupDefaults.ConnectedSpaceBetween),
    ) {
        options.forEachIndexed { index, label ->
            ToggleButton(
                checked = index == selectedIndex,
                onCheckedChange = { onSelect(index) },
                shapes = when (index) {
                    0 -> ButtonGroupDefaults.connectedLeadingButtonShapes()
                    options.lastIndex -> ButtonGroupDefaults.connectedTrailingButtonShapes()
                    else -> ButtonGroupDefaults.connectedMiddleButtonShapes()
                },
                colors = ToggleButtonDefaults.toggleButtonColors(
                    containerColor = JetBlack,
                    contentColor = TrafficWhite,
                    checkedContainerColor = SulfurYellow,
                    checkedContentColor = JetBlack,
                ),
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
