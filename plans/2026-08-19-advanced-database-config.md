# Advanced Database Configuration — Sync Scopes + Startup System Settings (2026-08-19)

**Revision 2** — rewritten after adversarial review. Nine claims in revision 1 were
wrong; they are corrected inline and listed under
[Corrections from review](#corrections-from-review). Read that section first if you
reviewed r1.

Bring the SwiftUI (macOS/iPadOS) Edit/Register Database screen to parity with the
Edge Studio **VS Code** extension's **Advanced Configuration** accordion:

1. **Collection Sync Scopes** — per-collection sync reach
2. **Startup System Settings** — arbitrary `ALTER SYSTEM` parameters applied at open

Screenshots: `~/Desktop/vsc-edit-database.png`,
`~/Desktop/vsc-edit-database-settings.png` (copy to `screens/swift/` when starting).

---

## Design posture — the one thing to get right

Sync scopes are a **data-containment** control. A user who sets `LocalPeerOnly`
believes that collection never leaves the device. Startup settings are ordinary
tuning knobs. These two need **opposite failure policies**, and r1's single
best-effort policy for both was its central flaw:

| | Sync scopes | Startup settings |
|---|---|---|
| Apply fails | **Abort the open**, surface an error | Log + continue, report in result |
| Stored JSON won't decode | **Hard error**, refuse to open | Degrade to `[]` + warn |
| Unknown enum raw value | **Decode failure** | n/a |
| Verification | **Read back via `SHOW` and compare** | Optional |

Rule: *absence of containment config must never be indistinguishable from loss of it.*

---

## SDK API facts (verified against Ditto Swift SDK 5.1.0)

No typed Swift API exists for either feature — both are DQL via
`ditto.store.execute`. Verified in the 5.1.0 `.swiftinterface` (no
`SyncScope`/`AllPeers`/`BigPeerOnly` symbols) and by extracting strings from the
`DittoSwift` binary.

### Collection sync scopes
Docs: https://docs.ditto.live/sdk/latest/sync/sync-scopes

```swift
let scopes = ["orders": "SmallPeersOnly"]           // [String: String]
try await ditto.store.execute(
    query: "ALTER SYSTEM SET USER_COLLECTION_SYNC_SCOPES = :scopes",
    arguments: ["scopes": scopes])
try ditto.sync.start()
```

| DQL value | UI label | Behavior |
|---|---|---|
| `AllPeers` | All Peers | Default — Ditto Server + Small Peers |
| `BigPeerOnly` | Big Peer Only | Ditto Server only |
| `SmallPeersOnly` | Small Peers Only | Small Peers only |
| `LocalPeerOnly` | Local Peer Only | Never leaves this device |

All four raw values confirmed present in the SDK binary (note `SmallPeersOnly` is
plural). The binary also carries the guard string *"value of system parameter
`` updated while sync is active; please set sync scopes before calling
`start_sync()`"*, and `InvalidSystemCollectionMutation`, corroborating both the
timing requirement and the `__`-prefix restriction.

Constraints:
- **MUST be set before `ditto.sync.start()`.**
- **Not persisted by the SDK** — reset when the instance closes; re-apply every open.
- Cannot target system collections. Device-local; not synced to peers. Not
  enforced for remote query requests.

### Startup system settings
Docs: https://docs.ditto.live/sdk/latest/sync/using-alter-system

- `ALTER SYSTEM SET <name> = <value>` · `SHOW ALL` / `SHOW <name>` ·
  `ALTER SYSTEM RESET ALL` / `RESET <name>`
- **In-memory only.** No published parameter list, hence free-form name + typed value.
- **Supported types this release: String, JSON, Integer, Double, Boolean.** Arrays
  get no dedicated editor — but any valid JSON document is accepted, so
  `["a","b"]` under `JSON` already produces a real array.
- The user is trusted to know the parameter and type. We validate that the text
  *parses*, plus the safety rules below.

### Observed value shapes (from a real `SHOW ALL`, ~280 parameters)

| Kind | Examples |
|---|---|
| Bool | `data_sync_enabled: true`, `dql_strict_mode: false` |
| Int | `mesh_chooser_max_wlan_clients: 12` |
| Int-as-flag | `sqlite3_synchronous: 1`, `transports_wifi_aware_background_mode: 2` |
| Double | `doc_id_filter_error_rate: 0.01`, `doc_sync_redundancy_backoff_threshold: 0.59999999999999998` |
| Double (sci-notation) | `metrics_exporter_onfile_histogram_summary_min_value: 1.0000000000000001e-09` |
| String | `sqlite3_journal_mode: "WAL"`, `metrics_exporter_prometheus_http_listener_addr: "0.0.0.0:9000"` |
| String (empty) | `transports_ble_adapter_mac: ""` |
| Map / Array | `user_collection_sync_scopes: {}`, `additional_p2p_trusted_ca_certs: []` |

Consequences (all re-verified by running Swift, not by assumption):

1. **Integer and Double are distinct** — real double artifacts and sci-notation.
   Don't collapse into one "Number". `Double("1.0000000000000001e-09")` parses.
2. **`Int` overflows on real values**: `dql_request_history_log_dump_limit` and
   `metrics_exporter_onfile_max_files` are `18446744073709551615` (`UInt64.max`);
   `Int(_:)` returns nil → needs a `UInt64` fallback.
3. **Empty string is legal** → don't gate Save on a non-empty *value* for `.string`.
4. **Names read back lowercase `snake_case`** while writes appear case-insensitive
   (the app writes `DQL_STRICT_MODE`, `SHOW ALL` returns `dql_strict_mode`) →
   dedupe case-insensitively, write verbatim.
5. **`example_*` sandbox parameters exist and are documented in the SDK binary as
   having "no effect on Ditto itself"** — `example_parameter`,
   `example_string_parameter`, `example_bool_parameter`, `example_map_parameter`,
   `example_array_parameter`, `example_duration_parameter`. Live tests target these.

---

## Where this slots into the codebase

`DittoManager.hydrateDittoSelectedDatabase` — verified sequence in
`Data/DittoManager.swift`: `Ditto.open` :145 → `setOfflineOnlyLicenseToken` :171 →
`setPeerMetadata` :175 → `updateTransportConfig` :192-201 → `logTransportReadback`
:202 → `ALTER SYSTEM SET DQL_STRICT_MODE` :206 → macOS
`mesh_chooser_max_wlan_clients = 12` :210-213 → `dittoSelectedAppConfig =` :215 →
`sync.start()` :218-220 → `dittoSelectedApp = ditto` :222.

`isStrictModeEnabled` is the precedent for a new config field. Production surface:
`Models/DittoConfigForDatabase.swift` · `Data/SQLCipherService.swift` ·
`Data/Repositories/DatabaseRepository.swift` · `Data/DittoManager.swift` ·
`Views/Database/DatabaseEditorView.swift`, plus
`EdgeStudioIntegrationTests/Fixtures/DatabaseConfigFixtures.swift` and
`EdgeStudioUnitTests/Models/ModelTests.swift`.

---

## Data model

New file `Models/AdvancedDatabaseSettings.swift`.

```swift
enum SyncScope: String, CaseIterable, Codable, Sendable {
    case allPeers = "AllPeers", bigPeerOnly = "BigPeerOnly"
    case smallPeersOnly = "SmallPeersOnly", localPeerOnly = "LocalPeerOnly"
    var displayName: String
    var explanation: String   // legend copy, mirrors the VS Code bullet list
    // NO tolerant `parse`. An unknown raw value must FAIL decoding — silently
    // coercing an unrecognized scope is a containment bug.
}

/// Identity is the business key, NOT a UUID. Uniqueness is already validated, so
/// `collection` is stable across decode, keeps `Equatable` honest, and gives UI
/// tests a content-addressed accessibility id.
struct CollectionSyncScope: Codable, Equatable, Identifiable, Sendable {
    var collection: String
    var scope: SyncScope
    var id: String { collection }
}

enum StartupSettingType: String, CaseIterable, Codable, Sendable {
    case string, json, integer, double, boolean
    var displayName: String
    var usesFreeTextValue: Bool { self != .boolean }
}

/// Sendable closed enum — NOT `Any?`. `Any` is not Sendable and this value crosses
/// into the DittoManager actor; bridge to `Any` only at the `execute` call site.
enum DQLValue: Sendable, Equatable {
    case string(String), int(Int), uint(UInt64), double(Double), bool(Bool)
    case json(Data)          // re-parsed to a JSON object at the call site
}

struct StartupSetting: Codable, Equatable, Identifiable, Sendable {
    var parameter: String
    var type: StartupSettingType
    var value: String        // always text; coerced when the statement is built
    var id: String { parameter.lowercased() }

    /// nil ⇒ row-level validation error, Save disabled.
    ///   .string  → .string(value); "" is valid
    ///   .json    → .json(Data(value.utf8)) after JSONSerialization validation
    ///   .integer → Int(value) ?? UInt64(value)   ← UInt64.max needs the fallback
    ///   .double  → Double(value); sci-notation OK
    ///   .boolean → CASE-INSENSITIVE map. `Bool("True") == nil` (verified!), so
    ///              never use `Bool.init?(String)` on picker text.
    var typedValue: DQLValue? { get }
}
```

Added to `DittoConfigForDatabase`:

```swift
var collectionSyncScopes: [CollectionSyncScope]
var startupSettings: [StartupSetting]
```

**No default values on the initializer parameters.** The config is rebuilt from
scratch at `DatabaseRepository.swift:49`, `ContentView.swift:695`, and
`DatabaseEditorView.swift:450`; `updateDatabaseConfig` overwrites every column. A
defaulted parameter means a call site that forgets the field silently wipes it —
and that trap has **already fired**: `ContentView.swift:695-710` omits `logLevel`
and `isStrictModeEnabled`. Requiring both arguments makes the compiler enforce it.
Fix the pre-existing `ContentView` omission in the same pass.

Codable: both fields in `CodingKeys`, explicit in `encode(to:)`,
`decodeIfPresent(…) ?? []` for `startupSettings`. **Sync scopes decode strictly** —
a present-but-malformed array throws (see failure policy).

---

## Persistence — SQLCipher schema v5

`currentSchemaVersion` 4 → 5 (`SQLCipherService.swift:44`).

```sql
ALTER TABLE databaseConfigs ADD COLUMN collectionSyncScopes TEXT NOT NULL DEFAULT '[]'
ALTER TABLE databaseConfigs ADD COLUMN startupSettings      TEXT NOT NULL DEFAULT '[]'
```

Verified against SQLite 3.50.6: `ADD COLUMN … TEXT NOT NULL DEFAULT '[]'` succeeds
on a populated table and backfills correctly.

**Migration must be atomic — this is a bricking risk, not a nit.**
`migrateSchema` (`:375-397`) runs `PRAGMA user_version = N` *outside* any
transaction, and `migrateToVersion3` (`:416-422`) / `migrateToVersion4` (`:425-431`)
use bare `execute` with no transaction (only v2 wraps). If the process dies between
the two `ALTER TABLE`s, `user_version` is still 4, and the next launch re-runs the
migration → **"duplicate column name"** → `initialize()` throws → the `guard
!_isInitialized` at `:72` never passes → **every database config and stored
credential is permanently inaccessible with no in-app recovery.**

Required: wrap `migrateToVersion5` **and** its `PRAGMA user_version = 5` in one
`executeTransaction` (helper at `:801`; `createSchema` already does this at `:368`),
and make each `ALTER TABLE` conditional on `PRAGMA table_info(databaseConfigs)`.
Move the version bump inside the transaction for v2-v4 while there.

**Three write/read sites, not two.** r1 missed the read path:
- `createSchema()` `CREATE TABLE` (`:292-310`) — fresh installs
- `DatabaseConfigRow` + `insertDatabaseConfig` (`:501`) + `updateDatabaseConfig` (`:531`)
- **`getAllDatabaseConfigs()` (`:571-598`)** — hand-written `SELECT` list plus
  positional `sqlite3_column_*` reads at indices 0-15. Without editing it the new
  columns are never read back, and appending out of order shifts every index. Note
  it uses `String(cString: sqlite3_column_text(...))`, which null-derefs on NULL —
  hence `NOT NULL DEFAULT`, plus a defensive unwrap for the new indices.

JSON-in-TEXT over child tables: both lists are small, always read/written with the
parent, never queried independently. `DatabaseRepository` owns JSON ↔ model
bridging (already the legacy-name bridge). Decode failure handling differs by
field per the failure-policy table: `startupSettings` → `[]` + warning;
`collectionSyncScopes` → throw.

---

## Applying at open — `DittoManager`

### Ordering (differs from r1 — precedence is now defined)

r1 applied user settings *after* the app's own statements, which let a user's
generic setting silently override an app-managed one. Corrected order:

1. `Ditto.open` … `setOfflineOnlyLicenseToken`, `setPeerMetadata` (unchanged)
2. **User startup settings** — best-effort, each in its own `do/catch`
3. `updateTransportConfig` (unchanged position relative to 4-6)
4. `ALTER SYSTEM SET DQL_STRICT_MODE` (app-managed — must win)
5. macOS `mesh_chooser_max_wlan_clients` (app-managed — must win)
6. **Sync scopes** — fail-closed, then read-back verified
7. `logTransportReadback` — **moved to here**, after every `ALTER SYSTEM`, so the
   log reflects reality rather than pre-override values
8. `dittoSelectedApp = ditto` — **moved up from :222** (see orphan bug below)
9. `sync.start()`

App-managed parameters win because they have dedicated UI. Two controls writing one
parameter with order-defined precedence is a bug factory; hence the deny list below.

### Sync scopes — fail-closed

```
map = scopeMap(from: config.collectionSyncScopes)   // pure, unit-tested
if map.isEmpty { skip }
execute("ALTER SYSTEM SET USER_COLLECTION_SYNC_SCOPES = :scopes", ["scopes": map])
readback = execute("SHOW user_collection_sync_scopes")
guard readback == map else { throw }        // never reach sync.start()
```

On throw or mismatch: `throw AppError.error(message: "Could not apply sync scope
'orders' = Local Peer Only; the database was not opened to avoid syncing data you
marked device-local.")`. The existing `catch` (`DittoManager.swift:234-237`) and
`ContentView.swift:771-782` already render that, so the abort path is free.
Duplicate collection names are a **hard error here**, not last-wins — the UI blocks
them, but non-UI ingress exists.

### Startup settings — best-effort with a reported result

Return a value instead of only logging, so tests and UI can assert on it:

```swift
struct AdvancedApplyResult: Sendable {
    let applied: [String]
    let skipped: [(name: String, reason: String)]
}
```

Parameter names cannot be parameterized, so validate before interpolation — with
**whole-string matching**. `value.range(of: pattern, options: .regularExpression)`
accepts a *partial* match (so `"ok; ALTER SYSTEM SET data_sync_enabled = false --"`
would pass) and ICU `$` also matches before a trailing newline. Use Swift Regex
`wholeMatch(of:)` or `CharacterSet` membership over the full string.

### Reset to SDK defaults — `ALTER SYSTEM RESET ALL`

Requested behavior: clearing the settings actively restores defaults.
**Implemented as a live action, not a persisted flag** — r1's
`needsSystemSettingsReset` column is dropped, because review found it to be a
no-op that bought three hazards: (a) if `RESET ALL` throws, the flag never clears
and the database becomes permanently unopenable; (b) clearing it from inside
`hydrate` mutates the shared `@Observable` config from an actor, which
`DittoManager.swift:413-416` explicitly documents as forbidden; (c) a crafted QR
payload could arm a destructive statement on the scanning device.

- **Affordance**: `Reset to SDK defaults` in the Advanced Configuration header —
  clears both lists (the config then yields defaults on the next open, since
  `ALTER SYSTEM` state dies with the instance).
- **When this config is the *active* one** (which does happen — see corrections),
  saving a reset issues `ALTER SYSTEM RESET ALL` against the live instance and then
  **immediately re-applies** `updateTransportConfig`, `DQL_STRICT_MODE`, the macOS
  mesh setting, and the sync scopes, in that order. `RESET ALL` wipes *every*
  parameter, so anything not re-applied is silently lost.
- **Open hazard to verify (Phase 3)**: `SHOW ALL` exposes
  `transports_ble_server_is_enabled`, `transports_awdl_browse_enabled`,
  `transports_wifi_aware_client_is_enabled`, `udp_server_enabled`,
  `data_sync_enabled`. If `updateTransportConfig` writes through to those, a
  `RESET ALL` would **re-enable BLE/LAN/AWDL the user turned off** — a privacy
  regression. Experiment: disable BLE+LAN, issue `RESET ALL`, then `SHOW` those
  parameters. Record the result in `docs/ADVANCED_DATABASE_CONFIG.md`. The
  re-apply step above is what makes this safe either way.

### Two pre-existing bugs this feature makes worse

1. **Orphaned syncing instance.** `sync.start()` (`:218-220`) runs *before*
   `dittoSelectedApp = ditto` (`:222`), and `closeDittoSelectedDatabase` is guarded
   by `if let ditto = dittoSelectedApp` (`:24`). A throw in that window leaves a
   live instance syncing **every collection at the default `AllPeers`**, unreachable
   for shutdown, while the user sees "Failed to initialize database". Adding
   statements to that window widens it. Fix: assign `dittoSelectedApp` right after
   `guard let ditto` (`:147`), or `ditto.sync.stop()` in the catch.
2. **Runtime `ALTER SYSTEM` erases everything this feature persists.**
   `QueryService.executeSelectedAppQuery` (`QueryService.swift:33-40`) and the MCP
   `execute_dql` tool (`MCPToolHandlers.swift:45`) run arbitrary DQL — and this
   plan's own smoke test teaches the user `SHOW ALL`. One `ALTER SYSTEM RESET ALL`
   in the query editor blanks the live scope map while sync runs; the Advanced UI
   still shows `LocalPeerOnly`. Also there are **three `sync.start()` call sites**
   (`DittoManager.swift:219`, `:250` via `SyncStatusViewModel.swift:132`,
   `TransportConfigView.swift:293`) but only one apply point. Fix: extract
   `applyAdvancedSettings` and call it before *every* `sync.start()`; have
   `QueryService`/`execute_dql` detect `ALTER SYSTEM` and re-apply app-managed
   parameters afterwards (or refuse with "use Advanced Configuration").

### Concurrency

`DittoConfigForDatabase` is an `@Observable final class` marked `@unchecked
Sendable` whose header claims MainActor-mutates / actors-only-read. **That contract
is already violated**: `TransportConfigView.swift:277-288` mutates the live shared
instance from the MainActor while `SystemRepository.swift:278/553/650` reads it from
an actor. With `Bool`s that is a word-sized tear; with **arrays** it is an
unsynchronized CoW buffer retain/release — over-release crashes, or torn rows get
written back to SQLCipher.

Therefore: **do not read the new arrays off the shared reference inside
`DittoManager`.** Pass `[CollectionSyncScope]` / `[StartupSetting]` (value types)
as parameters into the apply function, or add a `DittoConfigSnapshot: Sendable`.
Compile the new file with `SWIFT_STRICT_CONCURRENCY=complete` as a Phase-1 gate.

---

## Validation

Enforced in a pure `AdvancedSettingsValidator` used by **both** the editor and the
apply path — the apply path is the real chokepoint, since non-UI ingress exists.

Sync scopes:
- **Trim first**, then reject empty — `"   "` and `"orders "` both pass a naive
  non-empty check and produce an inert scope, so `LocalPeerOnly` silently doesn't apply
- reject `__` prefix **and `system:` prefix** (`SystemRepository.swift:291`,
  `CollectionsRepository.swift:115` show the latter form in use)
- reject names needing identifier quoting (quotes, whitespace)
- duplicates: blocked in UI, **hard error** in the apply path
- **case sensitivity warning**: DQL collection names are case-sensitive, so `Orders`
  vs `orders` is an inert scope. `CollectionsRepository` has the live collection
  list — show "not found in this database" beside the row (warning, not blocking)

Startup settings:
- name non-empty and whole-string `^[A-Za-z_][A-Za-z0-9_]*$`
- duplicates compared case-insensitively
- value coercible to type; **empty valid for `.string`**
- **length/row caps**: value ≤ 4 KB, ≤ 64 rows (nothing else bounds a 10 MB JSON
  value that gets re-parsed on every open)
- **deny list** (app-managed — "Managed by <control>", Save blocked):
  `user_collection_sync_scopes`, `dql_strict_mode`, `mesh_chooser_max_wlan_clients`,
  `data_sync_enabled`, `transports_*`, `udp_*`
- **confirm list** (requires an explicit "I understand" toggle): anything matching
  `*_listener_addr`, `*_certs`, `sqlite3_*`, or containing `port`. Rationale:
  `metrics_exporter_prometheus_http_listener_addr = "0.0.0.0:9000"` opens a
  **listening socket on all interfaces** exporting database metrics;
  `additional_p2p_trusted_ca_certs` adds a trusted CA (MITM);
  `sqlite3_synchronous = 0` / `sqlite3_journal_mode = "OFF"` trades away store
  durability. None are caught by the name regex.

---

## UI — `DatabaseEditorView`

### Scrolling — make it explicit, don't assume it

**r1 was wrong that the Form scrolls.** `DatabaseEditorView.swift:43` creates a
bare `Form` with **no `.formStyle`** (verified: the only `.formStyle` uses in the
app are `AddIndexView.swift:42` `.columns`, `AppPreferencesView.swift:62` and
`TransportConfigView.swift:137` `.grouped`). On macOS the default resolves to
`.columns`, a two-column layout container — not a scroll view. What actually fixed
the earlier clipping was captions wrapping so content *happened* to fit in 790pt.

So: set `.formStyle(.grouped)` (matching `TransportConfigView`) and/or wrap in an
explicit `ScrollView`, give the Form `.frame(maxWidth: .infinity, maxHeight:
.infinity)` so it is the **sole** vertically-greedy child, and verify with a full
accordion before declaring the phase done.

Also:
- **Delete `Spacer(minLength: 0)`** (`:119`) — a Spacer sibling to a greedy scroll
  view splits residual space unpredictably; it was itself a prior overflow source.
- **Replace `Spacer().frame(height: 20)`** (`:58-61`) — renders as an empty grouped
  cell under `.grouped`; use padding on the picker row.
- **Keep both `.fixedSize(horizontal: false, vertical: true)` guards** (`:100`,
  `:112`) — r1 said to drop them. Inside a scroll view they're a no-op, but if the
  Form ends up columns-style they're load-bearing. Add the same guard to the new
  legend and every new `.caption2`.
- `ContentView.swift:292` **keeps** `.frame(width: 960, height: 790)`. (r1 contained
  a self-cancelling pseudo-diff here — "change X → X stays".) The invariant to hold
  is: the Form is the only vertically-flexible child, so 790pt acts as a viewport.
- **Gate the info panel on `isNewItem`, not `databaseId == ""`** (`:88`). Once the
  panel scrolls, the first keystroke in Database ID removes a ~90pt row from the
  middle of the content and shifts the caret's row while typing. `isNewItem`
  (`:383`) is immutable for the sheet's lifetime.

### Structure

Two sibling **collapsible `Section(isExpanded:)`** — *not* `Section`s nested inside
a `DisclosureGroup`, which lose headers/insets inside a Form. Insert them inside
`modeSpecificSections(for:)`, since `developerOptionsSection()` is emitted from
within it (`:231`) and there is no seam "before Developer Options".

Header trailing summary mirrors VS Code: `"1 scope · 0 startup settings"`.

### Rows must be adaptive

A single row is name + type picker + value + Remove. Under a macOS `.columns` Form
the row lives in the **trailing column only** (~450pt of the 960 after the label
gutter and `:122-123` padding) — four controls there gives ~120pt each. On iPad it
is worse: the iOS sheet is `.presentationDetents([.large])` (`ContentView.swift:333`,
ignored for a regular-width form sheet ≈700pt) and there is a **compact `< 650pt`
path** (`compactPickerContent`, `:350`) reachable in Slide Over at ~320pt, which r1
never mentioned.

Use `ViewThatFits(in: .horizontal)` with a horizontal row (fields
`.frame(minWidth: 180)` so it refuses to render when squeezed) falling back to a
stacked layout with Remove in a `.contextMenu`/swipe.

### Value control
- **Boolean** → `Picker` True / False (no free text)
- **String / JSON / Integer / Double** → `TextField`, monospaced for JSON
- Numeric keyboards: `.asciiCapable`, **not** `.numbersAndPunctuation` — the latter
  has no `e`, and sci-notation input is required. Wrap in `#if os(iOS)`.
- Changing a row's type **re-validates but must not clear the text** — silently
  deleting a pasted 1500-char value on a stray picker tap has no undo.

### Lists
Iterate **values keyed by `id`**, not `ForEach($bindings)`: a per-row Remove button
inside a binding-derived row invalidates the binding the executing body owns →
`Index out of range`. Resolve per-field bindings through the view model by `id`, and
clear `@FocusState` *before* mutating the array.

### Accessibility identifiers
**Content-addressed, not index-based** — matching the codebase convention
(`AppCard_\(app.name)` `ContentView.swift:412`, `NavItem_\(rawValue)`
`SidebarViews.swift:50`): `SyncScopeRow_<collection>`,
`StartupSettingRow_<parameter>`, plus fixed `AdvancedConfigDisclosure`,
`AddSyncScopeButton`, `AddStartupSettingButton`, `ResetToDefaultsButton`. Index ids
silently assert about a *different* row after a delete. Resolve fields within a row
via `descendants`. Caveat: `docs/TESTING.md:1243` notes SwiftUI pickers are
unreliable in XCUITest, and the existing `.menu` `LogLevelPicker` (`:244`) has no
UI test — verify one picker is addressable before claiming it as test surface.

### Dirty tracking
`OriginalSnapshot` (`:347`) gains normalized projections
(`[(collection, scope)]`, `[(parameter, type, value)]`). Business-key `id`s keep
synthesized `Equatable` honest, so this no longer needs a hand-written `==`.

### QR sharing — excluded, and don't wipe the source doing it

Decision stands: the QR payload carries **neither** array; users re-enter them.
Not for capacity reasons (measured: it would fit) but because silently importing
another device's sync scopes changes what syncs — in both directions.

**Corrected numbers** (r1's were value-dependent and optimistic; re-derived with a
realistic portal JWT/URLs): config alone **717 B** of the 2200-byte cap (33%, not
581/26%); +10 scopes +10 settings +5 favorites **1033 B** (47%, not 865/39%);
ceiling ~**171** rows of each with compressible names (not 182), ~30 each with
random names; single-value ceiling ~1350-1400 incompressible chars — a real PEM
certificate overflows.

Implementation: `encode(to:)` reaches only `QRCodeGenerator.encodePayload`
(verified exhaustively; `KeychainService.swift:49` encodes `DatabaseCredentials`).
- **Encode** a sanitized copy — via a new `func sanitizedForSharing() ->
  DittoConfigForDatabase` that constructs a **new instance**. `DittoConfigForDatabase`
  is a `final class` with no copy init, so the obvious `config.collectionSyncScopes
  = []` would **delete the user's real scopes from the shared `@Observable` object
  the moment they display a QR code** — data loss from a read-only action. Note
  `generate` re-builds this repeatedly while shedding favorites (`:41-52`).
- **Decode** clears both arrays regardless of payload contents, so another client's
  scopes can never be silently imported.
- Keep the model's `Codable` symmetric. (r1 justified this as "the plist loader can
  seed advanced settings" — **that was wrong**: `DittoAppConfigLoader` decodes JSON,
  not plists, and has **zero call sites** (dead code). The real seed path is
  `ContentView.seedTestDatabasesIfNeeded` (`:690-711`) using the memberwise init.
  The honest rationale is simply that a lossy `encode` would silently break a future
  JSON export.)

