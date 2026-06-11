package com.costoda.dittoedgestudio.ui.navigation

import androidx.compose.runtime.Composable
import androidx.lifecycle.viewmodel.navigation3.rememberViewModelStoreNavEntryDecorator
import androidx.navigation3.runtime.entryProvider
import androidx.navigation3.runtime.rememberNavBackStack
import androidx.navigation3.runtime.rememberSaveableStateHolderNavEntryDecorator
import androidx.navigation3.ui.NavDisplay
import com.costoda.dittoedgestudio.ui.database.DatabaseEditorScreen
import com.costoda.dittoedgestudio.ui.database.DatabaseListScreen
import com.costoda.dittoedgestudio.ui.mainstudio.MainStudioScreen
import com.costoda.dittoedgestudio.ui.qrcode.QrScannerScreen

/**
 * Root navigation graph built on Navigation 3 (`NavDisplay` + `rememberNavBackStack`).
 *
 * Routes:
 *  - [DatabaseListKey]   — start destination, list of saved databases.
 *  - [DatabaseEditorKey] — create/edit a database; `id == -1L` means "new".
 *  - [QrScannerKey]      — camera-based QR code import.
 *  - [StudioKey]         — main studio for the selected database.
 *
 * Decorators applied to every entry:
 *  - `rememberSaveableStateHolderNavEntryDecorator()` — preserves Compose
 *    `rememberSaveable` state across navigation.
 *  - `rememberViewModelStoreNavEntryDecorator()` — scopes ViewModels (including
 *    Koin `koinViewModel(...)`) to the entry so they live for the lifetime of
 *    that destination on the back stack.
 *
 * System back is wired through `NavDisplay.onBack`, which pops the last entry.
 */
@Composable
fun AppNavGraph() {
    val backStack = rememberNavBackStack(DatabaseListKey)

    NavDisplay(
        backStack = backStack,
        onBack = { backStack.removeLastOrNull() },
        entryDecorators = listOf(
            rememberSaveableStateHolderNavEntryDecorator(),
            rememberViewModelStoreNavEntryDecorator(),
        ),
        entryProvider = entryProvider {
            entry<DatabaseListKey> {
                DatabaseListScreen(
                    onAddDatabase = {
                        backStack.add(DatabaseEditorKey())
                    },
                    onEditDatabase = { database ->
                        backStack.add(DatabaseEditorKey(id = database.id))
                    },
                    onOpenDatabase = { database ->
                        backStack.add(StudioKey(databaseId = database.id))
                    },
                    onScanQrCode = {
                        backStack.add(QrScannerKey)
                    },
                )
            }

            entry<DatabaseEditorKey> { key ->
                DatabaseEditorScreen(
                    databaseId = key.id,
                    onDismiss = { backStack.removeLastOrNull() },
                )
            }

            entry<StudioKey> { key ->
                MainStudioScreen(
                    databaseId = key.databaseId,
                    onBack = { backStack.removeLastOrNull() },
                )
            }

            entry<QrScannerKey> {
                QrScannerScreen(
                    onNavigateBack = { backStack.removeLastOrNull() },
                )
            }
        },
    )
}
