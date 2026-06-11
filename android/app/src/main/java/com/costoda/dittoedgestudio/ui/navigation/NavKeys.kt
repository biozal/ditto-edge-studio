package com.costoda.dittoedgestudio.ui.navigation

import androidx.navigation3.runtime.NavKey
import kotlinx.serialization.Serializable

/**
 * Navigation 3 keys for the top-level app graph.
 *
 * Each key represents a destination consumed by [AppNavGraph]'s `NavDisplay`.
 * Keys are `@Serializable` so the back stack can be restored across configuration
 * changes via `rememberNavBackStack`.
 *
 * `id` and `databaseId` are `Long` to match the Room auto-increment primary key
 * type used by `DittoDatabase` and consumed by `DatabaseEditorScreen` /
 * `MainStudioScreen`.
 */
@Serializable
data object DatabaseListKey : NavKey

@Serializable
data class DatabaseEditorKey(val id: Long = -1L) : NavKey

@Serializable
data object QrScannerKey : NavKey

@Serializable
data class StudioKey(val databaseId: Long) : NavKey
