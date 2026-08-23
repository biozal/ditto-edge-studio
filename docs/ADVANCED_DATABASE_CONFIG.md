# Advanced Database Configuration

Per-database **Collection Sync Scopes** and **Startup System Settings**, edited in the
Advanced Configuration section of the Register/Edit Database sheet. Feature parity with
the Edge Studio VS Code extension.

Both features are DQL `ALTER SYSTEM` statements — the Ditto Swift SDK 5.1.0 exposes no
typed API for either — and both are **in-memory only in the SDK**, so Edge Studio
stores them per database and re-applies them on every open.

Implementation: [`Models/AdvancedDatabaseSettings.swift`](../SwiftUI/EdgeStudio/Models/AdvancedDatabaseSettings.swift),
[`Data/AdvancedSettingsApplier.swift`](../SwiftUI/EdgeStudio/Data/AdvancedSettingsApplier.swift).

## Collection Sync Scopes

Controls where each user collection may synchronize.

```sql
ALTER SYSTEM SET USER_COLLECTION_SYNC_SCOPES = :scopes   -- {"orders": "SmallPeersOnly"}
```

| DQL value | UI label | Behavior |
|---|---|---|
| `AllPeers` | All Peers | Default — Ditto Server and Small Peers |
| `BigPeerOnly` | Big Peer Only | Ditto Server only |
| `SmallPeersOnly` | Small Peers Only | Small Peers only (note: plural) |
| `LocalPeerOnly` | Local Peer Only | Never leaves this device |

SDK constraints: must be set **before `sync.start()`**; cannot target system
collections (`__`-prefixed); device-local (never synced to peers); not enforced for
remote query requests.

### Fail-closed by design

Sync scopes are a **data-containment** control, so unlike every other setting in the
app they abort the operation rather than degrade:

| Situation | Behavior |
|---|---|
| `ALTER SYSTEM` statement throws | Database does **not** open; error surfaced |
| Read-back positively disagrees | Database does **not** open |
| Read-back cannot be parsed, or `SHOW` itself fails | Open proceeds, reported as **unverified** (the write succeeded; only the confirmation is unavailable) |
| Stored JSON is present but unreadable | That config is marked unopenable; the rest of the list still loads. The editor shows a banner and blocks Save until the scopes are re-entered or the loss is explicitly confirmed — otherwise "change the name and Save" quietly overwrote the unreadable JSON with `[]` and cleared the guard |
| Unknown scope value in stored JSON | Decode fails — no coercion to a default |
| Duplicate collection names | Hard error — never resolved to one scope |

An **empty** scope list still issues the statement. Returning early on "no scopes" meant
deleting the last row never took effect: the SDK kept enforcing the old scope while the UI
showed none, and the re-apply reported success having sent nothing. A scope that survives a
clear is reported as unverified, since only another writer could have set it.

Verification compares by **subset**, not exact equality: the instance may legitimately
carry scopes this config did not set (e.g. one applied by a query the user ran), and
demanding an exact match would refuse to open the database over an unrelated entry.

The read-back deliberately consults only known result keys. An earlier version fell back
to "the first value in the row", which on an unordered dictionary is arbitrary — making
verification pass or throw depending on the process's hash seed.

The reasoning: if a `LocalPeerOnly` scope silently fails to apply, that collection
replicates to the Ditto Server and the mesh while the UI still shows "Local Peer Only".
**Absence of containment configuration must never be indistinguishable from loss of
it.** A successful statement alone is not proof, which is why the read-back exists.

Startup settings take the opposite policy: a bad parameter is skipped and reported, and
the database still opens.

## Startup System Settings

Arbitrary parameters applied after Ditto opens and before sync or subscriptions start.

```sql
ALTER SYSTEM SET <parameter> = :value
```

Ditto publishes no exhaustive parameter list, so the editor accepts a free-form name
plus a typed value. Run `SHOW ALL` in the query editor to see every parameter and its
current value.

### Supported value types

| Type | Notes |
|---|---|
| String | Free text. **Empty is valid** — e.g. `transports_ble_adapter_mac` ships as `""`. |
| JSON | Any valid JSON document. Objects **and arrays** — `["a","b"]` gives a real array. |
| Integer | Falls back to `UInt64` above `Int64.max`, e.g. `dql_request_history_log_dump_limit` = `18446744073709551615`. |
| Double | Accepts scientific notation, e.g. `1.0000000000000001e-09`. |
| Boolean | True/False picker. Mapped case-insensitively — `Bool("True")` is `nil` in Swift. |

Arrays get no dedicated row editor this release; use the JSON type.

Edge Studio validates that the entered text **parses** as the chosen type. It does not
validate that the parameter exists or that the value is in range — the SDK throws for
those, and the failure is reported per row.

### Acknowledgement is persisted, and revoked when what it approved changes

A sensitive parameter (below) carries an `isAcknowledged` flag **stored with the
setting**, and the apply path refuses to execute a sensitive parameter without it. That
matters because settings can arrive without ever passing through the editor — a seeded
plist, a hand-edited database, a future import. An acknowledgement held only in the view
model would have meant those were applied with no prompt at all.