State in the UI that advanced settings are not shared by QR.

---

## Tests

Per `docs/TESTING.md` — Swift Testing, AAA, ≥80% on new code. Note there is **no
CI**: `.github/workflows/` does not exist and `.git/hooks/` has no non-sample hooks,
so the TESTING.md pre-push coverage hook is aspirational. Nothing catches an
untested phase except review.

**Unit — `AdvancedDatabaseSettingsTests.swift`** (new)
- `SyncScope` raw values match the DQL strings exactly (the silent-mis-scope guard);
  an unknown raw value **fails** decoding
- whole-string parameter-name matching accepts `dql_x`, rejects `"x\n"` and
  `"ok; ALTER SYSTEM SET data_sync_enabled = false --"`
- `typedValue` per kind: `"12"`/int → `.int`; `"1.5"`/int → nil;
  **`"18446744073709551615"`/int → `.uint`**; `"1.0000000000000001e-09"`/double →
  `.double`; `{"a":1}`/json → object; `["a"]`/json → array; `{"a":}` → nil;
  **`"True"`/bool → `.bool(true)`** (regression guard — `Bool("True") == nil`);
  `""`/string → `.string("")`
- validator: trim-then-reject, `__` and `system:` prefixes, caps, deny list, confirm list

**Unit — ordering (the most safety-critical test, and not credential-gated)**
Extract `applyAdvancedSettings(to: DQLExecuting)` behind a protocol; a recording
fake asserts (a) the exact statement sequence and precedence (user settings before
`DQL_STRICT_MODE`/mesh/scopes), and (b) **`syncStarted` is the last recorded
event**. Without this, a refactor that moves the block below `sync.start()` leaks
`LocalPeerOnly` data with every test still green.

