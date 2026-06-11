@file:OptIn(androidx.compose.material3.adaptive.ExperimentalMaterial3AdaptiveApi::class)

package com.costoda.dittoedgestudio.ui.navigation

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.adaptive.navigation3.ListDetailSceneStrategy
import androidx.compose.material3.adaptive.navigation3.rememberListDetailSceneStrategy
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.lifecycle.viewmodel.navigation3.rememberViewModelStoreNavEntryDecorator
import androidx.navigation3.runtime.NavBackStack
import androidx.navigation3.runtime.NavKey
import androidx.navigation3.runtime.entryProvider
import androidx.navigation3.runtime.rememberNavBackStack
import androidx.navigation3.runtime.rememberSaveableStateHolderNavEntryDecorator
import androidx.navigation3.ui.NavDisplay
import com.costoda.dittoedgestudio.data.session.StudioSession
import com.costoda.dittoedgestudio.ui.database.DatabaseEditorScreen
import com.costoda.dittoedgestudio.ui.database.DatabaseListScreen
import com.costoda.dittoedgestudio.ui.mainstudio.MainStudioScreen
import com.costoda.dittoedgestudio.ui.mainstudio.ObserverEventsSection
import com.costoda.dittoedgestudio.ui.mainstudio.ObserversListSection
import com.costoda.dittoedgestudio.ui.mainstudio.StudioScaffold
import com.costoda.dittoedgestudio.ui.qrcode.QrScannerScreen
import com.costoda.dittoedgestudio.viewmodel.MainStudioViewModel
import com.costoda.dittoedgestudio.viewmodel.StudioNavItem
import org.koin.androidx.compose.koinViewModel
import org.koin.compose.getKoin
import org.koin.core.parameter.parametersOf
import org.koin.core.qualifier.named

/**
 * Root navigation graph (Navigation 3).
 *
 * Top-level keys:
 *  - [DatabaseListKey]   — start destination, list of saved databases.
 *  - [DatabaseEditorKey] — create/edit a database; `id == -1L` means "new".
 *  - [QrScannerKey]      — camera-based QR code import.
 *  - [StudioSectionKey]  — seven sibling rail-section entries (one per studio section).
 *  - [ObserverEventsKey] — detail drill-in pushed on top of [ObserversKey].
 *  - [StudioKey]         — legacy single-entry studio key, retained only for transitional
 *                          back-stack compatibility; no entry is registered for it.
 *
 * **Studio scope ownership** is handled by [StudioScopeManager] over the back stack: a Koin
 * `studio` scope (and its [StudioSession]) is kept open while any studio entry for that
 * databaseId is on the stack, and closed when all studio entries for that id leave the stack.
 * This replaces the previous per-entry `DisposableEffect` on [StudioKey] — necessary because
 * with sibling section entries no single entry outlives the studio.
 *
 * **Sections that have been migrated to the scene-driven shell:**
 *  - [ObserversKey] (list pane) + [ObserverEventsKey] (detail pane) via Material adaptive
 *    [ListDetailSceneStrategy]. Selecting an observer pushes [ObserverEventsKey]; the strategy
 *    automatically renders the two side-by-side at ≥600dp and as a normal drill-in below.
 *
 * **Sections still routed through the legacy monolith** ([MainStudioScreen]) via a bridge
 * entry each: [SubscriptionsKey], [QueryKey], [LoggingKey], [AppMetricsKey], [QueryMetricsKey],
 * [DiskUsageKey]. Each bridge entry creates / reuses the MainStudioViewModel for the database,
 * forces `selectedNavItem` to the entry's [StudioNavItem], and intercepts rail / drawer clicks
 * via the new `onNavItemSelected` callback to replace the top of the back stack with the
 * target section's key. This keeps all 7 sections functional while only Observers ships the
 * new scene treatment in this task.
 */