Three edits clear the flag, because approval was for a specific parameter *and* value:

- **Renaming the row** — `some_port` → `additional_p2p_trusted_ca_certs` is a different
  parameter.
- **Editing the value** — `127.0.0.1:9000` → `0.0.0.0:9000` turns a loopback listener into
  one on every interface.
- **Switching the type to Boolean when that seeds a value** — the seed overwrites the
  approved value with `True`, so `sqlite3_synchronous = FULL` acknowledged does not carry
  over to `= true`. Re-spelling an existing boolean (`true` → `True`) is *not* a value
  change and does not re-prompt.

### Reserved parameters (blocked)

These are managed by dedicated Edge Studio UI. Allowing them here would mean two
controls writing one parameter with order-dependent precedence:

`user_collection_sync_scopes` · `dql_strict_mode` · `mesh_chooser_max_wlan_clients` ·
`data_sync_enabled` · `transports_*` · `udp_*`

### Sensitive parameters (require acknowledgement)

Allowed, but the editor requires an explicit "I understand" toggle first:

| Pattern | Why |
|---|---|
| `*_listener_addr` | `metrics_exporter_prometheus_http_listener_addr` defaults to `0.0.0.0:9000` — a **listening socket on every interface** exporting database metrics |
| `*_certs` | `additional_p2p_trusted_ca_certs` adds a trusted CA (MITM surface) |
| `sqlite3_*` | Includes `synchronous` and `journal_mode` — the store's crash durability |
| a `port` name token | Network exposure. Token-matched, not a substring: `contains("port")` also matched "ex**port**er", flagging every `metrics_exporter_*` parameter and training users to tick the box unread |

### Limits

Value ≤ 4096 characters; ≤ 64 rows per list — enforced on the **apply path** as well as
in the editor, along with case-insensitive duplicate rejection, so a config from a
non-UI ingress cannot issue thousands of statements or two conflicting writes to one
parameter. Parameter names must match
`[A-Za-z_][A-Za-z0-9_]*` **whole-string** — the name is interpolated into DQL (identifiers
cannot be parameterized), so this is the injection guard. Values are always bound as
query arguments.

Names are compared case-insensitively for duplicates (DQL writes are case-insensitive
and read back lowercased) but written exactly as typed.

## Apply order

In `DittoManager.hydrateDittoSelectedDatabase`:

1. `Ditto.open`, offline license token, peer metadata
2. **User startup settings** (best-effort)
3. `updateTransportConfig`
4. `ALTER SYSTEM SET DQL_STRICT_MODE`
5. macOS `mesh_chooser_max_wlan_clients`
6. **Sync scopes** + read-back verification (fail-closed)
7. `logTransportReadback` — after every `ALTER SYSTEM`, so the log reflects reality
8. `sync.start()`

User settings run **first** so app-managed parameters always win. Sync scopes run
**last before sync**, as the SDK requires. `AdvancedSettingsApplierTests` asserts this
ordering with a recording fake, so a refactor that moves sync ahead of the scope
statement fails a test rather than leaking data.

`selectedDatabaseStartSync()` runs the **same** `OpenSequence`, so a restart re-applies
and re-verifies the scopes rather than trusting whatever is still in memory. That covers
every path that *starts* sync — the initial open, the Transport Settings restart, the
reset path, and the MCP `set_sync` tool.

What it does **not** cover: an `ALTER SYSTEM RESET ALL` typed into the query editor
against an instance that is **already syncing**. `ALTER SYSTEM` state is in-memory, so
that clears the scopes for the rest of the session, and the SDK requires scopes to be set
*before* `start_sync()` — re-applying them to a live session is therefore not a fix, which
is why Edge Studio does not pretend to offer one.

**Remedy, and it is the only one:** close the database and reopen it (or toggle sync off
and back on, which re-runs the sequence). Until then, treat the scopes shown in the editor
as the *stored* configuration, not as what the running session is enforcing.

## Reset to SDK defaults

The **Reset to SDK Defaults** button clears both lists and, when the edited database is
the one currently open, issues `ALTER SYSTEM RESET ALL` on save and then re-applies
everything Edge Studio manages: transport config, `DQL_STRICT_MODE`, the macOS mesh
setting, startup settings, and sync scopes.

A failed `RESET ALL` is surfaced to the user, not logged and forgotten: the saved config
would say "defaults" while the running instance still had the old parameters. The button
also has an **Undo Reset** affordance — it used to clear both lists irreversibly.

`RESET ALL` is **indiscriminate** — it resets every parameter, not just the user's — so
the re-apply is mandatory, not tidy-up. `SHOW ALL` lists `transports_ble_server_is_enabled`,
`transports_awdl_browse_enabled`, `transports_wifi_aware_client_is_enabled`,
`udp_server_enabled` and `data_sync_enabled`, i.e. the transport surface appears to live
in the same parameter store that `updateTransportConfig` writes to. If so, a reset
without the re-apply would silently **re-enable BLE/LAN/AWDL that the user turned off**.

> **Unverified:** whether `RESET ALL` actually reverts `updateTransportConfig`'s values
> has not been measured against a live instance. The re-apply makes the outcome correct
> either way. Worth confirming with a live database and recording the answer here.