**Unit — fail-closed policy**: a scope apply that throws, and a read-back mismatch,
both prevent `sync.start()` and surface an error. Assert on `AdvancedApplyResult`,
**never by scraping logs** — `LoggingService` has no injectable sink and
CocoaLumberjack writes asynchronously, so a `getCombinedLogs().contains(...)` check
is flaky and cross-contaminated.

**Unit — the wipe traps**: saving an unrelated field (e.g. `name`) preserves
`collectionSyncScopes`; `QRCodeGenerator.generate(config:)` leaves the source
config's scopes intact; decode → encode → decode is stable with business-key ids.

**Integration**: v4 → v5 migration from a checked-in 3-row v4 fixture DB —
`PRAGMA user_version == 5`, all 16 pre-existing fields byte-identical, new columns
`'[]'`; interrupted-migration recovery (re-running is idempotent);
`getAllDatabaseConfigs` returns the new columns.

**Live `ALTER SYSTEM` round-trip — `AlterSystemTests.swift`** (new harness; no
existing integration test opens a Ditto instance)
1. Open a real instance in `TestConfiguration.integrationTestDatabasePath` using
   `testDatabaseConfig.plist` or `DITTO_DATABASE_ID`/`DITTO_DEVELOPMENT_TOKEN`
   (needs a scheme `environmentVariables` entry to reach the test process).
