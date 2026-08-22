# Plan: Android Advanced Database Configuration — SwiftUI Parity + Ditto 5.1.0

**Spec:** `docs/ADVANCED_DATABASE_CONFIG.md` (SwiftUI shipped feature)
**SwiftUI implementation:** `SwiftUI/EdgeStudio/Models/AdvancedDatabaseSettings.swift`,
`SwiftUI/EdgeStudio/Data/AdvancedSettingsApplier.swift`,
`SwiftUI/EdgeStudio/Views/Database/DatabaseEditorView.swift` (Advanced Configuration section)
**Priority:** High | **Complexity:** High
**Status:** Implemented — see `docs/android/advanced-database-config.md` for the
as-built wiring, divergences, and unverified items

## Goal

Port the SwiftUI "Advanced Database Configuration" feature to Android with the same
behavior and UI patterns, and move the Android Ditto SDK from `5.1.0-rc.2` to the
`5.1.0` release.

Two capabilities, both stored per database and re-applied on every open (the SDK
holds them in memory only):

1. **Collection Sync Scopes** — `ALTER SYSTEM SET USER_COLLECTION_SYNC_SCOPES = :scopes`.
   Fail-closed: applied and verified by read-back before `sync.start()`; failure aborts
   the open.
2. **Startup System Settings** — `ALTER SYSTEM SET <parameter> = :value`. Best-effort:
   a bad row is skipped and reported, the database still opens.

## Current State Assessment

| Capability | Status | Details |
|---|---|---|
| Ditto SDK 5.1.0 | **GAP** | `gradle/libs.versions.toml:4` pins `5.1.0-rc.2`; release bump is one line |
| Config storage | **GAP** | `DatabaseConfigEntity` (Room v3) has no scope/settings columns; needs v4 + migration + schema JSON |
| Apply pipeline | **GAP** | `DittoManager.hydrate()` (`data/ditto/DittoManager.kt:33-71`) goes transport config → `sync.start()` with nothing between; no `ALTER SYSTEM` anywhere in the app |
| Strict mode | **GAP (pre-existing)** | `isStrictModeEnabled` is stored/edited/QR-shared but never applied; the new open sequence fixes this (SwiftUI applies it as step 4) |
| Editor UI | **GAP** | `DatabaseEditorScreen.kt` has no Advanced section; "Developer Options" (`:258-293`) is the anchor, matching SwiftUI's section order |
| QR exclusion | **GAP** | `QrCodeEncoder.kt:43-67` / `QrCodeDecoder.kt:85-102` copy fields verbatim; new fields must be excluded on **both** sides |
| `toggleSync()` | **DIVERGENCE** | `StudioSession.toggleSync()` (`:227-240`) restarts sync without re-applying; SwiftUI re-runs the full OpenSequence on every sync start |

## Phase 0 — SDK bump to 5.1.0

- `android/gradle/libs.versions.toml:4`: `ditto = "5.1.0-rc.2"` → `"5.1.0"`.
- Re-verify the "SDK 5.0.x" comments in `data/di/DataModule.kt:123,130,162` against the
  5.1.0 release API; update if stale.
- Gate: `./gradlew assembleDebug test` green before any feature work.

## Phase 1 — Domain models + validation (pure Kotlin)

New file `domain/model/AdvancedDatabaseSettings.kt`, mirroring the SwiftUI model
semantics exactly:

- `SyncScope` enum — raw values are the DQL wire format and must never be renamed:
  `AllPeers`, `BigPeerOnly`, `SmallPeersOnly` (plural), `LocalPeerOnly`; plus
  `displayName` and `explanation` legend copy. **No tolerant parser** — unknown stored
  values fail to decode rather than coerce (containment control).
- `CollectionSyncScope` — synthetic stable `UUID` id (not the collection name; see
  SwiftUI doc comment), `collection`, `scope`, `syncKey` (trimmed). `id` excluded from
  serialization and equality.