For a database that is not open there is nothing to reset — `ALTER SYSTEM` state dies
with the instance, so the next open already starts from SDK defaults.

## Storage

> ⚠️ The local store is **not encrypted** despite its name — see
> [`CREDENTIAL_STORAGE.md`](CREDENTIAL_STORAGE.md). Sync scopes and startup settings are
> not secrets, but they share a file with the database tokens and API keys that are.

Schema **v5** adds two columns to `databaseConfigs`:

```sql
collectionSyncScopes TEXT NOT NULL DEFAULT '[]'
startupSettings      TEXT NOT NULL DEFAULT '[]'
```

JSON-in-TEXT rather than child tables: both lists are small, always read and written
with their parent config, and never queried independently.

The migration is exercised against real v1 and v4 tables built by
`SchemaMigrationV5Tests` — including the half-applied state (one column present,
`user_version` still 4) that the guards exist for.

**Every** migration step (2, 3, 4 and 5) is now atomic and idempotent: each adds only
the columns that are absent, and both the `ALTER TABLE`s and the `PRAGMA user_version`
bump share one transaction. Before this change, migrations 3 and 4 were not
transactional: a process death mid-migration left `user_version` behind with one column
present, the next launch hit "duplicate column name", `initialize()` threw, and **every
stored config and credential became permanently inaccessible**. All steps are now
guarded, and the 1→5 chain, the interrupted chain and re-running the chain are tested.

## QR code sharing

**Advanced settings are excluded from QR payloads.** Users re-enter them manually on the
receiving device.

Capacity was not the reason — it would have fit (a realistic config with 10 scopes and
10 settings measures ~47% of the 2200-byte cap). The reason is behavioral: silently
importing another device's sync scopes changes what syncs, in both directions. A scanned
`LocalPeerOnly` could stop a collection from syncing with no visible cause; a scanned
`AllPeers` could push data the sender meant to keep on-device.

Enforced in the QR layer on **both** sides: `encodePayload` encodes
`config.sanitizedForSharing()`, and `decode(from:)` clears both arrays regardless of
what the payload contained, so another client's scopes can never be imported silently.
`sanitizedForSharing()` returns a **new instance** — `DittoConfigForDatabase` is a
reference type, so clearing in place would delete the user's real scopes just by
displaying a QR code.

## Testing

- `EdgeStudioUnitTests/Models/AdvancedDatabaseSettingsTests.swift` — DQL raw values,
  strict decode, type coercion (incl. `UInt64.max` and the `Bool("True")` trap),
  validation rules, injection guard, `sanitizedForSharing` non-mutation
- `EdgeStudioUnitTests/Services/AdvancedSettingsApplierTests.swift` — apply order vs
  `sync.start()`, fail-closed scope policy, best-effort setting policy, read-back
  verification, reset
- `EdgeStudioIntegrationTests/Services/SQLCipherServiceTests.swift` — schema v5,
  migration idempotency, round-trip, and the "unrelated save preserves scopes" guard

Also covered: `AdvancedSettingsApplier.OpenSequence` is the production statement
sequence used by `hydrate`, so the ordering tests assert that `startSync` is never
reached when scopes fail — rather than restating the order inside the test body.

Also covered, from the production-readiness remediation
(`plans/2026-08-21-production-readiness-remediation.md`):

- `EdgeStudioUnitTests/ViewModels/SyncRuntimeStateTests.swift` — the state machine behind
  the sync indicator (a repeated stop still reads stopped; a repeated start still reads
  running). Note the limit: these drive `setRunning` directly, so they do **not** prove the
  funnels publish after the SDK call succeeds — that ordering is covered at the view-model
  layer by `SyncStatusViewModelTests`' failed-start test, and on the real paths only by the
  manual smoke step in the remediation plan
- `EdgeStudioUnitTests/Services/SQLCipherErrorPresentationTests.swift` — storage errors
  reach the user as their own text rather than "The operation couldn't be completed"
- `EdgeStudioIntegrationTests/Services/SQLCipherInitFailureTests.swift` — a failed
  `initialize()` releases its connection handle, across five simulated Retry presses

Still untested (needs credentials and a live instance): whether the SDK's argument
encoder accepts `UInt64 > Int64.max` and `JSONSerialization`'s bridged objects, whether
a named parameter is legal on the right-hand side of a scalar `ALTER SYSTEM SET`, and
the exact `ALTER SYSTEM RESET ALL` syntax.

**And "needs credentials" understates it: the live `ALTER SYSTEM` round-trip suite does
not exist at all.** There is no skipped, credential-gated test waiting for a plist — so
none of the four questions above is verified by *any* automated test, and adding
credentials would not change that. What is known is narrower and was established by a
throwaway SPM probe against SDK 5.1.0, not by this repo's suite:
`ALTER SYSTEM SET USER_COLLECTION_SYNC_SCOPES = :scopes` accepts a named parameter as the
whole right-hand side, accepts an empty map, and `SHOW user_collection_sync_scopes`
returns the shape `coerceScopeMap` parses.