2. Round-trip each type against the `example_*` sandbox parameters — set, then
   `SHOW <param>`, asserting value **and dynamic type**. Must include
   `UInt64.max` and a JSON object, because *whether the SDK's argument encoder
   accepts `UInt64 > Int64.max` and `JSONSerialization`'s ObjC-bridged types is
   unverified* — as is whether a named parameter is legal on the RHS of a scalar
   `ALTER SYSTEM SET` (documented only for the scope map).
3. `USER_COLLECTION_SYNC_SCOPES` set → `SHOW user_collection_sync_scopes` matches
   (baseline `{}` on a fresh instance).
4. Negative: an unknown parameter is reported in `AdvancedApplyResult.skipped` and
   the open still succeeds; a failed **scope** aborts the open.
5. The `RESET ALL` / transport experiment above.
6. `@Suite(.enabled(if: TestCredentials.isAvailable))` — real trait
   (`Testing.swiftinterface:927`; repo precedent `MCPInsertFromFileTests.swift:165`).
   **A skipped suite reports green**, so Phase 3 sign-off requires a pasted result
   line showing `0 skipped`, plus an always-enabled test that fails when
   `DITTO_REQUIRE_LIVE=1` and credentials are absent.

**UI — extend `EdgeStudioUITests/DatabaseManagementUITests.swift`** (which already
opens this sheet at `:42-51`). `docs/TESTING.md:1138` requires screenshots for
layout bugs. Open the editor, expand `AdvancedConfigDisclosure`, add 6 scope rows
and 6 setting rows, then assert `isHittable` (not `exists`) on the
"Register Database" title, `SaveButton`, and `CancelButton` — the only mechanical
proof the chrome stayed pinned and on-screen. Attach screenshots `.keepAlways`.