@Composable
fun AppNavGraph() {
    val backStack = rememberNavBackStack(DatabaseListKey)
    val listDetailStrategy = rememberListDetailSceneStrategy<NavKey>()

    // Drive the Koin scope lifecycle from the current back stack contents. Must be inside
    // the composition so the underlying derivedStateOf reads tracked snapshot state.
    StudioScopeManager(backStack)

    NavDisplay(
        backStack = backStack,
        onBack = { if (backStack.size > 1) backStack.removeLastOrNull() },
        entryDecorators = listOf(
            rememberSaveableStateHolderNavEntryDecorator(),
            rememberViewModelStoreNavEntryDecorator(),
        ),
        sceneStrategy = listDetailStrategy,
        entryProvider = entryProvider {
            entry<DatabaseListKey> {
                DatabaseListScreen(
                    onAddDatabase = { backStack.add(DatabaseEditorKey()) },
                    onEditDatabase = { db -> backStack.add(DatabaseEditorKey(id = db.id)) },
                    onOpenDatabase = { db ->
                        // Studio entry is now SubscriptionsKey — the default section.
                        backStack.add(SubscriptionsKey(databaseId = db.id))
                    },
                    onScanQrCode = { backStack.add(QrScannerKey) },
                )
            }

            entry<DatabaseEditorKey> { key ->
                DatabaseEditorScreen(
                    databaseId = key.id,
                    onDismiss = { backStack.removeLastOrNull() },
                )
            }

            entry<QrScannerKey> {
                QrScannerScreen(onNavigateBack = { backStack.removeLastOrNull() })
            }

            // ── Scene-driven section: Observers ──────────────────────────────────
            entry<ObserversKey>(
                metadata = ListDetailSceneStrategy.listPane(
                    detailPlaceholder = { ObserverEventsPlaceholder() },
                ),
            ) { key ->
                StudioSectionContainer(
                    backStack = backStack,
                    databaseId = key.databaseId,
                    section = StudioNavItem.OBSERVERS,
                ) { viewModel ->
                    ObserversListSection(
                        viewModel = viewModel,
                        onObserverPicked = { observer ->
                            // Push the detail key. At ≥600dp the ListDetailSceneStrategy
                            // composes the result as the side-by-side detail pane; below
                            // 600dp it becomes a normal drill-in. Remove any existing
                            // detail before pushing so only one detail pane exists at a time.
                            backStack.removeIf { it is ObserverEventsKey }
                            backStack.add(
                                ObserverEventsKey(
                                    databaseId = key.databaseId,
                                    observerId = observer.id,
                                ),
                            )
                        },
                    )
                }
            }

            entry<ObserverEventsKey>(
                metadata = ListDetailSceneStrategy.detailPane(),
            ) { key ->
                StudioSectionContainer(
                    backStack = backStack,
                    databaseId = key.databaseId,
                    section = StudioNavItem.OBSERVERS,
                ) { viewModel ->
                    // The observer is already selected by the list-pane's row tap (which
                    // calls viewModel.selectObserver). If we arrive here without that having
                    // happened (e.g. process restore landing on a detail key alone), the
                    // empty state from ObserverDetailScreen is surfaced.
                    ObserverEventsSection(viewModel = viewModel)
                }
            }

            // ── Legacy bridge: the other 6 rail sections ─────────────────────────
            entry<SubscriptionsKey> { key -> LegacyStudioSectionEntry(backStack, key) }
            entry<QueryKey> { key -> LegacyStudioSectionEntry(backStack, key) }
            entry<LoggingKey> { key -> LegacyStudioSectionEntry(backStack, key) }
            entry<AppMetricsKey> { key -> LegacyStudioSectionEntry(backStack, key) }
            entry<QueryMetricsKey> { key -> LegacyStudioSectionEntry(backStack, key) }
            entry<DiskUsageKey> { key -> LegacyStudioSectionEntry(backStack, key) }
        },
    )
}

/**
 * Shared container for the scene-driven Observers entries. Resolves the [StudioSession] +
 * [MainStudioViewModel] for [databaseId] and wraps content in [StudioScaffold] (so the rail
 * / drawer chrome is consistent across migrated sections).
 *
 * Forces `viewModel.selectedNavItem = section` so any session-side logic keyed on it (e.g.
 * inspector help content) keeps working until that coupling is removed in a later task.
 *
 * Section switching pushes / replaces the top of the back stack with the new section's key,
 * which both updates the visible chrome and lets [StudioScopeManager] notice we're still in
 * the studio (same databaseId).
 */