- `StartupSettingType` — string/json/integer/double/boolean.
- `StartupSetting` — `parameter`, `type`, `value` (always text), `isAcknowledged`
  (**persisted**, defaults false on decode), `syncKey`, `typedValue` coercion:
  - integer falls back to `ULong` above `Long.MAX_VALUE` (`dql_request_history_log_dump_limit`
    ships as `18446744073709551615`)
  - double accepts scientific notation
  - boolean maps case-insensitively (the `Bool("True")` trap)
  - json validated by parse; empty string is a valid **String** value
- `DQLValue` sealed type → argument map bridge at the execute call site.
- `AdvancedApplyResult` — applied/skipped settings, appliedScopeCount, scopesUnverified.
- `AdvancedSettingsValidator` — the single chokepoint shared by editor and apply path:
  - `maxValueLength = 4096`, `maxRowCount = 64`
  - reserved exact names: `user_collection_sync_scopes`, `dql_strict_mode`,
    `mesh_chooser_max_wlan_clients`, `data_sync_enabled`; reserved prefixes:
    `transports_`, `udp_`
  - sensitive: suffix `_listener_addr` / `_certs`, prefix `sqlite3_`, **token** match
    on `port`/`ports` (never `contains("port")` — it matches "exporter")
  - parameter name guard: whole-string `[A-Za-z_][A-Za-z0-9_]*`, ≤ 128 chars — this is
    the SQL-injection guard because names are interpolated into DQL
  - collection rules: non-empty after trim, no `__`/`system:` prefixes, no
    whitespace/quotes/backticks, no duplicates
  - `partitionSettings()` for whole-list validation (duplicates + row cap) covering
    non-UI ingress
- `AdvancedSettingsDql` — statement builders; `scopeMap()` throws on
  duplicate/invalid/too-many (never resolves a conflict to one scope).

Serialization for storage: kotlinx.serialization JSON (already used by the QR layer).

## Phase 2 — Storage (Room v4)

- `DatabaseConfigEntity`: add `collectionSyncScopes TEXT NOT NULL DEFAULT '[]'` and
  `startupSettings TEXT NOT NULL DEFAULT '[]'` (JSON-in-TEXT, same rationale as
  SwiftUI schema v5: small lists, always read/written with the parent, never queried
  independently).
- `AppDatabase`: version 3 → 4, hand-written `MIGRATION_3_4` (the repo bans destructive
  fallback — `AppDatabase.kt:79-85`), commit `app/schemas/.../4.json`.
- `DittoDatabase` domain model + `DatabaseRepositoryImpl.toDomain()/toEntity()`
  mappers (`:55-93`) thread the two fields.
- Corrupt-JSON stance (parity): a config whose stored scopes JSON is unreadable is
  marked unopenable, the rest of the list still loads; the editor shows a banner and
  blocks Save until re-entered or explicitly discarded.

## Phase 3 — Apply pipeline

New `data/ditto/AdvancedSettingsApplier.kt`:

- `DQLExecuting` interface wrapping `ditto.store.execute` so a recording fake can test
  ordering without a live instance (same trick as SwiftUI).
- `applyStartupSettings()` — best-effort, per-row skip with reasons.
- `applySyncScopes()` — fail-closed:
  - empty scope list **still issues the statement** (deleting the last row must take
    effect; `ALTER SYSTEM` state is in-memory)
  - read-back via `SHOW user_collection_sync_scopes`; verification is **subset**, not
    equality; only known result keys consulted (no "first value in row" fallback)
  - statement throw or positive read-back disagreement → abort open
  - unparseable read-back → open proceeds, reported **unverified**
- `OpenSequence` equivalent encoding the production order so tests assert the real
  sequence: user settings → transports → `DQL_STRICT_MODE` → sync scopes → `startSync`.
  (`mesh_chooser_max_wlan_clients` is macOS-only — not applicable.)

Wire into `DittoManager.hydrate()` between `applyTransportConfig` (line 64) and
`sync.start()` (line 66). Route the sync-start path of `StudioSession.toggleSync()`
through the same sequence (SwiftUI parity: every sync start re-applies and re-verifies).