Don't write tautological statement-text assertions; test invariants instead
(raw values not `displayName`, `__`/`system:` dropped, duplicates a hard error,
names deduped case-insensitively but written verbatim).

---

## Docs
- New `docs/ADVANCED_DATABASE_CONFIG.md` — features, DQL emitted, timing,
  in-memory caveat, **precedence rules**, deny/confirm lists, the `RESET ALL`
  transport finding (modeled on `docs/STRICT_MODE.md`)
- `SwiftUI/EdgeStudio/Resources/Help/UserGuide.md`; `CLAUDE.md` + `README.md` features

## Phases

| # | Scope | Gate |
|---|---|---|
| 1 | Model, `DQLValue`, validator, DQL helpers | unit tests green; new file compiles under `SWIFT_STRICT_CONCURRENCY=complete` |
| 2 | Schema v5 (atomic migration) + row/repo bridging incl. `getAllDatabaseConfigs` | v4-fixture migration test: `user_version == 5`, 16 fields byte-identical, new columns `'[]'`; re-running the migration is a no-op |
| 3 | `DittoManager` apply path, fail-closed scopes, precedence, orphan + re-apply fixes | ordering unit test green; live suite reports **`0 skipped`**; bogus param appears in `.skipped` with open succeeding; failed scope aborts open; `RESET ALL`/transport result recorded in the doc |
| 4 | Editor UI: sections, adaptive rows, explicit scrolling, validation, a11y ids | UI test asserts title/Save/Cancel `isHittable` with 6+6 rows on macOS, iPad form sheet, **and iPad 320pt Slide Over**; screenshots attached |
| 5 | Docs + help + feature lists | `docs/ADVANCED_DATABASE_CONFIG.md` exists with the precedence + `RESET ALL` findings; `UserGuide.md` renders in the in-app Help window |

