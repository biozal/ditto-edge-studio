import DittoSwift
import Foundation

/// Minimal DQL execution surface, so the advanced-settings apply logic can be tested
/// with a recording fake instead of a live Ditto instance.
protocol DQLExecuting: Sendable {
    /// Runs `query` and returns each result item's value dictionary.
    @discardableResult
    func runDQL(_ query: String, arguments: [String: Any?]) async throws -> [[String: Any?]]
}

extension Ditto: DQLExecuting {
    @discardableResult
    func runDQL(_ query: String, arguments: [String: Any?]) async throws -> [[String: Any?]] {
        let result = arguments.isEmpty
            ? try await store.execute(query: query)
            : try await store.execute(query: query, arguments: arguments)
        return result.items.map(\.value)
    }
}

/// Applies a database's Advanced Configuration to an open Ditto instance.
///
/// Split out of `DittoManager` for two reasons: the statement order relative to
/// `sync.start()` is safety-critical and needs a unit test that doesn't require
/// credentials, and the two lists need **opposite failure policies**:
///
/// - **Startup settings** are tuning knobs → best-effort. One bad parameter name is
///   reported, not fatal.
/// - **Sync scopes** are a data-containment control → fail-closed. If they cannot be
///   applied and verified, the caller must not start sync, because "scope missing"
///   means data the user marked device-local would replicate.
struct AdvancedSettingsApplier: Sendable {
    let executor: any DQLExecuting

    enum ApplyError: LocalizedError {
        case scopeStatementFailed(collections: [String], underlying: String)
        case scopeVerificationMismatch(expected: [String: String], actual: [String: String])
        case invalidScopes(String)

        var errorDescription: String? {
            switch self {
            case let .scopeStatementFailed(collections, underlying):
                return "Could not apply collection sync scopes for \(collections.joined(separator: ", ")). " +
                    "The database was not opened, to avoid syncing data you marked device-local. (\(underlying))"
            case let .scopeVerificationMismatch(expected, actual):
                return "Collection sync scopes were not stored as requested " +
                    "(expected \(expected), found \(actual)). The database was not opened, " +
                    "to avoid syncing data you marked device-local."
            case let .invalidScopes(detail):
                return "Collection sync scopes are invalid: \(detail). The database was not opened."
            }
        }
    }

    // MARK: - Startup Settings (best-effort)

    /// Applies each startup setting independently. A failure is recorded and skipped
    /// rather than aborting: an unrecognized parameter name is a typo, not a reason to
    /// lock the user out of their database.
    func applyStartupSettings(_ settings: [StartupSetting]) async -> AdvancedApplyResult {
        var result = AdvancedApplyResult()
        guard !settings.isEmpty else { return result }

        // Whole-list validation, not per-row: `validateSetting(_:others: [])` cannot see
        // duplicates, and the row cap was only ever enforced in the editor — so a
        // QR-imported or hand-edited config could issue thousands of statements, or two
        // conflicting writes to one parameter, silently.
        let partitioned = AdvancedSettingsValidator.partitionSettings(settings)
        for rejection in partitioned.rejected {
            result.skippedSettings.append(
                .init(name: rejection.setting.syncKey, reason: rejection.error.message)
            )
        }

        for setting in partitioned.allowed {
            let name = setting.syncKey
            guard let typedValue = setting.typedValue else {
                result.skippedSettings.append(.init(name: name, reason: "Value could not be converted."))
                continue
            }

            do {
                try await executor.runDQL(
                    AdvancedSettingsDQL.settingStatement(for: setting),
                    arguments: ["value": typedValue.argumentValue]
                )
                result.appliedSettings.append(name)
            } catch {
                result.skippedSettings.append(.init(name: name, reason: error.localizedDescription))
            }
        }

        if result.appliedSettings.isEmpty, result.skippedSettings.isEmpty {
            Log.info("[Advanced] No startup settings to apply")
        } else {
            Log.info(
                "[Advanced] Startup settings applied=\(result.appliedSettings.count) " +
                    "skipped=\(result.skippedSettings.count)"
            )
            for skipped in result.skippedSettings {
                Log.warning("[Advanced] Skipped startup setting '\(skipped.name)': \(skipped.reason)")
            }
        }
        return result
    }

    // MARK: - Sync Scopes (fail-closed)