Fold the existing `isStrictModeEnabled` flag into the sequence — it is currently
persisted but never applied.

## Phase 4 — Editor UI

`DatabaseEditorScreen.kt` + `DatabaseEditorViewModel.kt`, following the screen's
existing patterns (`FormSectionHeader`, `ExposedDropdownMenuBox`, `Switch` rows,
`labelSmall` secondary helper text, test tags, `canSave` gating):

- "Advanced Configuration" section after mode-specific sections, before Developer
  Options (SwiftUI order). Disclosure row with chevron; auto-expands when validation
  errors exist; error badge on the disclosure row.
- **Collection Sync Scopes** subsection: row per mapping (collection name field +
  scope dropdown), add/remove buttons, 64-row cap on add, legend text, inline row
  errors with the exact SwiftUI messages.
- **Startup System Settings** subsection: row per setting (parameter field, type
  dropdown, value control — text field or True/False dropdown for boolean), sensitive
  acknowledgement switch, inline row errors.
- Acknowledgement revocation (parity): renaming the row, editing the value, or
  switching type to Boolean when that seeds a value clears `isAcknowledged`;
  re-spelling an existing boolean does not.
- Corrupt-scopes banner + "Discard the unreadable sync scopes" toggle; Save blocked
  until resolved.
- **Reset to SDK Defaults** button with Undo. If the edited database is the one
  currently open, save issues `ALTER SYSTEM RESET ALL` and re-applies everything the
  app manages (a failed RESET is surfaced, not logged-and-forgotten). For a database
  that is not open there is nothing to reset — next open starts from SDK defaults.
- ViewModel: one `MutableStateFlow` per list (matching the editor's existing two-way
  binding pattern), row-level validation, `canSave` extended with advanced errors,
  `save()` serializes both lists.

## Phase 5 — QR exclusion

Advanced settings are **excluded from QR payloads** on both sides (behavioral reason,
not capacity: importing another device's scopes silently changes what syncs, in both
directions).

- Do **not** add the fields to `QrConfigPayload`.
- Decode side: explicitly construct the saved `DittoDatabase` with empty lists
  regardless of payload content (defense against a payload crafted by another client).
- Tests assert exclusion in both directions (the SwiftUI `QRCodeAdvancedExclusionTests`
  equivalent).

## Phase 6 — Tests + verification

Unit (JUnit4 + MockK + kotlinx-coroutines-test, per existing conventions):

- Validator: injection guard (whole-string), reserved/sensitive matching (incl. the
  "exporter" non-match), duplicates (case-insensitive), `ULong` max, boolean case trap,
  value length, row cap, `partitionSettings`.
- DQL builders: scope map raw values, duplicate/invalid/too-many throws.
- Applier with recording fake: statement order vs `startSync` (startSync never reached
  when scopes fail), best-effort vs fail-closed policy, read-back shapes A/B,
  empty-map statement, subset verification, unverified path.
- Repository mapper round-trip; editor ViewModel (canSave gating, ack revocation,
  corrupt banner, reset/undo); QR exclusion both directions.

Instrumented (wipe-safe device only): `MigrationTest` 3→4, DAO round-trip with the new
columns.

Gates: `./gradlew assembleDebug`, `./gradlew test`, `./gradlew check`.

## Documented stances and unverified items

- **Opposite failure policies are deliberate**: scopes fail-closed (containment),
  settings best-effort (tuning knobs).
- `ALTER SYSTEM RESET ALL` typed into the query editor against a live syncing instance
  clears scopes for the session; the only remedy is close/reopen or sync toggle. The
  editor shows *stored* configuration, not necessarily what the running session
  enforces.
- **Unverified (same as SwiftUI):** the live `ALTER SYSTEM` round-trip on Android SDK
  5.1.0 — named parameter as the whole RHS of a scalar `ALTER SYSTEM SET`, the empty
  map, `ULong > Long.MAX_VALUE` argument encoding, and the `SHOW` result shape — has no
  automated test. The SwiftUI side probe-verified these only for the Swift SDK. Record
  findings in `docs/android/` after a live check.