Every phase: macOS + iOS (iPad Pro 13-inch (M5)) builds, `swiftlint lint --strict`
on changed files, full unit suite passing.

---

## Corrections from review

Wrong in r1, fixed above:

1. **`Bool("True")` is `nil`** — Swift's `Bool.init?(String)` is case-sensitive
   (verified). r1's Boolean coercion would have made `typedValue` always nil,
   permanently disabling Save whenever a Boolean row existed.
2. **The editor *can* be open while a database is connected.** `showMainStudio`
   (`ContentView.swift:756-787`) awaits the whole of `hydrateDittoSelectedDatabase`
   before setting `isMainStudioViewPresented = true`, so the picker stays on screen
   over a fully open, syncing instance — and the "Database Config" button
   (`:206`) and iOS FAB (`:424`) are **not** gated during that window. Separately,
   `TransportConfigView.swift:255-306` and MCP `configure_transport` already edit
   and persist the active config while connected, and `save()` already calls
   `changeDittoLogLevel`, which compares against `dittoSelectedAppConfig`
   (`DittoManager.swift:422`). r1 asserted this twice as impossible.
3. **The `Form` does not scroll** — no `.formStyle` on it, so macOS defaults to
   `.columns`, a layout container. r1's central "the whole form scrolls" decision
   was a no-op as written, and moving the info panel inside it would have made the
   panel the first thing to vanish.
