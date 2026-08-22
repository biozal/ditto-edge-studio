import Foundation
import Observation

/// The single source of truth for "is sync running right now".
///
/// Before this existed, `SyncStatusViewModel.isSyncEnabled` was a stored `Bool` that
/// defaulted to `true` "because hydration starts sync" and was written only by
/// `toggleSync` and `reset`. That made it a *guess*, and three production paths falsified
/// it without it noticing:
///
/// 1. `TransportConfigView.applyTransportConfig` stops sync, applies transports, then
///    restarts. When the restart throws — which it can, because sync scopes are
///    fail-closed — sync is off while the indicator still reads green. The user's first
///    recovery tap then takes the *stop* branch (a no-op on already-stopped sync), so it
///    takes two taps to restart.
/// 2. `DittoManager.resetSystemSettingsToDefaults` stops sync and, on failure,
///    deliberately leaves it stopped — without telling the UI.
/// 3. `selectedDatabaseStartSync` used to return silently when no config was selected,
///    after which `toggleSync` set the flag to `true` anyway. That half is now closed at
///    the source too — it throws (S6) — so this hazard is history, kept here because it is
///    why the *derivation* is the right shape rather than two patched call sites.
///
/// Deriving the value from the only two functions that actually start or stop sync
/// removes the guess. Everything that renders sync state reads this.
///
/// **Scope caveat, deliberate.** This is one process-wide flag, so it describes "the
/// session", not "a particular `Ditto` instance". On the abort paths (`hydrate`'s
/// post-condition and the two added in Phase 4) the *losing* instance is stopped, and
/// publishing `false` there can contradict a winning instance that is still syncing —
/// reachable only via iPad multi-window concurrent opens. That is strictly narrower than
/// the hard-coded `true` it replaces; per-instance state would need an identity the view
/// layer does not have. Recorded as a known limitation rather than papered over.
@MainActor
@Observable
final class SyncRuntimeState {
    /// Process-wide instance used by production code. Tests inject their own.
    static let shared = SyncRuntimeState()

    /// Whether `sync.start()` has succeeded more recently than any `sync.stop()`.
    ///
    /// `private(set)` on purpose: the only legitimate writers are the two funnels in
    /// `DittoManager`, which call `setRunning(_:)` immediately after the SDK call they
    /// wrap actually returns. A view that could write this would reintroduce the guess.
    private(set) var isRunning = false

    init(isRunning: Bool = false) {
        self.isRunning = isRunning
    }

    /// Records the outcome of a real `sync.start()` / `sync.stop()`.
    ///
    /// Call **after** the SDK call returns, never before: publishing optimistically is how
    /// the flag came to disagree with reality in the first place.
    func setRunning(_ running: Bool) {
        guard isRunning != running else { return }
        isRunning = running
        Log.info("[Sync] Runtime state → \(running ? "running" : "stopped")")
    }
}
