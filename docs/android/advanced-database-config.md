# Android: Advanced Database Configuration

Android port of the SwiftUI feature specified in
[`../ADVANCED_DATABASE_CONFIG.md`](../ADVANCED_DATABASE_CONFIG.md) — per-database
**Collection Sync Scopes** and **Startup System Settings**, edited in the Advanced
Configuration section of the Register/Edit Database screen and re-applied on every
open. Plan: [`plans/android/advanced-database-config-parity.md`](../../plans/android/advanced-database-config-parity.md).

The DQL statements, failure policies, validation rules, reserved/sensitive parameter
lists, and QR-exclusion rationale are **identical to the SwiftUI spec** and are not
restated here. This document records only the Android wiring and the points where the
port diverges.

## Implementation map

| Concern | File |
|---|---|
| Models, validation, DQL builders, storage codec | `domain/model/AdvancedDatabaseSettings.kt` |
| Apply pipeline (fail-closed scopes, best-effort settings, OpenSequence) | `data/ditto/AdvancedSettingsApplier.kt` |
| Open/sync funnels | `data/ditto/DittoManager.kt` (`hydrate`, `startSync`, `resetSystemSettingsToDefaults`) |
| Storage (Room v4, JSON-in-TEXT columns) | `data/db/entity/DatabaseConfigEntity.kt`, `data/db/AppDatabase.kt` (`MIGRATION_3_4`) |
| Editor UI | `ui/database/DatabaseEditorScreen.kt` + `ui/database/AdvancedConfigurationSection.kt` |
| Editor state | `viewmodel/DatabaseEditorViewModel.kt` |

## Wiring notes

- **Every sync start goes through `DittoManager.startSync()`**, which re-runs the
  OpenSequence (user settings → transports → `DQL_STRICT_MODE` → scopes + read-back →
  `sync.start()`). That covers the initial open (`hydrate`), the sync toggle
  (`StudioSession.toggleSync`), and the Transport Settings restart
  (`StudioSession.applyTransportSettings`).
- `DittoManager` is a Koin **singleton**, so the editor ViewModel receives it directly
  for `lastAdvancedApplyResult`, `refreshActiveConfigIfMatching`, and the live
  `resetSystemSettingsToDefaults` path.
- The Kotlin SDK's `execute(query, arguments: Map<String, Any?>)` overload accepts
  nested maps, lists, and `ULong` (verified against the 5.1.0 sources), so no CBOR
  plumbing is needed for the scopes map or `UInt64`-range integers.
- Read-back parses `SHOW user_collection_sync_scopes` result items via
  `item.jsonString()` → `parseJsonToMap`, accepting both the keyed-by-parameter and
  name/value row shapes, same as SwiftUI.

## Divergences from the SwiftUI implementation

- **`mesh_chooser_max_wlan_clients`** is macOS-only and has no Android equivalent; the
  OpenSequence omits it.
- **Row identity is serialized.** `CollectionSyncScope.id` / `StartupSetting.id` are
  stored with the row (SwiftUI excludes them from Codable). The stores are
  per-platform, so format parity is not required, and persisting the id keeps
  `copy()`-based row mutation stable in Compose lists.
- **Strict mode is now applied.** `isStrictModeEnabled` was persisted, edited, and
  QR-shared on Android but never applied to the instance; the OpenSequence issues
  `ALTER SYSTEM SET DQL_STRICT_MODE` on every open, closing that gap.

## Unverified

Same caveat as the SwiftUI release: the **live `ALTER SYSTEM` round-trip has no
automated test** — named parameter as the whole right-hand side of a scalar
`ALTER SYSTEM SET`, the empty scope map, `ULong` argument encoding, and the exact
`SHOW` result shape were verified only against SDK sources and SwiftUI's SPM probe,
not against a running Android instance. The read-back treats an unparseable `SHOW`
result as "unverified" rather than fatal, so a shape surprise degrades safely.

## Testing

- `AdvancedDatabaseSettingsTest` — wire values, coercion (incl. `ULong.MAX_VALUE` and
  the boolean case trap), injection guard, reserved/sensitive matching, storage
  strictness.
- `AdvancedSettingsApplierTest` — recording-fake ordering vs `startSync`, fail-closed
  scope policy, best-effort settings, read-back shapes, empty-map statement.
- `DittoManagerTest` — the production hydrate path applies strict mode + scopes before
  `sync.start()`, refuses corrupt scopes, and never starts sync when scopes fail.
- `DatabaseRepositoryTest` — mapper round-trip, corrupt-scope flag, lenient settings.
- `DatabaseEditorViewModelTest` — `canSave` gating, acknowledgement revocation
  (rename / value edit / Boolean seeding), reset/undo, corrupt-scope blocking.
- `QrCodeEncoderTest` / `QrCodeDecoderTest` — advanced settings excluded in both
  directions, including a crafted hostile payload.
- `MigrationTest` (instrumented) — v1→v4 chain and v3→v4 column defaults.
- `AdvancedConfigurationUiTest` (instrumented, 22 tests) — disclosure and summary,
  scope/setting row editing, inline validation messages, Save gating, sensitive
  acknowledgement (grant, revoke on rename, withdraw), boolean dropdown seeding,
  reset/undo, corrupt-scope banner recovery, and an end-to-end save through the UI
  into a fake repository. Dropdown menu interactions are covered by dedicated tests;
  tests that type text first drive dropdown *selection* through the ViewModel because
  clicking an `ExposedDropdownMenuBox` anchor with the IME open is flaky on emulators.