4. **`getAllDatabaseConfigs()` was omitted** from the schema work — positional
   column reads mean the new columns would never load.
5. **Migration atomicity** — r1 said "following the existing shape" without noticing
   that v3/v4 aren't transactional and the version bump sits outside; a half-applied
   v5 permanently bricks the config DB.
6. **`typedValue: Any?`** is not `Sendable` and crosses an actor boundary → closed
   `DQLValue` enum instead.
7. **`let id: UUID` excluded from `Codable`** would mint new ids on every decode,
   making `Equatable` always false (breaking the plan's own round-trip test and
   dirty tracking) and churning SwiftUI identity mid-typing → business-key ids.
8. **QR "sanitized copy"** of a reference type would have wiped the user's live
   scopes on displaying a QR code → explicit `sanitizedForSharing()`.
9. **The plist-can-seed rationale was false** — `DittoAppConfigLoader` is dead code
   that decodes JSON, not plists.
10. **QR byte figures were optimistic/value-dependent** — corrected (717 B / 33%
    baseline, 1033 B / 47% realistic, ~171-row ceiling).
11. **`needsSystemSettingsReset`** dropped: no-op with a permanent-brick path and a
    documented concurrency-contract violation. Reset is now a live action.
12. **Index-based a11y ids** contradict the codebase convention and silently assert
    about the wrong row after a delete.

## Still unverified — prove in Phase 3, don't assume
- Named parameters on the RHS of a **scalar** `ALTER SYSTEM SET` (docs show only
  the scope-map case)
- `UInt64 > Int64.max` and `JSONSerialization`'s ObjC-bridged objects surviving the
  SDK's argument encoder
- Exact `ALTER SYSTEM RESET ALL` syntax (`ALTER SYSTEM`, `SET`, `RESET` all appear
  in the SDK binary; the literal `RESET ALL` does not). `SHOW ALL` is confirmed
  working from the query editor.
- Whether `RESET ALL` reverts `updateTransportConfig`'s settings
- Doc-sourced, not code-verified: per-scope sync semantics, "not persisted",
  "device-local", "not enforced for remote query requests"