@Composable
private fun StudioSectionContainer(
    backStack: NavBackStack<NavKey>,
    databaseId: Long,
    section: StudioNavItem,
    content: @Composable (MainStudioViewModel) -> Unit,
) {
    val viewModel = rememberStudioViewModel(databaseId)
    LaunchedEffect(section) { viewModel.selectedNavItem = section }

    StudioScaffold(
        currentSection = section,
        session = viewModel.session,
        onBack = { if (backStack.size > 1) backStack.removeLastOrNull() },
        onSectionSelect = { newItem ->
            // Replace top so the new section becomes the visible entry. Always strip any
            // dangling ObserverEventsKey so leaving Observers doesn't leave a stale detail
            // pane keyed to a section we no longer show.
            backStack.removeIf { it is ObserverEventsKey }
            val newKey = newItem.toSectionKey(databaseId)
            if (backStack.isNotEmpty()) {
                backStack[backStack.lastIndex] = newKey
            } else {
                backStack.add(newKey)
            }
        },
    ) {
        content(viewModel)
    }
}

/**
 * Bridge composable for the 6 sections we have not yet migrated to the scene-driven shell.
 * Renders the legacy [MainStudioScreen] with [section]-equivalent forced selection, and
 * intercepts rail/drawer clicks so they drive the back stack instead of mutating the VM
 * directly. From the user's perspective, navigation between any two sections (migrated or
 * not) goes through the same code path: a back-stack replace-top.
 */
@Composable
private fun LegacyStudioSectionEntry(
    backStack: NavBackStack<NavKey>,
    key: StudioSectionKey,
) {
    val viewModel = rememberStudioViewModel(key.databaseId)
    LaunchedEffect(key) { viewModel.selectedNavItem = key.navItem }

    MainStudioScreen(
        databaseId = key.databaseId,
        session = viewModel.session,
        onBack = { if (backStack.size > 1) backStack.removeLastOrNull() },
        onNavItemSelected = { newItem ->
            backStack.removeIf { it is ObserverEventsKey }
            val newKey = newItem.toSectionKey(key.databaseId)
            if (backStack.isNotEmpty()) {
                backStack[backStack.lastIndex] = newKey
            } else {
                backStack.add(newKey)
            }
        },
    )
}

/**
 * Resolves the per-databaseId [StudioSession] from Koin's studio scope, then constructs the
 * per-entry [MainStudioViewModel] using `koinViewModel(parameters = ...)`. The Nav3 view-model
 * decorator scopes the VM to *this* entry, so a fresh entry for the same databaseId reuses
 * the same session (Koin scope is keyed by databaseId) but a new VM instance — exactly the
 * behaviour we want when switching between sibling section entries.
 */
@Composable
private fun rememberStudioViewModel(databaseId: Long): MainStudioViewModel {
    val koin = getKoin()
    val scopeId = remember(databaseId) { StudioSession.scopeId(databaseId) }
    val scope = remember(scopeId) {
        koin.getOrCreateScope(scopeId, named(StudioSession.SCOPE_QUALIFIER))
    }
    val session = remember(scope, databaseId) {
        scope.get<StudioSession> { parametersOf(databaseId) }
    }
    return koinViewModel(
        key = "MainStudioViewModel:$databaseId",
        parameters = { parametersOf(session) },
    )
}

/**
 * Placeholder shown by [ListDetailSceneStrategy.listPane] in the detail-pane area when no
 * observer has been selected yet (expanded widths). Mirrors the empty state in
 * [com.costoda.dittoedgestudio.ui.mainstudio.ObserverDetailScreen].
 */
@Composable
private fun ObserverEventsPlaceholder() {
    Box(
        modifier = Modifier.fillMaxSize(),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = "Select an observer to see its events",
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}
