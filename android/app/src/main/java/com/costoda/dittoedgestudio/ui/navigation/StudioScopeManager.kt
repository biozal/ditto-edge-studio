package com.costoda.dittoedgestudio.ui.navigation

import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.remember
import androidx.navigation3.runtime.NavKey
import com.costoda.dittoedgestudio.data.session.StudioSession
import org.koin.compose.getKoin
import org.koin.core.qualifier.named

/**
 * Back-stack-derived ownership for the Koin "studio" scopes.
 *
 * The studio shell is a set of sibling rail-section entries ([StudioSectionKey]) plus
 * compact-width drill-in detail entries — no single entry outlives the studio. This composable
 * watches [backStack] and, for every databaseId that has at least one studio entry on the
 * stack, keeps the Koin scope identified by [StudioSession.scopeId] open.
 *
 * When the back stack no longer contains any studio entry for a given databaseId — i.e. the user
 * popped back out of the studio entirely — the scope is closed, which fires
 * `onClose { it?.close() }` in `DataModule` and tears down the [StudioSession].
 *
 * Rail switching never closes the scope (the new top entry still references the same
 * databaseId); only fully leaving the studio does.
 */
@Composable
fun StudioScopeManager(backStack: List<NavKey>) {
    val koin = getKoin()
    // Snapshot-aware derivation: recomputes whenever the back stack mutates.
    val activeIds by remember(backStack) {
        derivedStateOf { activeStudioDatabaseIds(backStack) }
    }

    // For each currently-active databaseId, ensure the scope exists. A keyed DisposableEffect
    // closes the scope when its key (the databaseId) leaves [activeIds] for good — Compose
    // leaves the keyed block out of recomposition when it disappears from the iteration, which
    // triggers `onDispose`. The dispose call closes the scope; StudioSession.close() is
    // idempotent and guarded by an AtomicBoolean inside the session.
    activeIds.forEach { databaseId ->
        key(databaseId) {
            DisposableEffect(databaseId) {
                val scopeId = StudioSession.scopeId(databaseId)
                val scope = koin.getOrCreateScope(scopeId, named(StudioSession.SCOPE_QUALIFIER))
                onDispose { scope.close() }
            }
        }
    }
}

/**
 * Pure function (unit-testable) that extracts the set of databaseIds for which a Koin studio
 * scope must be alive, given the current back stack. A scope is required if the stack contains:
 *  - any [StudioSectionKey] for that databaseId, or
 *  - any [StudioChildKey] for that databaseId (compact-width drill-in detail keys).
 *
 * Iteration order is deterministic (insertion order of the resulting [LinkedHashSet]) so tests
 * can assert against a stable sequence.
 */
fun activeStudioDatabaseIds(backStack: List<NavKey>): Set<Long> {
    val out = LinkedHashSet<Long>()
    for (k in backStack) {
        when (k) {
            is StudioSectionKey -> out += k.databaseId
            is StudioChildKey -> out += k.databaseId
            else -> Unit
        }
    }
    return out
}