    /// Applies the sync scopes and verifies them by reading the parameter back.
    ///
    /// - Returns: the number of collections scoped.
    /// - Throws: if the statement fails, the scopes are invalid, or the read-back
    ///   disagrees with what was requested. The caller must not start sync on throw.
    /// - Returns: how many collections were scoped, and whether the read-back could
    ///   confirm them.
    @discardableResult
    func applySyncScopes(_ scopes: [CollectionSyncScope]) async throws -> (applied: Int, verified: Bool) {
        let map: [String: String]
        do {
            map = try AdvancedSettingsDQL.scopeMap(from: scopes)
        } catch {
            throw ApplyError.invalidScopes(String(describing: error))
        }

        // NOTE: an empty map still issues the statement. `ALTER SYSTEM` state is
        // in-memory and lives as long as the instance, so returning early on "no scopes"
        // meant deleting the last scope row never took effect — the SDK kept enforcing
        // the old `LocalPeerOnly` while the UI showed none, and the re-apply reported
        // success having sent nothing.
        do {
            try await executor.runDQL(
                AdvancedSettingsDQL.setSyncScopesQuery,
                arguments: ["scopes": map]
            )
        } catch {
            throw ApplyError.scopeStatementFailed(
                collections: map.keys.sorted(),
                underlying: error.localizedDescription
            )
        }

        // Verify. The SDK accepts the statement silently, so a read-back is the only
        // proof the containment the user asked for is actually in effect.
        switch await readSyncScopes() {
        case let .parsed(actual):
            // Subset, not equality: the instance may legitimately carry scopes this
            // config did not set (e.g. one applied by a query the user ran), and
            // demanding an exact match would refuse to open the database over it.
            for (collection, expected) in map {
                guard let found = actual[collection] else {
                    throw ApplyError.scopeVerificationMismatch(expected: map, actual: actual)
                }
                guard found == expected else {
                    throw ApplyError.scopeVerificationMismatch(expected: map, actual: actual)
                }
            }
            // Clearing case: nothing was requested, so nothing of ours may remain. A
            // leftover scope here means some other writer set it (a query the user ran),
            // which we report rather than treat as our own success.
            if map.isEmpty, !actual.isEmpty {
                Log.warning(
                    "[Advanced] Requested no sync scopes but the instance still reports " +
                        "\(actual.count): \(actual.keys.sorted().joined(separator: ", "))"
                )
                return (0, false)
            }
            Log.info("[Advanced] Sync scopes verified for \(map.count) collection(s)")
            return (map.count, true)

        case .unavailable:
            // The write succeeded; only the read-back is unusable (the SDK's `SHOW`
            // result shape for this parameter is not pinned by a live test yet). Don't
            // block the open — but never report this as verified either.
            Log.warning(
                "[Advanced] Applied \(map.count) sync scope(s) but could NOT verify them via " +
                    "'\(AdvancedSettingsDQL.showSyncScopesQuery)'. Treating as unverified."
            )
            return (map.count, false)
        }
    }

    private enum ScopeReadback {
        case parsed([String: String])
        case unavailable
    }

    /// Reads the current scope map.
    ///
    /// Deliberately does **not** fall back to `row.values.first`: on an unordered
    /// dictionary that picks an arbitrary element, which made verification succeed or
    /// fail depending on the process's hash seed — including intermittently refusing to
    /// open the database. Only known keys are consulted, and the `SHOW` statement itself
    /// is allowed to fail (some SDK builds may not support it) without bricking every
    /// database that uses scopes.
    private func readSyncScopes() async -> ScopeReadback {
        let rows: [[String: Any?]]
        do {
            rows = try await executor.runDQL(AdvancedSettingsDQL.showSyncScopesQuery, arguments: [:])
        } catch {
            Log.warning("[Advanced] Sync scope read-back query failed: \(error.localizedDescription)")
            return .unavailable
        }

        for row in rows {
            // Shape A: keyed by the parameter name (any case).
            for (key, value) in row
                where key.caseInsensitiveCompare(AdvancedSettingsDQL.syncScopesReadParameter) == .orderedSame
            {
                if let map = Self.coerceScopeMap(value) {
                    return .parsed(map)
                }
            }
            // Shape B: a name/value row, e.g. {"name": "user_collection_sync_scopes", "value": {...}}.
            if let name = row["name"].flatMap(\.self) as? String,
               name.caseInsensitiveCompare(AdvancedSettingsDQL.syncScopesReadParameter) == .orderedSame,
               let value = row["value"].flatMap(\.self),
               let map = Self.coerceScopeMap(value)
            {
                return .parsed(map)
            }
        }
        return .unavailable
    }

