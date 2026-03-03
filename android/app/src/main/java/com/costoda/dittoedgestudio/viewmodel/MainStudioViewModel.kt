package com.costoda.dittoedgestudio.viewmodel

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ManageSearch
import androidx.compose.material.icons.outlined.Description
import androidx.compose.material.icons.outlined.Memory
import androidx.compose.material.icons.outlined.Storage
import androidx.compose.material.icons.outlined.Sync
import androidx.compose.material.icons.outlined.Visibility
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.lifecycle.ViewModel

enum class StudioNavItem(val label: String, val icon: ImageVector) {
    SUBSCRIPTIONS("Subscriptions", Icons.Outlined.Sync),
    QUERY("Query", Icons.Outlined.Storage),
    OBSERVERS("Observers", Icons.Outlined.Visibility),
    LOGGING("Logging", Icons.Outlined.Description),
    APP_METRICS("App Metrics", Icons.Outlined.Memory),
    QUERY_METRICS("Query Metrics", Icons.AutoMirrored.Outlined.ManageSearch),
}

class MainStudioViewModel(private val databaseId: Long) : ViewModel() {
    var selectedNavItem by mutableStateOf(StudioNavItem.SUBSCRIPTIONS)
    var dataPanelVisible by mutableStateOf(true)
    var inspectorVisible by mutableStateOf(false)
    var syncEnabled by mutableStateOf(false)
    var bottomBarExpanded by mutableStateOf(true)
    var transportConfigVisible by mutableStateOf(false)
    var fabMenuExpanded by mutableStateOf(false)
    var connectionPopupVisible by mutableStateOf(false)
}
