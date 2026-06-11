package com.costoda.dittoedgestudio.ui.navigation

import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.remember
import androidx.lifecycle.viewmodel.navigation3.rememberViewModelStoreNavEntryDecorator
import androidx.navigation3.runtime.entryProvider
import androidx.navigation3.runtime.rememberNavBackStack
import androidx.navigation3.runtime.rememberSaveableStateHolderNavEntryDecorator
import androidx.navigation3.ui.NavDisplay
import com.costoda.dittoedgestudio.data.session.StudioSession
import com.costoda.dittoedgestudio.ui.database.DatabaseEditorScreen
import com.costoda.dittoedgestudio.ui.database.DatabaseListScreen
import com.costoda.dittoedgestudio.ui.mainstudio.MainStudioScreen
import com.costoda.dittoedgestudio.ui.qrcode.QrScannerScreen
import org.koin.compose.getKoin
import org.koin.core.parameter.parametersOf
import org.koin.core.qualifier.named

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
 * The root entry is never popped — emptying the back stack would leave
 * NavDisplay rendering nothing instead of letting the system finish the activity.
 */
@Composable
fun AppNavGraph() {
    val backStack = rememberNavBackStack(DatabaseListKey)

    NavDisplay(
        backStack = backStack,
        onBack = { if (backStack.size > 1) backStack.removeLastOrNull() },
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
                // Resolve / create the per-database Koin "studio" scope. The scope owns the
                // StudioSession (Ditto instance, sync handles, observer handles, etc.) and
                // survives navigation between sibling rail-section entries (Task 4.x).
                //
                // Lifecycle: the DisposableEffect below ties the scope's close() to this
                // entry leaving composition for good. When the StudioKey is popped from the
                // back stack, the Nav3 ViewModelStore decorator first clears the entry's
                // ViewModels (MainStudioViewModel etc.), and then this DisposableEffect
                // disposes — closing the scope, which fires `onClose { it?.close() }` in
                // DataModule, which calls StudioSession.close() exactly once (guarded by an
                // AtomicBoolean inside the session).
                //
                // Caveats:
                //  - Activity recreation / config changes also dispose+recreate, so the
                //    session is rebuilt. Acceptable for now; documented as a known cost.
                //  - Process death tears everything down anyway.
                val koin = getKoin()
                val scopeId = remember(key.databaseId) { StudioSession.scopeId(key.databaseId) }
                val scope = remember(scopeId) {
                    koin.getOrCreateScope(scopeId, named(StudioSession.SCOPE_QUALIFIER))
                }
                val session = remember(scope, key.databaseId) {
                    scope.get<StudioSession> { parametersOf(key.databaseId) }
                }
                DisposableEffect(scopeId) {
                    onDispose { scope.close() }
                }

                MainStudioScreen(
                    databaseId = key.databaseId,
                    session = session,
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