    /// Accepts a dictionary of strings, a loosely-typed dictionary, or a JSON string.
    private static func coerceScopeMap(_ raw: Any?) -> [String: String]? {
        guard let raw else { return nil }
        if let typed = raw as? [String: String] {
            return typed
        }
        if let loose = raw as? [String: Any] {
            var map: [String: String] = [:]
            for (key, value) in loose {
                guard let string = value as? String else { return nil }
                map[key] = string
            }
            return map
        }
        if let json = raw as? String,
           let data = json.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        {
            var map: [String: String] = [:]
            for (key, value) in object {
                guard let string = value as? String else { return nil }
                map[key] = string
            }
            return map
        }
        return nil
    }

    // MARK: - Reset

    /// The statement sequence a database open must perform, in order.
    ///
    /// Extracted from `DittoManager.hydrateDittoSelectedDatabase` so a test can observe
    /// the **real** ordering. The previous ordering test hand-wrote the sequence in its
    /// own body and asserted the order of its own lines, which meant moving
    /// `applySyncScopes` after `sync.start()` in production would have leaked
    /// `LocalPeerOnly` data with every test still green.
    ///
    /// Two invariants this type exists to guarantee:
    /// 1. The user's startup settings run **before** the app's own `ALTER SYSTEM`
    ///    statements, so app-managed parameters win.
    /// 2. Sync scopes are applied **and** `startSync` is never reached if they fail —
    ///    the SDK requires scopes before `start_sync()`, and a missing `LocalPeerOnly`
    ///    means data the user marked device-local replicates.
    struct OpenSequence: Sendable {
        let applier: AdvancedSettingsApplier
        /// Applies the peer-to-peer transport configuration (an SDK call, not DQL).
        let applyTransportConfig: @Sendable () async throws -> Void
        let isStrictModeEnabled: Bool
        /// The macOS-only mesh client cap; nil elsewhere.
        let meshMaxWlanClients: Int?
        /// Runs after every `ALTER SYSTEM` statement and before sync starts — the
        /// transport readback logging lives here so the log reflects final state.
        let beforeSync: @Sendable () async -> Void
        let startSync: @Sendable () async throws -> Void

        @discardableResult
        func run(
            startupSettings: [StartupSetting],
            syncScopes: [CollectionSyncScope]
        ) async throws -> AdvancedApplyResult {
            // 1. User settings first, so anything Edge Studio manages overrides them.
            var result = await applier.applyStartupSettings(startupSettings)

            // 2. Transports.
            try await applyTransportConfig()

            // 3-4. App-managed parameters.
            try await applier.executor.runDQL(
                "ALTER SYSTEM SET DQL_STRICT_MODE = \(isStrictModeEnabled ? "true" : "false")",
                arguments: [:]
            )
            if let meshMaxWlanClients {
                try await applier.executor.runDQL(
                    "ALTER SYSTEM SET mesh_chooser_max_wlan_clients = \(meshMaxWlanClients)",
                    arguments: [:]
                )
            }

            // 5. Sync scopes — fail-closed, so a throw here means `startSync` is never
            //    reached and the caller aborts the open.
            let scopeOutcome = try await applier.applySyncScopes(syncScopes)
            result.appliedScopeCount = scopeOutcome.applied
            result.scopesUnverified = !scopeOutcome.verified

            await beforeSync()

            // 6. Only now may sync start.
            try await startSync()
            return result
        }
    }

    /// Restores every system parameter to its SDK default.
    ///
    /// Callers must re-apply everything the app manages afterwards — transport
    /// configuration, `DQL_STRICT_MODE`, the macOS mesh setting and the sync scopes —
    /// because this resets *all* parameters, not just the user's.
    func resetAllToDefaults() async throws {
        try await executor.runDQL(AdvancedSettingsDQL.resetAllQuery, arguments: [:])
        Log.info("[Advanced] ALTER SYSTEM RESET ALL issued")
    }
}
