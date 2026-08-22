# Production-Readiness Remediation — Advanced Database Configuration (2026-08-21)

**Status:** plan only. No production code is written by this document.
**Status update 2026-08-21.** Executed so far:
- **Phase 0** — baseline validated (§9.1).
- **Phase 0b** — this change set's lint debt cleared; one deliberate deviation recorded
  in step 3.
- **Phase 1** — adjudication round complete (§9.2). Two independent adjudicators agree
  exactly: **8 confirmed, 2 refuted (S4, S7), 0 unproven.** S4 and S7 must not be fixed.
- **Phase 5a** — the SwiftLint build gate is now **real and fatal**, and proven so by
  negative test (a violation fails the build, exit 65) plus a positive control (comment
  prose does not). Coverage extended to the three test targets.
- **Phase 2 (C6)** — `changedRowCount()` deleted; the affected-row count now comes back
  from `execute` itself.
- **Phase 3 (C1, the blocker)** — Database ID is immutable after registration, enforced
  in the UI, in the SQL, and by a mutation-tested UI test.
- **Phase 4 (C5)** — identity post-conditions on all three sync-starting paths; the reset
  path no longer calls back into the actor for transports; S5's UI-test gate applied at
  the call site only (per both adjudicators' threat traces).
- **Phase 6a (C3)** — `isSyncEnabled` is no longer a stored guess: it is derived from
  `SyncRuntimeState`, which only `DittoManager`'s two start/stop funnels write, and only
  after the SDK call returns. All nine start/stop sites route through them. Proven by an
  executed negative lint test rather than a text count. The UI-level assertion stays
  unautomated (needs credentials) — recorded in §10 items 6 and 11, with the
  `accessibilityValue` shipped as the seam.
- **Phase 5b** — the `DittoManager` exclusion is dropped from `sync_start_choke_point`,
  which C3 is what made possible: the file went from nine `sync.start()`/`stop()` sites
  to one, inline-disabled.
- **Phase 6b** — the eight confirmed single-source findings, in five gated batches: S3
  (`LocalizedError`), S1/S2/S10 (editor), S9 (connection leak, mutation-tested), S8
  (`#if DEBUG` seams, proven by the Release build), S6 (throw instead of a silent
  return). **S4 and S7 were not touched** — both refuted in Phase 1, and a refutation is
  a result, not a gap.
- **Phase 7** — C2's dead code is gone (a deletion is its own wiring proof), and the
  documentation no longer asserts encryption the store does not have. D1 option 3 is
  recorded as a dated decision in `docs/CREDENTIAL_STORAGE.md`, with the type/file rename
  and options 1-2 folded into a tracked follow-up. The store is still plaintext — that is
  written down, not fixed.
- **Phase 8c** — readiness review **converged 2026-08-22**: two independent reviewers, both
  **SHIP**, zero blocking objections. 19 non-blocking observations; each re-verified by
  execution before being acted on. One real regression from Phase 6b found and fixed, three
  false claims corrected, two overstated guarantees narrowed, four §10 items added or
  promoted. Dispositions in §9.5. Two things are left to the user: commit hygiene
  (untracked `backup.ab` and `data/*.db` are not gitignored) and whether to commit.
- **Phase 8a/8b** — coverage measured per file; both pure files were already over 80%
  (91.23% / 86.27%), `SyncRuntimeState` is at 100%, and the SDK-boundary exemption is now
  written into `docs/TESTING.md` with the four exempt functions named and their measured
  numbers pasted in. No `Ditto.open` seam was built. **Phase 8c (the readiness review) has
  not been run** — it spawns independent reviewers, so it waits on the user.

Every gate green: **506** unit + **164** integration tests, all three builds (Debug macOS,
Release macOS, iOS Simulator), the **full** UI suite (15 tests, 10 credential-gated skips,
0 failures), changed-file lint **0 violations in 68 files**, `swiftformat --dryrun` 0/68,
repo-config lint 0 errors.

Remaining: nothing in the plan. The change set is **reviewed and shippable**; committing it
is the user's call.

**Revision 5 — APPROVED.** Converged after four adversarial review rounds (8
independent reviewers, two per round, none seeing another's output). Round 4: **both
reviewers APPROVE with zero blocking objections.** Every blocking objection across
rounds 1-3 was reproduced by execution before being accepted; two reviewer claims were
refuted. Revision 5 additionally applies the non-blocking corrections both round-4
reviewers flagged — a stale ledger cell that contradicted the accepted N6 refutation, a
post-Phase-0b threshold that contradicted its own gate, a C7 enumeration that was four
claims short, the hard-coded `in 51 files` count that drifts as phases add files, and
two implementation constraints on C3's funnels. What changed in each round:

*Round 1 — both reviewers BLOCKed on the same two objections:*
- The new SwiftLint custom rules omit `match_kinds`, so they match comment prose and
  string literals; C4 as originally specified would have failed every build → **N3**,
  §3.C4, Phase 5's mandatory step order.
- Two existing integration tests assert exactly the behavior C1 removes, so Phase 3's
  gate could never have gone green → Phase 3c's explicit rewrite dispositions.
- Non-blocking → **N4**: most of the fifteen error-severity lint violations are this
  change set's own, not pre-existing → Phase 0b.
- **Refuted:** `docs/ADVANCED_DATABASE_CONFIG.md:154-158` carries no false SwiftLint
  claim (§3.C4).

*Round 2 — one APPROVE, one BLOCK on two objections, both accepted:*
- The UI-test suite **skips** in this checkout (no `testDatabaseConfig.plist`) and
  `xcodebuild` exits 0, so a UI-test gate would report green having asserted nothing →
  **N6**, Phase 0's skip-counting rule, Phase 3c's credential-free route (plus **N5**:
  no addressable edit affordance exists), and Phase 6a's UI assertion demoted to §10.
- Phase 3's wiring grep (`"databaseId = ?"`) matches nine legitimate `WHERE` clauses and
  was unsatisfiable → anchored to the SET-list form.
- Non-blocking, accepted: the `force_unwrapping` at `TestHelpers.swift:138` is
  **pre-existing** (`HEAD:137`) — the split is 8 introduced / 7 pre-existing, not 9/6;
  swiftlint silently falls back to `included:` and reports a false clean, so gates now
  assert the linted **file count**; the execution-order line omitted Phase 0b.

*Round 3 — both reviewers BLOCKed, on different objections; all three accepted:*
- `sorted_imports` (`.swiftlint.yml:41`) and SwiftFormat's `--importgrouping
  testable-bottom` (`.swiftformat:38`) are **mutually unsatisfiable** for any file with
  `@testable`, so Phase 0b's "reorder the import block" would have made §8's
  `swiftformat --dryrun` gate permanently dirty and been reverted by `CLAUDE.md`'s own
  pre-commit sequence. Reproduced by execution → Phase 0b now resolves it in **config**
  (drop `sorted_imports`; SwiftFormat owns import order), and §8 states swiftformat's
  expected value as a gate.
- Phase 3c's UI test saved a dummy config into the **persisted** UI-test store with no
  addressable Delete control, which would flip six currently-skipping UI-test classes to
  `XCTFail`. → per-run unique id, `DeleteDatabaseMenuItem` identifier, `tearDown`
  cleanup, and a gate that re-runs the other six classes.
- Phase 7b's C7 edit list and gate grep covered only the `AES-256` phrasing; **15**
  false encryption claims exist across six files, so C7 would have been recorded closed
  with "secure encrypted storage" surviving two lines above an edited line. → full
  enumeration + a case-insensitive `grep -rniE "encrypt"` gate that requires reading,
  not counting.
- **Refuted (2 independent reviewers, accepted):** "the entire UI-test suite skips" was
  an overstatement. `AdvancedConfigurationUITests` — the class §8's UI command names —
  runs credential-free and passes; six other classes skip. **N6** is corrected, and the
  decisions that rested on it re-justified on their own evidence.
- Non-blocking, accepted: count reconciliation (9 → 8) in three places, `Self.`-qualified
  `createDatabaseConfig` call site, **N5** extended to the iOS swipe action and the
  Delete control, §9's pre-fill rule relaxed to permit cells measured while planning.

*Round 4 — both reviewers APPROVE, zero blocking objections.* Their non-blocking notes
are applied in revision 5: §9.1's stale "skips" cell for `AdvancedConfigurationUITests`
(contradicted the accepted N6 refutation); §9.1's post-0b threshold said 7 where the
gate says 1; C7's enumeration was 16 claims in its table plus 4 more in
`SQLCipherService.swift` (20 total, and the read-don't-count gate is the authority);
`in 51 files` is now re-derived per gate rather than hard-coded, with the zsh
word-splitting trap that produces the 145-file false clean written down; C3's funnels
must be `nonisolated` and take `ditto` as a parameter, and `SyncRuntimeState`'s
single-global scope is booked in §10 item 6; Phase 3's `updateDittoAppConfig` grep
expects 6 hits, not 4. Both reviewers also independently re-executed the plan's
load-bearing claims (C1's FK repro **and** its fix, both `match_kinds` probes, the
lint/format conflict, the 15/51 and 0/145 and 0/51 measurements) and all reproduced. One
reviewer additionally ran the plan's *proposed final* `.swiftlint.yml` over the whole
production tree and got exactly the three real `sync.start()` sites with all prose
suppressed — forward evidence that Phase 5 step 3 will not break the build.
**Scope:** make the uncommitted "Advanced Database Configuration" change set shippable.
Nothing else. No new features, no refactors that are not required by a confirmed defect.

**Inputs:** `plans/2026-08-21-production-readiness-remediation-PROMPT.md`,
`docs/FIX_VERIFICATION_RULE.md`, `plans/2026-08-19-advanced-database-config.md`,
`docs/ADVANCED_DATABASE_CONFIG.md`, `docs/CREDENTIAL_STORAGE.md`, `docs/TESTING.md`,
and the working tree (`git status` / `git diff`).

---

## 0. How this plan is executed (the anti-regression contract)

Every previous round on this change set failed in one of five ways. This plan binds
each phase to a rule that makes that failure detectable **before** the next phase
starts. These are not aspirations; a phase is not complete until its row is satisfied.

| # | Historical failure | Binding rule in this plan |
|---|---|---|
| 1 | **Fix-by-assertion** — method written, declared done, no production caller (`sanitizedForSharing`, then `setParameter`/`setValue`/`setType`, then `reapplyAdvancedSettings`) | Every phase that adds or changes a function names its **production call site** in its own "Wiring" line, and the phase's exit gate includes the literal `grep` that proves it. A phase whose grep returns only the definition and test files **fails**. |
| 2 | **Tests aimed at the fix, not the feature** — five tests certified a control the UI bypassed; the Database-ID test passed because its fixture had no child rows | Every test step states the **production path** it covers, and the fixture requirements that make it representative. For C1 specifically the fixture **must** contain a `history` child row — that omission is why the previous test passed. |
| 3 | **Hardening without a threat trace** — `.completeFileProtection` was correct alone and destructive in context | No security control is added or changed in this plan without a written trace of every other reader/writer of the thing being protected. Phase 1 (adjudication) is where `.completeFileProtection` is examined; it is **not** changed on sight. |
| 4 | **Batch-fixing a long list in one pass** | Phases are small and strictly sequential. Each phase ends with its own build+test+lint gate. **Do not start phase N+1 until phase N's gate is green and its result is written into §9.** Nothing in this plan is "and while we're in there". |
| 5 | **Claiming clean tooling without running it on the changed files** | Every gate runs lint/format on the explicit changed-file list, **tests included**, using the commands in §8 — not the repo default config alone, which sets `included: SwiftUI/EdgeStudio` and therefore never sees a test file. Measured, not assumed: doing this revealed **9** error-severity violations introduced by this change set that the prompt's baseline reported as pre-existing (**N4**), and that a first draft of this plan repeated. Phase 0b clears them before any behavioral work. |

Additionally, per `docs/FIX_VERIFICATION_RULE.md` §4: **the executor of a phase does
not sign it off.** Each phase's gate is verified by a reviewer that did not write the
change, checking (a) the wiring grep, (b) that the tests exercise the shipping path,
(c) that nothing worse was introduced.

---

## 1. Confirmation ledger

Per `docs/FIX_VERIFICATION_RULE.md` §1, a finding is actionable at two independent
confirmations. This table records what is actionable and why.

| ID | Finding | Sources | Independent evidence gathered while writing this plan |
|---|---|---|---|
| **C1** | `updateDatabaseConfig` writes `databaseId` in the `SET` list; four child FKs have `ON DELETE CASCADE` and **no `ON UPDATE`**, with `PRAGMA foreign_keys = ON` | 2 reviewers + executed repro | **Reproduced independently.** `SQLCipherService.swift:648-691` sets `databaseId = ?` with `WHERE _id = ?`; FKs at `:363, :374, :385, :399`; pragma at `:99`. Reproduced on SQLite 3.50.6 with the real table shapes: `UPDATE databaseConfigs SET name=…, databaseId=… WHERE _id=…` with one `history` child row → `FOREIGN KEY constraint failed (19)`, `changes=0`, parent row unchanged. Because `executeWithParameters` (`:1017-1020`) treats any non-`DONE`/`OK` step result as fatal, the whole save throws — the name/token/scope edits submitted with it are lost. |
| **C2** | `reapplyAdvancedSettings` is dead code whose doc comment names a caller that does not exist | 2 reviewers + grep | **Confirmed.** `grep -rn reapplyAdvancedSettings --include=*.swift .` returns exactly two hits: the definition (`DittoManager.swift:315`) and a comment referring to it (`:208`). Zero callers, including tests. |
| **C3** | Sync stopped by a non-toolbar path is not reflected in `SyncStatusViewModel.isSyncEnabled` | 2 reviewers + read | **Confirmed, with a reachability correction — see §3.C3.** `isSyncEnabled` (`SyncStatusViewModel.swift:31`) is written only by `toggleSync` (`:126-134`) and `reset` (`:113`). `DittoManager.resetSystemSettingsToDefaults` stops sync at `:369` and, on the error path, deliberately leaves it stopped (`:399-405`) without touching it. `TransportConfigView.applyTransportConfig` (`:298-315`) swallows a `selectedDatabaseStartSync()` throw into `syncStartError`, restarts observers, then rethrows — sync is off and `isSyncEnabled` still reads `true`. |
| **C4** | The SwiftLint rules that replaced a deleted test enforce nothing | 2 reviewers + read | **Confirmed on all three counts.** Build phase is `swiftlint lint --config .swiftlint.yml --quiet \|\| true` (`project.pbxproj:370`) — exit status discarded. `.github/` **does not exist** (`ls: .github: No such file or directory`); `.git/hooks/` has no non-sample hooks. `.swiftlint.yml:98` excludes `.*/(AdvancedSettingsApplier\|DittoManager)\.swift`, and `DittoManager.swift` holds **all three** `sync.start()` sites (`:252`, `:391`, `:429`). Also: `included: SwiftUI/EdgeStudio` (`:6-7`) means no test file is ever linted by that config. |
| **C5** | The reset path lacks the identity post-condition `hydrate` has | 2 reviewers + read | **Confirmed.** `hydrate` guards with `guard dittoSelectedApp === ditto` (`DittoManager.swift:267`). `resetSystemSettingsToDefaults` has no such guard, and its `applyTransportConfig` closure (`:380-386`) calls back into the actor via `self.applyTransportConfig(...)`, which re-reads `dittoSelectedApp` (`:554`) rather than the captured `ditto` — so it either throws "No Ditto app is currently selected" or configures a **different** instance while the `ALTER SYSTEM` statements and `sync.start()` target the captured one. `selectedDatabaseStartSync` (`:412-441`) likewise has no post-condition. |
| **C6** | `changedRowCount()` is latently wrong | 2 reviewers + read | **Confirmed.** `changedRowCount()` (`:993-995`) reads connection-wide `sqlite3_changes(db)` *after* `executeWithParameters` has finalized its statement (`:1007` `defer`). Correct only because nothing on that path suspends between the two. |
| **C7** | Documentation still contains false statements | 2 reviewers + grep | **Confirmed.** `grep -rn "encrypted at rest"` finds five repository headers — `HistoryRepository.swift:11`, `DatabaseRepository.swift:16`, `FavoritesRepository.swift:11`, `ObservableRepository.swift:13`, `SubscriptionsRepository.swift:13` — plus the test named `` `Credentials stored encrypted at rest` `` (`SQLCipherServiceTests.swift:377`). `docs/ADVANCED_DATABASE_CONFIG.md` has a duplicated `### Acknowledgement is persisted` heading (`:96` and `:102`) and a garbled splice at `:210-211` ("…inside the same transaction. — both `ALTER TABLE`s and the `PRAGMA user_version` bump share one transaction, and each column is added only if absent."). |

### 1.1 Findings this plan adds (and their confirmation status)

Discovered while gathering the evidence above. Recorded here so they are not laundered
into the fix list without adjudication.

| ID | Finding | Status |
|---|---|---|
| **N1** | The live `ALTER SYSTEM` round-trip suite that `plans/2026-08-19-advanced-database-config.md` made the Phase-3 gate (`AlterSystemTests.swift`, "live suite reports **`0 skipped`**") **was never written.** `find SwiftUI -name "*AlterSystem*"` returns nothing; `EdgeStudioIntegrationTests/Services/` contains only `KeychainServiceTests`, `SchemaMigrationV5Tests`, `SQLCipherServiceTests`. | Author-confirmed by command (1 source). **Not a code defect** — it is a documentation-truth issue: the feature plan's own Phase-3 gate was never met, and `docs/ADVANCED_DATABASE_CONFIG.md:251-254` correctly says so. Handled in Phase 7 as a **known-unverified** entry, not as a fix. Writing that suite is out of scope (needs credentials + a scheme `environmentVariables` change). |
| **N2** | `DittoManager.localDirectoryPath` (`:479-494`) embeds `"\(name.lowercased())-\(databaseId)"`. **`name` is already user-editable**, so renaming a database already orphans its on-disk Ditto store today — a pre-existing behavior this change set does not touch. | Author-confirmed (1 source). **Deliberately not fixed** — pre-existing, out of scope, and directly relevant to the C1 decision (see §3.C1). Recorded so the C1 rationale is auditable. |
| **N3** | Both new custom SwiftLint rules omit `match_kinds`, so they match **comment prose and string literals**, not just code. This is a defect in `.swiftlint.yml` — a file this change set modifies (+22 lines) — and it makes the C4 fix as originally specified break every build. | **Confirmed: 2 independent reviewers + author execution.** Verified with swiftlint 0.65.0: a file whose only occurrence is `// A comment mentioning sync.start()` produces `error: … (sync_start_choke_point)`, exit 2; with `match_kinds: [identifier]` the same file is clean while a real `try ditto.sync.start()` is still reported. Running the repo config with `DittoManager` un-excluded yields 6 hits at `:252, :288, :309, :391, :417, :429`, of which `:288, :309, :417` are comments. **Fixed by §3.C4 / Phase 5.** |
| **N5** | `DatabaseCard` declares `var onEdit: () -> Void` (`DatabaseCard.swift:5`) but its body never uses it; the real affordances are unidentified `contextMenu` Buttons (`ContentView.swift:434`/`:437`, `DatabaseListPanel.swift:63`/`:69`) plus an iOS swipe action (`DatabaseList.swift:30-34`), and `DatabaseList.swift:13` passes `onEdit: {}`. So there is no addressable edit **or delete** control in the accessibility tree. | Author-confirmed by grep + read, and independently reported by 2 reviewers. **Not fixed beyond the minimum C1 needs:** Phase 3a adds `EditDatabaseMenuItem` and `DeleteDatabaseMenuItem` to the two macOS context menus so the C1 UI test can reach the editor and clean up. The dead parameter, the empty closure and the iOS swipe action are pre-existing, out of scope, and recorded in §9.4. |
| **N6** | `testDatabaseConfig.plist` is absent from this checkout (`find . -name "testDatabaseConfig*"` → only the `.example`), so **every UI test that goes through `openStudio()` / `addDatabasesFromPlist()` `XCTSkip`s** (`UITestBase.swift:259`, `:339`) and `xcodebuild` exits 0. That is `AppLaunchUITests`, `DatabaseManagementUITests`, `NavigationLifecycleUITests`, `NavigationSmokeUITests`, `QueryExecutionUITests`, `QueryResultsUITests`. | **Confirmed: 1 reviewer + author execution.** **PARTLY REFUTED by 2 further independent reviewers, and the refutation is accepted:** `AdvancedConfigurationUITests` — the one class §8's UI command actually names — does **not** skip. Verified: it never calls `openStudio()`/`addDatabasesFromPlist()`; it taps `AddDatabaseButton`, drives the editor sheet credential-free, and **cancels** without saving (`AdvancedConfigurationUITests.swift:24-115`). So the prompt's "the UI test passes" is **correct** for that class, and an earlier draft of this plan overstated N6 as "the entire UI-test suite skips". The derived decisions stand on their own evidence: skip-counting (a real hazard for the other six classes), Phase 3c's credential-free route (necessary because there is no seeded database to edit), and Phase 6a's demotion (reading sync state genuinely needs an open database and therefore credentials). |
| **N4** | Eight of the fifteen error-severity lint violations on the changed-file list are **introduced by this change set**, not pre-existing — including 2 `sync_scopes_via_applier` hits in a test file it creates, which are string-literal false positives of N3. The other 7 (6 `sorted_imports` + 1 `force_unwrapping` present in `HEAD`) are pre-existing. | **Confirmed: 3 independent reviewers + author execution** (§9.1). **Fixed by Phase 0b.** Two earlier drafts got the split wrong in opposite directions — failure mode 5 applied to this plan's own claims. |

---

## 2. The two explicit decisions

### D1 — the unencrypted credential store

`docs/CREDENTIAL_STORAGE.md` proves the store is plaintext: no SQLCipher product is
linked, `import SQLite3` (`SQLCipherService.swift:3`) is Apple's system libsqlite3
where `PRAGMA key` is a silent no-op, and the live file begins with `SQLite format 3`.

**Decision: option 3 — accept plaintext for this release, purge every contrary claim,
and file option 1 (link SQLCipher + `sqlcipher_export` migration) as a tracked
follow-up with its own plan. This does not block the release of this change set.**

Rationale, stated so it can be argued with rather than inferred:

1. **It is not a regression of this change set.** The store was plaintext before this
   work began. The two columns this feature adds (`collectionSyncScopes`,
   `startupSettings`) hold sync-scope names and tuning parameters — not secrets.
   Blocking a feature change set on a pre-existing platform issue it did not worsen is
   the wrong gate.
2. **Option 1 and option 2 are both larger and riskier than everything else in this
   plan combined**, and each changes the on-disk format or the key lifecycle for
   existing installs. Bundling either here is precisely historical failure mode 4
   (batch-fixing) plus mode 3 (hardening without a threat trace) — and the threat trace
   for the key file has already produced one data-destruction path on this repo.
3. **The dishonesty is what is fixable now, cheaply and verifiably**, and that is what
   C7 and Phase 7 do.

**What ships under option 3 (Phase 7):**

- Every remaining "encrypted at rest with AES-256 (SQLCipher)" claim in code is removed
  and replaced with a one-line pointer to `docs/CREDENTIAL_STORAGE.md`.
- The misnamed integration test is renamed to describe what it actually asserts.
- `docs/CREDENTIAL_STORAGE.md` gains a "Decision" section recording this choice, its
  date, and the follow-up.

**What deliberately does *not* ship, and why** (these are the parts a reviewer should
push back on if they disagree — the objection is legitimate, the answer is a judgement
call the user can overrule):

- **The type is not renamed** (`SQLCipherService` → e.g. `LocalConfigurationStore`).
  `CREDENTIAL_STORAGE.md:69-71` lists renaming as part of option 3, and the argument
  for it is real. Against it: the type declaration already carries an unmissable
  16-line `⚠️ THE STORE IS NOT CURRENTLY ENCRYPTED` header
  (`SQLCipherService.swift:20-32`), so it no longer misleads anyone reading it; the
  rename touches `SQLCipherService`, `SQLCipherError`, `SQLCipherContext`,
  `SQLCipherServiceTests`, `SchemaMigrationV5Tests` and every repository — a large
  cosmetic diff added to an already-large change set under review, with zero security
  benefit; and the option-1 follow-up replaces the implementation anyway, which is the
  cheap moment to rename. **Folded into the option-1 follow-up.**
- **The on-disk file is not renamed** (`ditto_encrypted.db`). Renaming it requires a
  migration of every existing install whose failure mode is losing every stored
  credential — a data-destruction risk taken on for a filename that is not user-visible.
  Under option 1 the file is rewritten anyway. **Folded into the option-1 follow-up.**

**Reversing this decision** is a one-line change to §5: replace Phase 7 with the
option-1 or option-2 work, which needs its own plan and its own review cycle. Do not
attempt it inside this plan's phases.

### D2 — the coverage gate

Measured coverage of the new code is ~35-40% against `docs/TESTING.md`'s mandatory 80%
(`docs/TESTING.md:31`, `:1633`). `DittoManager` sits at 3.38%, with
`hydrateDittoSelectedDatabase` at 0/200 lines because it needs a live `Ditto`.

**Decision: do both halves — raise per-file coverage on the code that *is* extractable,
and renegotiate the gate in writing for the code that is not. Do not inject a seam
around `Ditto.open`.**

1. **Enforce ≥80% per file on the new, pure files** — `Models/AdvancedDatabaseSettings.swift`
   and `Data/AdvancedSettingsApplier.swift`. These already have the `DQLExecuting`
   protocol seam and a recording fake, so this is achievable without credentials, and
   it is where a bug leaks data. Measured **per file**, not aggregate (Phase 8).
2. **Extract the two pure decisions that already exist inside `hydrate`** and cover
   them directly (Phase 4): `createDatabaseConfig` (URL-scheme/host validation) and a
   new `transportFlags(for:isUITesting:)` static. Both are pure, currently uncovered,
   and both are needed by Phase 4 anyway (C5). This is a real coverage gain aimed at
   the **feature path**, not at the fix.
3. **Do not build an injection seam around `Ditto.open`.** Wrapping `Ditto.open` +
   `setOfflineOnlyLicenseToken` + `presence.setPeerMetadata` + `auth.expirationHandler`
   + `updateTransportConfig` in a protocol is a large architectural change to the most
   safety-critical function in the app, motivated by a coverage number with no failing
   behavior behind it. That is historical failure mode 3/4. **Refused, with reason.**
4. **Renegotiate the gate in writing** (Phase 8), by amending `docs/TESTING.md` with a
   named, bounded exemption rather than silently missing the number:

   > **SDK-boundary exemption.** Code whose body is a sequence of Ditto SDK calls that
   > cannot be constructed without a live `Ditto` instance is exempt from the 80% rule,
   > **on three conditions**: (a) every *decision* in it — validation, gating,
   > ordering, failure policy — is extracted into a pure type or static and covered to
   > ≥80% there; (b) the residual shim is listed by name in this section with its
   > measured coverage; (c) the shim's behavior is covered by a live/manual procedure
   > recorded in the owning plan. Listing a file here is a claim that (a) holds, and a
   > reviewer may reject it.
   >
   > Currently exempt: `Data/DittoManager.swift` — `hydrateDittoSelectedDatabase`,
   > `resetSystemSettingsToDefaults`, `selectedDatabaseStartSync`.

   The measured numbers from Phase 8 are pasted into that section. **The discrepancy
   is not left unstated anywhere.**

---

## 3. Fix decisions for the confirmed defects

### C1 — choose the *smallest* fix, not the migration

**Chosen: keep `WHERE _id = ?`, remove `databaseId` from the `SET` list, and make the
Database ID field non-editable for an existing config.** Rejected: the v6 migration
with `ON UPDATE CASCADE`.

Why the migration is refused:

- SQLite cannot alter a foreign key. `ON UPDATE CASCADE` requires **recreating all four
  child tables** (`subscriptions`, `history`, `favorites`, `observables`) inside a
  transaction with the `foreign_keys` pragma manipulated around it. This change set
  currently contains **no schema change at all** in the remediation; adding one
  reintroduces the exact bricking class that `migrateToVersion5` was written to close.
- Even a correct migration would not make the operation safe: `localDirectoryPath`
  (`:479-494`) embeds `name-databaseId`, so changing the id orphans the on-disk Ditto
  store. A correct "change database identity" feature also has to move that directory —
  and as **N2** records, the same directory is *already* orphaned by a plain rename
  today. Fixing identity-change properly is a feature, not a remediation.
- Nothing needs it. All four `updateDittoAppConfig` call sites either cannot change
  `databaseId` (`DittoManager.swift:621` log level; `MCPToolHandlers.swift:544`
  transport; `TransportConfigView.swift:283` transport) or are the editor
  (`DatabaseEditorView.swift:1158`). QR import uses `addDittoAppConfig`
  (`ContentView.swift:770`), as does seeding (`:747`). **Verified by grep** — recorded
  as a Phase 3 gate.

**Ordering hazard inside this fix.** Change the UI **first**, then the SQL. Reversed,
there is a window where the field is still editable and the write silently drops the
change — which is *worse* than today's loud failure. Both land in the same phase and
the same commit-ready state; the sub-order is not optional.

**Secondary correctness detail.** `save()` currently persists
`databaseId.trimmingCharacters(...)` (`DatabaseEditorView.swift:1133`, `:1138`). Once
`updateDatabaseConfig` stops writing the column, an existing config with an untrimmed
stored id would end up with a trimmed value in the in-memory cache
(`DatabaseRepository.cachedConfigs`) and in `refreshSelectedConfigIfMatching`, but the
untrimmed value on disk. Fix in the same phase: for `!isNewItem`, persist
`original.databaseId` verbatim.

### C2 — delete it, and delete the claim it was written to support

**Chosen: delete `reapplyAdvancedSettings` and remove the mitigation claim.** Rejected:
wiring it into `QueryService` / the MCP `execute_dql` tool.

Why wiring is refused:

- Wiring it means detecting `ALTER SYSTEM` inside arbitrary user DQL — a parser, on the
  hot path of the query editor, with a false-negative mode that fails silently.
- More decisively, it would not work. The SDK's own guard string (quoted in
  `plans/2026-08-19-advanced-database-config.md:63-65`) is *"value of system parameter
  updated while sync is active; please set sync scopes before calling `start_sync()`"*,
  and `resetSystemSettingsToDefaults` already stops sync before re-applying for exactly
  this reason (`DittoManager.swift:363-369`). `reapplyAdvancedSettings` re-applies
  scopes **without** stopping sync — by its own doc comment (`:303-304`). Wiring it
  would install a control that appears to restore containment and may not. That is
  security theater, and worse than the honest gap.

What replaces it: the real, enforceable invariant already exists — every path that
*starts* sync goes through `AdvancedSettingsApplier.OpenSequence`, which applies and
verifies scopes first. Phase 5 makes the lint gate that protects it real. The residual
gap — a user typing `ALTER SYSTEM RESET ALL` into the query editor against a
**running** instance — is documented as a known limitation with the correct user
remedy (close and reopen the database), not papered over.

### C3 — one source of truth for "is sync running"

**Chosen: a small `@MainActor @Observable SyncRuntimeState`, published from the only
two places that start or stop sync, and read by `SyncStatusViewModel.isSyncEnabled`.**

Reachability, stated precisely — a reviewer should hold this to account rather than
accept the prompt's framing unexamined:

- **`TransportConfigView` restart path: reachable in ordinary use.** It lives inside
  `MainStudioView`, where the toolbar is on screen. When `selectedDatabaseStartSync()`
  throws (fail-closed scopes), sync is off and `isSyncEnabled` still reads `true`: the
  indicator is green, and the user's first recovery tap takes the **stop** branch
  (`SyncStatusViewModel.swift:126-130`) — a no-op on already-stopped sync — so it takes
  two taps to restart. **This alone justifies the fix.**
- **`resetSystemSettingsToDefaults` path: narrower than the prompt implies.**
  `ContentView.body:35-46` swaps `MainStudioView` in for `macOSPickerView`, and the
  editor sheet is attached to the picker (`:297-326`, `:351-366`) — so the editor and
  the studio toolbar are never on screen together. The live-instance reset is reachable
  while the picker is up with an instance still open (the `hydrate` await window, where
  `dittoSelectedApp` is assigned at `:188` well before `isMainStudioViewPresented`
  flips; plus iPad multi-window). The visible symptom is deferred rather than absent:
  `MainStudioView`'s VM is `@State`-constructed per presentation
  (`MainStudioView.swift:208`) with `isSyncEnabled = true` (`:31`), so the next studio
  presentation shows green over stopped sync.
- **The default is itself a guess.** `isSyncEnabled = true` is documented as true
  "because hydration starts sync" (`:28-31`). Deriving it from the actual state removes
  the guess, which is why this is the right shape rather than patching two call sites.

Design (kept deliberately small):

- New `Views/StudioView/ViewModels/SyncRuntimeState.swift`: `@MainActor @Observable
  final class SyncRuntimeState { static let shared = SyncRuntimeState();
  private(set) var isRunning = false; func setRunning(_ running: Bool) }`.
- `DittoManager` gains two private funnels — `startSyncNow(_ ditto: Ditto) async throws`
  and `stopSyncNow(_ ditto: Ditto) async` — each performing the existing
  `Task.detached(priority: .utility)` start/stop **and** publishing to
  `SyncRuntimeState.shared` on the MainActor. Every existing `ditto.sync.start()` /
  `ditto.sync.stop()` in the file is rewritten to call them. After this, the file
  contains exactly one `sync.start(` and one `sync.stop(` — which is what makes C4's
  lint rule enforceable rather than decorative.
- `SyncStatusViewModel`: `isSyncEnabled` becomes a computed read of an **injected**
  `SyncRuntimeState` (default `.shared`); `toggleSync` and `reset` stop writing it.
  Injection keeps it unit-testable — a global read would not be.

Two implementation constraints, both raised in review:

- **Declare the funnels `nonisolated`** and have them take `ditto` as a parameter, never
  re-read `dittoSelectedApp`. Actor-isolated funnels would be awaited from inside the
  `@Sendable startSync:` closure, at the precise point `DittoManager.swift:243-247`
  documents as a deliberately non-suspending re-entrancy window. The existing
  `Task.detached(...).value` already suspends there, so this is not a new hazard class —
  but taking `ditto` as a parameter is what keeps it from becoming one.
- **`SyncRuntimeState` is a single global, so it describes "the session", not "an
  instance".** On the abort paths (`hydrate:273` and the two Phase 4 post-conditions)
  the *losing* instance is stopped, and publishing `false` there could contradict a
  winning instance that is still syncing. iPad multi-window concurrent-open only, and
  strictly narrower than today's behavior (where the flag is a hard-coded `true`).
  Recorded in §10 item 6 rather than solved with per-instance state, which would need an
  identity the view layer does not have.

Failure mode this must not introduce: if a funnel throws *after* publishing, the state
lies in the other direction. Therefore publish **after** the detached start/stop
returns for start, and unconditionally for stop (a stop that throws still leaves sync
down). Asserted by test in Phase 6.

### C5 — post-condition + stop calling back into the actor

Two changes, both in `DittoManager`:

1. Add `guard dittoSelectedApp === ditto else { … }` after `sequence.run` in
   `resetSystemSettingsToDefaults` and in `selectedDatabaseStartSync`, mirroring
   `hydrate:267-275` — including its comment's reasoning (stop only *our* instance;
   never enter the shared teardown, which acts on whatever is currently selected).
2. Replace the reset path's `applyTransportConfig` closure (`:380-386`) so it captures
   `ditto` and calls `ditto.updateTransportConfig { … }` **directly**, exactly as
   `hydrate:228-238` does — removing the `self.applyTransportConfig(...)` re-read of
   `dittoSelectedApp` that is the actual defect. The three Bools come from
   `Self.transportFlags(for: config, isUITesting:)`, the pure static extracted in
   Phase 4.

**Scope guard.** `transportFlags` including the UI-test gate would also resolve
single-source finding **S5** (the reset path bypassing `isRunningUITests()`). That is
why **S5 is adjudicated in Phase 1**, before Phase 4 writes the helper. If S5 is
refuted, Phase 4 writes `transportFlags(for:isUITesting:)` such that reset passes
`isUITesting: false`, preserving today's behavior exactly, and records the refutation.
The helper is written either way — the *value* passed depends on the verdict. This is
the plan not pre-deciding an unconfirmed finding.

### C6 — return the count instead of re-reading the connection

`executeWithParameters` returns `Int` (`sqlite3_changes(db)` read immediately after
`sqlite3_step` returns, before the `defer`-ed finalize); `execute(_:_:)` becomes
`@discardableResult -> Int`; `updateDatabaseConfig` uses the returned value;
`changedRowCount()` is **deleted**. Non-DML statements return a stale count that every
caller ignores — noted so it is not mistaken for a bug later.

### C4 — make the gate real; withdraw only the claims that are actually false

**The rules are broken in a way the prompt did not name, and it must be fixed first or
this phase bricks the build.** Neither custom rule declares `match_kinds`, and
SwiftLint's default is to match **every** syntax kind — including comment prose and
string literals. Verified by execution (swiftlint 0.65.0):

- A probe file whose only occurrence is `// A comment mentioning sync.start() in prose.`
  produces `error: … (sync_start_choke_point)` and `swiftlint` exits **2**.
- Running the *repo* config with `DittoManager` dropped from `excluded` — exactly what
  this phase does — yields **six** error-severity hits in `DittoManager.swift`:
  `:252`, `:288`, `:309`, `:391`, `:417`, `:429`. Three of those (`:288`, `:309`,
  `:417`) are **prose in comments**, not call sites. So "after C3 there is exactly one
  legitimate `sync.start(`" is false, and dropping `|| true` with the exclusion removed
  would fail all three builds on comment text — leaving the executor to either delete
  the comments that document why the guards exist, or revert C4 to the defect it was
  meant to close.
- Both `sync_scopes_via_applier` hits in today's baseline
  (`AdvancedSettingsApplierTests.swift:277`, `:548`) are **string literals**, for the
  same reason.
- With `match_kinds: [identifier]`, the same probe reports the real
  `try ditto.sync.start()` and **not** the comment, and **not** a
  `"log line about sync.start()"` string literal. Verified.

Therefore:

- **`.swiftlint.yml` — `sync_start_choke_point`:** add `match_kinds: [identifier]`.
  This is what makes the rule mean "a call", and it is a precondition for every other
  C4 step.
- **`.swiftlint.yml` — `sync_scopes_via_applier`:** add
  `excluded_match_kinds: [comment, doccomment]` — **not** `match_kinds: [identifier]`.
  The production statement it guards *is* a string literal
  (`AdvancedSettingsDQL.setSyncScopesQuery`, `AdvancedDatabaseSettings.swift:490`), so
  restricting it to identifiers would turn the rule into a permanent no-op that reports
  clean forever. It must keep matching strings, and the two test-file hits are resolved
  at source in Phase 0b (below) rather than silenced.
- **`.swiftlint.yml`:** prefix the `sync_scopes_via_applier` regex with `(?i)` so a
  lowercase `user_collection_sync_scopes` is caught.
- **`.swiftlint.yml:98`:** delete `DittoManager` from the `sync_start_choke_point`
  `excluded` regex, leaving `.*/AdvancedSettingsApplier\.swift`. After C3 and the
  `match_kinds` fix there is exactly **one** matching call in the file — the
  `sync.start(` inside `startSyncNow` — carrying one inline
  `// swiftlint:disable:next sync_start_choke_point` with a one-line reason.
  **No disable on `stopSyncNow`:** the regex only matches `start`, so a disable there
  would itself violate the default-enabled `superfluous_disable_command` rule.
- **`project.pbxproj:370`:** drop `|| true` — **last**, only after the lint run above is
  clean. Do **not** add `--strict`: with `--strict` every warning-severity rule
  (`force_unwrapping`, `todos_fixmes`, `no_print_statements`) becomes a build error
  across the whole app — a far larger change than the defect. Dropping `|| true` makes
  **error-severity** violations fail the build, and both custom rules are already
  `severity: error`. That is the targeted fix.
- **Withdraw the over-claim, keep the rule.** The reviewers defeated
  `sync_start_choke_point` with `let s = ditto.sync; try s.start()`. No regex can close
  that, and pretending otherwise is the failure this whole document exists to stop. The
  rule's `message` and its comment block at `.swiftlint.yml:89-99` are rewritten to say
  what is true — the regex catches the direct form and is a speed bump; the
  **enforceable** guarantees are the `OpenSequence` type, its ordering tests, and (after
  C3) the two-funnel concentration of `sync.start`/`sync.stop`. The rewrite must also
  state the funnels' own residual gap: **`startSyncNow` is itself unguarded**, so a
  future `DittoManager` path could call it outside an `OpenSequence` and lint would stay
  silent. That is still strictly stronger than today (whole file excluded, exit status
  discarded), but it is not a proof, and the comment must not imply one.
  **Correction to an earlier draft of this plan:** it also named
  `docs/ADVANCED_DATABASE_CONFIG.md:154-158` as carrying a false enforcement claim.
  That is wrong — `grep -rni swiftlint docs/ADVANCED_DATABASE_CONFIG.md` returns
  nothing, and `:156-158` claims only that `AdvancedSettingsApplierTests` asserts the
  ordering, which is **true**. That file is not edited by this phase. (Its separate,
  genuinely false claim about re-applying scopes is C2's, handled in Phase 7a.)
- **CI is deliberately not added.** There is no `.github/` and no hook infrastructure;
  standing up CI for this repo is a separate project with its own decisions (runner,
  simulator provisioning, credential handling for the live suites). Recorded as
  deliberately deferred with reason, per `FIX_VERIFICATION_RULE.md` "What to write
  down". The build-phase failure is the gate that ships.

---

## 4. Single-source findings — adjudication, not fixes

Per `docs/FIX_VERIFICATION_RULE.md` §2, none of these is touched before a targeted
adjudication round confirms it. **Phase 1 is that round.** Adjudicators are told the
finding is disputed and asked to confirm **or refute** with `file:line` evidence and a
concrete failure scenario.

| ID | Finding | If confirmed | If refuted |
|---|---|---|---|
| **S1** | `ViewModel.setType` seeds `value = "True"` without revoking a sensitive row's `isAcknowledged` (`DatabaseEditorView.swift:1027-1039`) | Phase 6: revoke in `setType` when the seeded value changes and the row is sensitive, mirroring `setValue:1015-1022`. Test through `bindingForSettingType` (`:628-635`), the binding the picker actually uses. | Record refutation + evidence in §9. Note the likely refutation: `isSensitiveParameter` matches on the *name*, and `setType` never changes the name, so the acknowledged (name, value) pair only changes when a **Boolean** seed overwrites a non-Boolean value — a narrow path. |
| **S2** | Boolean `Picker` tags are exactly `"True"`/`"False"` (`:562-566`, `AdvancedDatabaseSettings.swift:225`), so a stored lowercase `true` renders with no selection — and `DatabaseEditorAdvancedViewModelTests:317` asserts that state as correct | Phase 6: canonicalize the row's `value` to `"True"`/`"False"` when a `.boolean` row loads with a case-variant, and **correct the test** (a test asserting the defect is worse than no test). | Record + evidence. |
| **S3** | `SQLCipherError` conforms to `CustomStringConvertible` but not `LocalizedError` (`:1087`), so every storage error surfaces as "The operation couldn't be completed. (… error N.)" — including `keyFileUnreadable`'s guidance and the duplicate-Database-ID case (`ContentView.swift:505-510`, `Ditto_Edge_StudioApp.swift:127-131`) | Phase 6: add `LocalizedError` with `errorDescription { description }`. One-line, no behavior change beyond the string. **Author note:** independently read and consistent with the claim — the alert renders `appState.error?.localizedDescription` for any non-`AppError`. Still routed through adjudication, per the rule. | Record + evidence. |
| **S4** | Corrupt `startupSettings` JSON decodes leniently to `[]` (`DatabaseRepository.swift:62-71`) and is silently overwritten with `"[]"` on the next save — no banner, no discard toggle, unlike the sync-scope path | Phase 6: **narrowest form only** — surface a non-blocking banner reusing the existing `lastApplyFailures` presentation (`DatabaseEditorView.swift:471-493`). Do **not** add a second blocking discard gate: `docs/ADVANCED_DATABASE_CONFIG.md:33-46` sets the *deliberate* asymmetry (scopes fail closed, settings degrade), and blocking Save on unreadable tuning knobs contradicts it. | Record + evidence. |
| **S5** | The reset path passes `config.isBluetoothLeEnabled` etc. straight through (`DittoManager.swift:380-386`), bypassing the `isRunningUITests()` gate `hydrate` uses (`:217-220`) to keep BLE/LAN off under UI tests | Phase 4 passes `isUITesting: isRunningUITests()` into `transportFlags`. **Threat trace required before the change** (rule 3): the gate exists to suppress OS permission prompts that block the harness — confirm no non-test path depends on reset re-enabling transports. | Phase 4 passes `isUITesting: false` from the reset path, preserving today's behavior byte-for-byte, and records why. |
| **S6** | `selectedDatabaseStartSync` returns silently when `dittoSelectedAppConfig` is nil (`:414`), after which `toggleSync` sets `isSyncEnabled = true` | **Largely dissolved by C3** — after C3, `isSyncEnabled` derives from `SyncRuntimeState`, so a no-op start cannot flip the indicator. If adjudication still confirms the silent return itself is a defect, Phase 6 makes it throw. Note the interaction explicitly so the adjudicators are not judging pre-C3 code. | Record + evidence; the C3 change stands regardless. |
| **S7** | `.completeFileProtection` may be the wrong class for the documented "accessible after first unlock" intent (`SQLCipherService.swift:277-297`) | **Threat trace first, and it is mandatory** (rule 3 — this exact control already produced a credential-destruction path on this repo). The trace must enumerate every reader of `sqlcipher.key`: `getOrCreateEncryptionKey:237-251` (hard-fails on unreadable, no longer regenerates), plus any background/locked-relaunch path. Only with that written down may Phase 6 change the class to `.completeFileProtectionUntilFirstUserAuthentication`. | Record + evidence. **Default to no change.** |
| **S8** | `QRCodeGenerator.testPayloadString(config:favorites:)` / `(rawJSON:)` ship in Release (`:125`, `:131`) while comparable seams are `#if DEBUG` (e.g. `SQLCipherService.executeRawForTesting:978-986`, `DatabaseRepository.clearCacheForTesting:83-90`) | Phase 6: wrap both in `#if DEBUG`. **Must be verified by the Release build**, since that is the configuration where the tests referencing them are not compiled — `QRCodeAdvancedExclusionTests.swift:36, 53, 147`. | Record + evidence. |
| **S9** | `initialize()` leaks a `sqlite3` connection per Retry press when `verifyEncryption` throws (`:86-103`; `_isInitialized` stays false at `:116`, and the Retry button at `ContentView.swift:511-515` re-enters) | Phase 6: `sqlite3_close(db); db = nil` on every throwing path after `sqlite3_open` succeeds. **Author note:** independently read and consistent. Still adjudicated. | Record + evidence. |
| **S10** | `ViewModel.needsSensitiveAcknowledgement(id:)` has tests but no production caller (`DatabaseEditorView.swift:979`; the view uses `isSensitiveRow` at `:527`) | Phase 6b: delete it, **and** re-point its three now-orphaned assertions at `DatabaseEditorAdvancedViewModelTests.swift:129`, `:137`, `:255` — the unit-test target will not compile otherwise. Save is **already** blocked via `hasAdvancedValidationErrors:1055` → `startupSettingError:972` → `validateSetting`'s `.needsAcknowledgement` (`AdvancedDatabaseSettings.swift:440-442`), so this removes a duplicate, not a control. **Verify that chain before deleting**, and re-point those three assertions at `hasAdvancedValidationErrors` — the property the Save button actually reads (`DatabaseEditorView.swift:138`) — rather than dropping the coverage. This is exactly the shape of the historical "five tests certified a control the UI bypassed" failure, in the opposite direction. | Record + evidence. |

**A refutation is a successful outcome.** Refuted findings are written into §9 with
their evidence so the same hypothesis is not re-litigated next round.

---

## 5. Phases

Strictly sequential. Each phase's gate must be green, and its result written into §9,
before the next begins.

### Phase 0 — establish the baseline (no code changes)

The prompt supplies a baseline; this plan does not take it on trust, because
"claiming clean tooling without running it" is failure mode 5.

**Actions**

1. Run all three builds, both test commands, and both lint/format commands from §8.
   Record exact pass/fail counts and every diagnostic.
2. Enumerate the changed-file list once and save it (`git status --short | awk '{print $2}' | grep '\.swift$'`)
   so every later gate lints the same set, including untracked new files.
3. Run `swiftlint lint --config .swiftlint.yml` (repo config, production only) and
   **record whether any `error:`-severity violation exists today.** Phase 5 drops
   `|| true`; if there is a pre-existing error-severity violation, Phase 5 breaks the
   build. This is the number that decides whether Phase 5 needs a fix-up step.

4. **Count UI-test skips, not just exit status.** Run the UI-test command with
   `-resultBundlePath` and extract the skip count. This is not optional bookkeeping:

> **Measured while writing this plan:** `testDatabaseConfig.plist` **does not exist** in
> this checkout — `find . -name "testDatabaseConfig*"` returns only
> `SwiftUI/EdgeStudio/testDatabaseConfig.plist.example`. `UITestBase.swift:259` therefore
> throws `XCTSkip("No seeded databases — testDatabaseConfig.plist absent or empty
> (credential-less path).")`, and `:339`/`:360-365` (`ensureMainStudioViewIsOpen`,
> `openStudio`) skip through the same helper. A skipped suite **exits 0**. Six UI-test
> classes route through those helpers and therefore skip entirely:
> `AppLaunchUITests`, `DatabaseManagementUITests`, `NavigationLifecycleUITests`,
> `NavigationSmokeUITests`, `QueryExecutionUITests`, `QueryResultsUITests`.
>
> **`AdvancedConfigurationUITests` — the class §8's UI command names — does NOT skip.**
> It never touches those helpers; it taps `AddDatabaseButton`, drives the editor sheet
> credential-free, and cancels (`AdvancedConfigurationUITests.swift:24-115`). Verified.
> So the prompt's "the UI test passes" is accurate for that class (**N6**, partly
> refuted). Two things follow, both real: (a) that class is the working precedent
> Phase 3c's route is modeled on; (b) the skip risk is live for anything that needs a
> seeded database, which is exactly what Phase 3c and Phase 6a must not quietly rely on.
>
> **Binding rule for every subsequent gate: a skipped UI test is a FAILED gate.** Each
> gate that names a UI test records `passed / failed / skipped`, and a non-zero skip on
> an assertion this plan relies on must be resolved (Phase 3's credential-free route) or
> moved to §10 as unverified (Phase 6a). It may never be recorded as a pass. This is
> `plans/2026-08-19-advanced-database-config.md:588`'s own warning ("A skipped suite
> reports green") turned into a gate rather than a hope.

**Gate:** the baseline in §9.1 is filled in with real output. If the **test or build**
numbers disagree with the prompt's baseline (478 unit + 160 integration, three clean
builds), **stop and report the disagreement** rather than proceeding on a wrong
baseline. The UI-test line is **expected** to disagree, per the note above; record the
skip count rather than stopping.

The **lint** numbers are already known to disagree with the prompt, and the corrected
values are recorded here rather than discovered as a stop:

> **Measured while writing this plan** (swiftlint 0.65.0, `swiftlint lint --strict` on
> the 51 changed `.swift` files): **15** error-severity violations, not 6 —
> 12 × `sorted_imports`, 2 × `sync_scopes_via_applier`
> (`EdgeStudioUnitTests/Services/AdvancedSettingsApplierTests.swift:277`, `:548`),
> 1 × `force_unwrapping`
> (`EdgeStudioIntegrationTests/TestHelpers.swift:138`). The repo config on its own
> (`swiftlint lint --config .swiftlint.yml`, production only) is clean — 0 violations.
>
> The prompt's "6 pre-existing `sorted_imports` errors in test files" is right about a
> **subset**: 6 of the 12 are in pre-existing test files this change set merely
> modified (`DatabaseConfigFixtures`, `SQLCipherServiceTests`,
> `SyncStatusViewModelMoreTests`, `TestHelpers`, `ModelTests`,
> `DatabaseRepositoryTests`). **8 violations are introduced by this change set** — 6
> `sorted_imports` in files it creates (`AdvancedDatabaseSettingsTests`,
> `AdvancedSettingsApplierTests`, `QRCodeAdvancedExclusionTests`,
> `DatabaseEditorAdvancedViewModelTests`, `SchemaMigrationV5Tests`,
> `DatabaseRepositoryAdvancedTests`) and the two `sync_scopes_via_applier` hits in a
> test file it creates. The remaining one — the `force_unwrapping` at
> `TestHelpers.swift:138` — is **pre-existing**: `git show
> HEAD:SwiftUI/EdgeStudioIntegrationTests/TestHelpers.swift` has `letters.randomElement()!`
> at line 137, and only whitespace reflow moved it. Verified. So the split is
> **8 introduced / 7 pre-existing**, not 9/6.
>
> Two earlier drafts of this plan got this wrong in opposite directions — first calling
> all fifteen pre-existing, then calling the force-unwrap new. Both were failure mode 5
> applied to this plan's own claims, which is exactly why the numbers are pinned to
> commands here rather than prose.

**Unverified after this phase:** nothing — this phase produces facts only.

---

### Phase 0b — clear this change set's own lint debt

Small, mechanical, and required: the plan cannot claim clean tooling on files it
introduces while eight error-severity violations sit in them (failure mode 5). Done
before any behavioral change so the later gates have a genuinely clean floor.

**Actions**

1. **12 `sorted_imports` — resolve the tool conflict in config; do not edit the files.**
   `sorted_imports` and SwiftFormat's import settings are **mutually unsatisfiable** for
   any file containing `@testable`. Verified by execution on a copy of
   `AdvancedDatabaseSettingsTests.swift`:

   | Step | Result |
   |---|---|
   | original | `import Foundation` / `import Testing` / `@testable import …` |
   | `swiftlint lint --fix --config .swiftlint.yml` | `@testable import …` **first** |
   | `swiftformat --dryrun --config .swiftformat` | `1/1 files would have been formatted` |
   | `swiftformat --config .swiftformat` | reverts to `@testable` **last** |
   | `swiftlint lint --strict` | `sorted_imports` error again |

   `.swiftlint.yml:41` opts in `sorted_imports` (which sorts `@testable` first);
   `.swiftformat:38` sets `--importgrouping testable-bottom` and `:53` enables
   `sortImports` (which puts it last). An earlier draft of this plan said "reorder the
   import block", which would have made §8's mandatory `swiftformat --dryrun` gate
   permanently dirty (`6/51 files would have been formatted`, today's value is `0/51` —
   measured) and would be silently reverted by `CLAUDE.md`'s own documented pre-commit
   sequence (`swiftlint lint --fix; swiftformat .; swiftlint lint`). That is failure
   mode 5 reappearing inside this plan's remedy for failure mode 5.

   **Decision: delete `sorted_imports` from `.swiftlint.yml`'s `opt_in_rules` (`:41`).**
   Import ordering stays enforced — by SwiftFormat's `sortImports`, whose `--dryrun` is
   already a mandatory gate in §8 — and `.swiftlint.yml:19-20` already concedes
   formatting to SwiftFormat for exactly this reason ("Let SwiftFormat handle
   formatting"). No coverage is lost; a contradiction is removed. This also retires all
   12 violations, including the 6 in pre-existing files, because the correct resolution
   of a config contradiction is not per-file.

   **Verify no production regression:** production files carry no `@testable`, and
   `swiftlint lint --config .swiftlint.yml` is already `0 violations in 145 files`
   (measured), so this cannot unmask anything there. Confirm after the change.
2. **2 `sync_scopes_via_applier`** — `AdvancedSettingsApplierTests.swift:277`, `:548`
   hardcode the literal `"ALTER SYSTEM SET USER_COLLECTION_SYNC_SCOPES"` as a
   `failingPrefixes` entry. Replace both with `AdvancedSettingsDQL.setSyncScopesQuery`
   (`AdvancedDatabaseSettings.swift:490`), which is the same text plus the ` = :scopes`
   suffix and is still a valid prefix. This silences the rule **at source rather than
   with a disable comment**, and it removes a duplicated statement literal — which
   `plans/2026-08-19-advanced-database-config.md:598-600` already warns against
   ("don't write tautological statement-text assertions").
> ### ✅ EXECUTED 2026-08-21 — gate green
>
> Ran ahead of the rest of the plan, at the user's request, to validate the starting
> state. Results in §9.1. Steps 1 and 2 applied as written; **step 3 was deliberately
> overridden** — see the note under it. Three files changed: `.swiftlint.yml`,
> `SwiftUI/EdgeStudioUnitTests/Services/AdvancedSettingsApplierTests.swift`,
> `SwiftUI/EdgeStudioIntegrationTests/TestHelpers.swift`. No production code touched.
>
> Verified beyond lint, because lint-clean is not proof for a change to a test fixture:
> 478 unit + 160 integration tests pass (baseline counts, unchanged), all three builds
> succeed, and **both tests whose fixture changed still pass** — confirming the
> `AdvancedSettingsDQL.setSyncScopesQuery` substitution is prefix-compatible and they
> still fail for the same reason they did before. A negative control confirms
> SwiftFormat still rejects unsorted imports (`1/1 files would have been formatted` on a
> deliberately mis-ordered probe), so retiring `sorted_imports` dropped no coverage.

3. **Do not touch** the `force_unwrapping` at `TestHelpers.swift:138`
   (`letters.randomElement()!`). It is **pre-existing** —
   `git show HEAD:SwiftUI/EdgeStudioIntegrationTests/TestHelpers.swift` has it at line
   137, only whitespace reflow moved it. Out of scope, recorded in §9.4.

   > **OVERRIDDEN on execution (2026-08-21), on the user's instruction to fix the
   > linting issues.** Fixed by replacing `map { … ! }` with `compactMap { … }`.
   > Behaviour is identical: `letters` is a non-empty literal, so `randomElement()`
   > never returns nil and the result is always `length` characters. The upside is
   > structural — the gate is now **0 violations** with no standing exception, so every
   > later phase compares against zero instead of remembering which single error was
   > allowed. §8's acceptance table and §9.4 are updated accordingly. This is the only
   > deviation from the plan as approved.

**Gate:**
- `swiftlint lint --strict` on the changed-file list → exactly **1** error-severity
  violation: the pre-existing `force_unwrapping` in `TestHelpers.swift`. **Confirm the
  summary line reads `in 51 files`, not `in 145 files`** (see §8).
- `swiftlint lint --config .swiftlint.yml` → still `0 violations in 145 files`.
- `swiftformat --dryrun` on the changed-file list → still `0/51 files would have been
  formatted`. This is the gate the earlier draft would have broken; it is now an
  explicit acceptance value, not an assumption.
- Full unit+integration suites still pass (step 2 changes a test's fixture string; that
  test must still fail for the same reason it did before). All three builds clean.

**Unverified after this phase:** nothing behavioral changes.

---

### Phase 1 — adjudication round (no code changes)

**Actions**

1. Spawn **two independent reviewers** (neither sees the other's output, nor any
   rebuttal) with the ten findings **S1-S10** from §4, the codebase, and an explicit
   instruction to **confirm or refute** each with `file:line` evidence and a concrete
   failure scenario. They are told each finding is disputed and single-source.
2. Where the author's own read is recorded in §4 (S3, S9), that counts as **one**
   confirmation, so one adjudicator agreeing reaches two. State that in the ledger
   rather than double-counting silently.
3. Write the verdict table into §9: finding, confirmation count, evidence, disposition.
4. For **S5** and **S7**, additionally write the **threat trace** required by rule 3
   before any later phase may act on them.

**Gate:** §9 contains a disposition for all ten findings. Every finding is either
"confirmed (2+) → Phase N" or "refuted/unconfirmed → not fixed, evidence recorded".
**No code is written in this phase.**

**Unverified after this phase:** confirmations are review judgements, not executed
proofs, except where a finding was reproduced by command.

---

### Phase 2 — C6: return the affected row count

Ordered first because C1's regression test asserts on the row count, and doing C6
afterwards would mean re-verifying C1.

**Files / functions**

- `SwiftUI/EdgeStudio/Data/SQLCipherService.swift`
  - `executeWithParameters(_:_:)` (`:1005`) → `@discardableResult ... -> Int`; capture
    `Int(sqlite3_changes(db))` immediately after the `sqlite3_step` guard at `:1017-1020`.
    `@discardableResult` is required **here too**, not only on the wrapper:
    `executeRawForTesting` (`:983-985`) calls `executeWithParameters` directly and would
    otherwise emit an unused-result warning that shows up in the "clean build" evidence.
  - `execute(_:_:)` (`:1000`) → `@discardableResult ... -> Int`, forwarding.
  - `updateDatabaseConfig` (`:648`) → `let changed = try await execute(sql, …)`;
    `guard changed == 1 else { throw … }` replacing `:685`.
  - **Delete** `changedRowCount()` (`:993-995`).

**Smallest correct change:** signature widening plus one deletion. No call site other
than `updateDatabaseConfig` reads the value; `@discardableResult` keeps the ~40 other
`execute` calls untouched.

**Wiring (rule 1):** production call site is `updateDatabaseConfig:685`, reached from
`DatabaseRepository.updateDittoAppConfig:186`. Proof:
`grep -rn --include="*.swift" "changedRowCount" .` → **no hits**;
`grep -n "let changed = try await execute" SwiftUI/EdgeStudio/Data/SQLCipherService.swift` → one hit.

**Verification:** `EdgeStudioIntegrationTests` — existing coverage that updating a
non-existent `_id` throws must still pass; add one test that a successful update of an
existing config does **not** throw (i.e. the count is genuinely 1, not accidentally so).

**Left unverified:** that no *other* `execute` caller ever comes to depend on the
returned count. `@discardableResult` makes that a silent future hazard; noted, not
guarded.

---

### Phase 3 — C1: the foreign-key regression

**Sub-order is mandatory: UI first, then SQL, then tests.**

**3a — UI (do this first)**

- `SwiftUI/EdgeStudio/Views/Database/DatabaseEditorView.swift`
  - Database ID `TextField` (`:71-79`): add `.disabled(!viewModel.isNewItem)` and a
    caption explaining that a registered database's ID cannot be changed (delete and
    re-register). `isNewItem` (`:884-888`) is immutable for the sheet's lifetime and
    is exactly `databaseId == ""`, which is exactly the insert-vs-update split at
    `:1155-1158` — so the disable condition and the SQL change cover the same set.
  - `save()` (`:1130-1154`): for `!isNewItem`, pass `original.databaseId` verbatim as
    `databaseId` instead of the trimmed field value, so the in-memory cache
    (`DatabaseRepository.cachedConfigs`) and `refreshSelectedConfigIfMatching:1163`
    cannot diverge from disk for a legacy untrimmed id. `original` is the
    `OriginalSnapshot` at `:842`.
- `SwiftUI/EdgeStudio/Views/ContentView.swift` and
  `SwiftUI/EdgeStudio/Views/Database/DatabaseListPanel.swift`: add
  `.accessibilityIdentifier("EditDatabaseMenuItem")` to the context-menu **Edit** Button
  (`ContentView.swift:434`, `DatabaseListPanel.swift:63`) and
  `.accessibilityIdentifier("DeleteDatabaseMenuItem")` to the **Delete** Button
  (`ContentView.swift:437`, `DatabaseListPanel.swift:69`). Nothing else about those menus
  changes. Both exist solely so 3c's UI test can reach the editor for an existing config
  **and clean up after itself** — verified, neither affordance is addressable today
  (**N5**), and a leftover config breaks six other UI-test classes (see 3c).

**3b — SQL**

- `SwiftUI/EdgeStudio/Data/SQLCipherService.swift` `updateDatabaseConfig` (`:648-691`):
  remove `databaseId = ?` from the `SET` list (`:656`) and remove `config.databaseId`
  from the bound arguments (`:678`). `WHERE _id = ?` stays. The comment at `:681-684`
  is rewritten to record **both** hazards: the original `WHERE databaseId = ?` bug it
  already describes, **and** why the column is now not written at all (the FK
  reproduction, plus `localDirectoryPath`).

**3c — Tests**

**First, the two existing tests that assert the behavior 3b removes.** Both are in
`SwiftUI/EdgeStudioIntegrationTests/Repositories/DatabaseRepositoryAdvancedTests.swift`
(an untracked file this change set creates), and both go **red** the moment 3b lands.
Verified by reading them. Without an explicit disposition here, Phase 3's gate ("full
unit+integration suites") can never go green and the executor is left improvising
deletions of named regression tests mid-phase — the exact pattern
`docs/FIX_VERIFICATION_RULE.md:13-15` records as how this repo got worse three times.

1. `` `Editing the Database ID persists` `` (`:164-190`) — sets
   `config.databaseId = "db-renamed"`, updates, and asserts
   `#expect(loaded[0].databaseId == "db-renamed")` (`:186`). After 3b the column is not
   written, so this fails.
   **Disposition: rewrite, do not delete.** Rename to
   `` `Editing a config never changes its Database ID` ``, replace the doc comment
   (`:164-166`, which describes the old `WHERE databaseId = ?` bug) with the C1
   rationale, and invert the assertion: submitting a changed `databaseId` for an
   existing config leaves `databaseId` at its stored value while `name` and the sync
   scopes **do** change. This asserts the new shipping contract — the same contract the
   UI now enforces by disabling the field — instead of the removed one. It keeps the
   surviving half of the original test's value (`name` and `collectionSyncScopes` still
   persist through an update).
2. `` `Editing one config never overwrites another` `` (`:192-220`) — sets
   `first.databaseId = second.databaseId` and asserts
   `await #expect(throws: (any Error).self) { try await repo.updateDittoAppConfig(first) }`
   (`:210-212`), relying on the `UNIQUE` index firing **because** `databaseId` is in the
   `SET` list. After 3b no constraint is violated, `changed == 1`, nothing throws — so
   this fails too.
   **Disposition: rewrite, do not delete.** The invariant the test protects (one
   config's save must never rewrite another's row) is now guaranteed *structurally* by
   `WHERE _id = ?` plus the column not being written, which is strictly stronger than a
   `UNIQUE` rejection. So: drop the `#expect(throws:)`, keep and strengthen the
   surviving assertions (`:214-219`) — after `first` is saved with `second`'s
   `databaseId` submitted, **both** rows are intact: `second`'s name, token and
   `databaseId` unchanged, and `first`'s `databaseId` also unchanged. Update the doc
   comment (`:192-195`) to state that cross-row overwrite is now structurally
   impossible rather than constraint-rejected.
   Also add one assertion that `addDittoAppConfig` still rejects a duplicate
   `databaseId` — that is where the `UNIQUE` index is still load-bearing, and dropping
   the `UPDATE`-path throw must not quietly retire coverage of it.

Both rewrites are recorded in §9.3 with before/after names, so the change is auditable
rather than a silent deletion.

**Then, the new coverage:**

- `SwiftUI/EdgeStudioIntegrationTests/Services/SQLCipherServiceTests.swift` — new test.
  **Production path covered:** a user editing the name/token of a database they have
  already run queries against, i.e. `DatabaseEditorView.save` → `updateDittoAppConfig`
  → `updateDatabaseConfig`.
  **Fixture requirement (rule 2):** the config **must** have at least one `history`
  child row before the update. The previous Database-ID test passed *because its
  fixture had no child rows* — a childless fixture makes this test vacuous.
  Asserts: the update does not throw; `name` and `token` changed; `databaseId`
  unchanged; the `history` child row still present and still joined to the parent.
- **UI test — on a credential-free route, and it must clean up after itself or it breaks
  six other test classes.** The route that goes through `UITestBase.openStudio()` /
  `addDatabasesFromPlist()` skips in this checkout (**N6**), so the test is modeled on
  `AdvancedConfigurationUITests`, which already drives this sheet credential-free and
  passes. It works because **registering a database never opens Ditto** —
  `DatabaseEditorView.save` → `addDittoAppConfig` is a pure store write
  (`DatabaseRepository.swift:144-181`).

  1. Launch with `UI-TESTING`. Tap `AddDatabaseButton`.
  2. Fill `NameTextField`, `DatabaseIdTextField`, `TokenTextField` — the three
     identifiers `UITestBase.addSingleDatabase` already relies on. Use a **per-run
     unique** `databaseId` (e.g. `uitest-\(UUID().uuidString)`): `databaseId` is
     `NOT NULL UNIQUE` (`SQLCipherService.swift:336`), so a fixed value left behind by a
     crashed run makes every later run fail on insert.
     Assert `DatabaseIdTextField.isEnabled == true` **here** (the register case). Save.
  3. Reopen that config for editing; assert `DatabaseIdTextField.isEnabled == false`.
  4. **Delete it, in `tearDown` so it runs on failure too.**

  **Two identifiers must be added for steps 3-4, because neither affordance is
  addressable today.** `DatabaseCard` declares `onEdit` (`DatabaseCard.swift:5`) but its
  body never uses it; the real controls are unidentified `contextMenu` Buttons.
  Verified. Phase 3a adds `EditDatabaseMenuItem` and `DeleteDatabaseMenuItem` to
  `ContentView.swift:434`/`:437` and `DatabaseListPanel.swift:63`/`:69`. Nothing else in
  those menus changes. **N5** (the dead `onEdit`, `DatabaseList.swift:13`'s
  `onEdit: {}`, and the iOS swipe action at `DatabaseList.swift:30-34`) is recorded and
  **not** fixed.

  **Why cleanup is a blocker, not hygiene.** The UI-test store persists across launches
  (`ditto_edge_studio_test/ditto_encrypted.db`, `SQLCipherService.swift:18`,
  `:185-187`). A leftover dummy config means `addDatabasesFromPlist()`
  (`UITestBase.swift:255-260`) **finds a card and stops skipping**, so
  `ensureMainStudioViewIsOpen()` (`:341-347`) taps it, `createDatabaseConfig` rejects the
  dummy `url` (`DittoManager.swift:75-85`), `CloseButton` never appears, and
  `UITestBase.swift:349-353` calls `XCTFail`. That flips
  `AppLaunchUITests`, `DatabaseManagementUITests`, `NavigationLifecycleUITests`,
  `NavigationSmokeUITests`, `QueryExecutionUITests` and `QueryResultsUITests` from
  clean skips to red — a regression *caused by the test written to prove C1*.

  **Therefore Phase 3's gate additionally requires:** (a) the test asserts no
  `AppCard_*` element remains at its end; (b) the **other six UI-test classes are run**
  and confirmed still-skipping (not failing) after it. That second check is the decisive
  one and it is cheap. Residual risk — a hard crash mid-test leaves a row — plus its
  one-line recovery (`rm -rf "~/Library/Application Support/ditto_edge_studio_test"`) is
  recorded in §10.

  **This is the user's path**; the view-model assertion alone is the failure mode this
  rule exists to stop. If driving the macOS context menu proves unreliable under
  XCUITest, the outcome is recorded in §10 as unverified — **not** left as a silent skip.

**Wiring (rule 1):** no new function; the changed behavior is at existing call sites.
Proof required in the gate — **note the anchored form**: a bare
`grep "databaseId = ?"` returns **11** hits in this file, nine of which are legitimate
`WHERE databaseId = ?` clauses (`:699`, `:757`, `:783`, `:802`, `:823`, `:842`, `:863`,
`:904`, `:929`) plus the comment at `:681`. Verified. Using the bare form would make the
gate unsatisfiable, and the only way to "pass" it would be to break
`deleteDatabaseConfig`'s cascade at `:699`.

- `grep -nE '^\s+databaseId = \?,?$' SwiftUI/EdgeStudio/Data/SQLCipherService.swift` → **no hits** (the SET-list line is gone).
- A read of `updateDatabaseConfig` confirming `databaseId` is absent from **both** the
  SET list and the bound arguments, and `WHERE _id = ?` remains.
- `grep -rn --include="*.swift" "updateDittoAppConfig" SwiftUI/EdgeStudio` → **6** hits:
  the four call sites listed in §3.C1, plus the protocol requirement
  (`Protocols.swift:42`) and the definition (`DatabaseRepository.swift:186`). Read each
  of the four and confirm none of them changes `databaseId`.

**Verification:** the two rewritten tests in
`DatabaseRepositoryAdvancedTests.swift`; the new integration test; the new UI test;
full unit+integration suites; all three builds. The gate explicitly names
`DatabaseRepositoryAdvancedTests.swift` so a red result there cannot be read as
unrelated flakiness.

**Left unverified:** an existing install whose stored `databaseId` has surrounding
whitespace keeps it (no longer silently trimmed on save). Accepted and recorded — it is
the pre-existing on-disk value, and trimming it would move the Ditto store directory.

---

### Phase 4 — C5: identity post-condition and the reset transport closure

**Files / functions** — all in `SwiftUI/EdgeStudio/Data/DittoManager.swift`

1. New `nonisolated static func transportFlags(for config: DittoConfigForDatabase, isUITesting: Bool) -> (bluetoothLE: Bool, lan: Bool, awdl: Bool)` — the pure extraction of `:217-220`.
2. `hydrate` (`:217-220`) calls it with `isUITesting: isRunningUITests()`. **Behavior
   must be byte-identical**; this is a de-duplication, not a change.
3. `resetSystemSettingsToDefaults` (`:378-393`): the `applyTransportConfig` closure
   captures `ditto` and calls `ditto.updateTransportConfig { … }` directly (mirroring
   `hydrate:228-238`), using `Self.transportFlags(for: config, isUITesting: <per S5 verdict>)`.
   No `self.` call-back into the actor.
4. `resetSystemSettingsToDefaults`: add the post-condition after `sequence.run`
   (`:394-397`) — `guard dittoSelectedApp === ditto else { stop only this instance; return }`,
   mirroring `:267-275` including its "never enter the shared teardown" reasoning.
5. `selectedDatabaseStartSync` (`:433-436`): same post-condition after `sequence.run`.
6. Make `createDatabaseConfig` (`:53`) `nonisolated static` **and drop `private`** so
   its URL validation is reachable from `EdgeStudioUnitTests`. It is declared
   `private func` today (verified at `DittoManager.swift:53`), and `@testable import`
   exposes `internal`, not `private` — `nonisolated static` alone would leave the
   planned unit tests unwritable. Body untouched — but the call site at
   `DittoManager.swift:155` must become `Self.createDatabaseConfig(...)`. Self-correcting
   (the build fails loudly), but the file list would otherwise omit it.

**New `sync.stop` sites this phase adds.** Both post-conditions (items 4 and 5) stop
the captured instance on the abort path, mirroring `hydrate:273`. That takes
`DittoManager` from **7** `ditto.sync.start()`/`ditto.sync.stop()` call sites to **9**.
Phase 6a converts all nine to the funnels; its enumeration must include these two, or a
funnel-bypassing stop ships with the wiring gate reported green.

**Wiring (rule 1):**
`grep -n "transportFlags" SwiftUI/EdgeStudio/Data/DittoManager.swift` → definition +
**two** production call sites (hydrate, reset).
`grep -n "self.applyTransportConfig" SwiftUI/EdgeStudio/Data/DittoManager.swift` → **no hits**.
`grep -c "dittoSelectedApp === ditto" SwiftUI/EdgeStudio/Data/DittoManager.swift` → **3**.
`grep -c "createDatabaseConfig" SwiftUI/EdgeStudio/Data/DittoManager.swift` → **2**
(the definition + the one production call site in `hydrate`, `:155`).

**Verification:**
- New unit tests (`EdgeStudioUnitTests`) for `transportFlags`: UI-testing true forces
  all three off regardless of config; false passes config through. This is the
  **feature** decision (suppressing OS permission prompts under UI tests), not the fix.
- New unit tests for `createDatabaseConfig`: bare-UUID `url` throws with the documented
  message; `https://…` succeeds; `.smallPeerOnly` with and without a secret key. This
  is the D2 coverage step, landing on `hydrate`'s real validation branch.
- Full suites; all three builds.

**Left unverified — stated plainly:** the post-conditions themselves are **not covered
by an automated test.** Reproducing them needs a live `Ditto` plus a controlled
close/replace race mid-`sequence.run`; D2 refuses to build an injection seam for it.
Covered instead by (a) the `grep -c` invariant above, (b) a manual smoke step —
open a database, close it from a second window mid-open, confirm no orphan instance and
no "No Ditto app is currently selected" error. **This is a known-unverified item, not a
verified one.**

---

### Phase 5 — C4: make the lint gate real

Depends on **Phase 6's C3 work? No — the reverse.** C3 is what reduces `DittoManager`
to a single `sync.start(`/`sync.stop(` pair. Running Phase 5 first would require an
inline disable on all three current start sites, then editing them again in Phase 6.
**Therefore: Phase 5 runs *after* Phase 6.** It is numbered here because it belongs
with C4 conceptually; the execution order is
**0, 0b, 1, 2, 3, 4, 6a, 6b, 5, 7, 8**. See §5.1.

*(Content moved to §5.1 for ordering clarity — see "Phase 5 (executes after Phase 6)".)*

---

### Phase 6 — C3 (sync-state truth) + the confirmed single-source findings

Split into two independently gated sub-phases so C3 is not entangled with unrelated
one-liners (failure mode 4).

**6a — C3**

- New `SwiftUI/EdgeStudio/Views/StudioView/ViewModels/SyncRuntimeState.swift`, created
  via the **Xcode MCP server** if it is available in the executing session, so it lands
  in the target (per `CLAUDE.md`). If Xcode MCP is unavailable, add it to the target and
  **prove membership by building** — a file that compiles is in the target.
- `SwiftUI/EdgeStudio/Data/DittoManager.swift`: add `startSyncNow(_:)` / `stopSyncNow(_:)`
  funnels; rewrite **all nine** `ditto.sync.start()` / `ditto.sync.stop()` call sites as
  they exist *after Phase 4* to use them. Seven exist today —
  `closeDittoSelectedDatabase:29-31`, `hydrate`'s `startSync:` closure `:251-253`,
  `hydrate`'s abort-path stop `:273`, `resetSystemSettingsToDefaults`'s stop `:369` and
  `startSync:` closure `:391`, `selectedDatabaseStartSync`'s `startSync:` closure
  `:428-430`, `selectedDatabaseStopSync:455-458` — plus the **two abort-path stops
  Phase 4 adds** with its post-conditions. Re-derive the list by grep at the start of
  this phase; do not trust these line numbers after Phase 4 has shifted them.
- `SwiftUI/EdgeStudio/Views/StudioView/ViewModels/SyncStatusViewModel.swift`: inject
  `syncRuntime: SyncRuntimeState = .shared`; `isSyncEnabled` becomes
  `{ syncRuntime.isRunning }`; remove the writes at `:130`, `:133`, `:113`.

**Wiring (rule 1).** A plain `grep "sync\.start(\|sync\.stop("` is **not** usable as the
gate: it matches comment prose and string literals, so the count can never reach the
funnel-only number (`DittoManager.swift:33` is a `Log.info` string; `:288`, `:309`,
`:417` are comments; `AdvancedSettingsApplier.swift:25`, `:261` are doc comments).
Verified. Use instead:

1. `grep -n "ditto\.sync\.start()\|ditto\.sync\.stop()" SwiftUI/EdgeStudio/Data/DittoManager.swift`
   → exactly **two** hits, both inside the funnels. (This form excludes the prose and
   the `Log.info` string, all of which lack the `ditto.` receiver, but it is a
   heuristic — hence check 2.)
2. **The authoritative check:** run SwiftLint with a temporary config that is
   `.swiftlint.yml` plus Phase 5's two corrections (`match_kinds: [identifier]` on
   `sync_start_choke_point`, and `DittoManager` dropped from its `excluded`) and confirm
   **exactly one** violation — the funnel's own `sync.start(`. Phase 5 then makes that
   same configuration permanent and fatal. This is a real syntax-aware check, not a
   text count.
   **The temp config must be written at the repo root** (e.g. `.swiftlint.probe.yml`,
   deleted afterwards): `included:` resolves relative to the config file's own
   directory, so a config placed elsewhere lints zero files and reports clean — another
   false-green of exactly the kind §8 warns about. Confirm the summary line shows a
   non-zero file count.
3. `grep -rn --include="*.swift" "SyncRuntimeState" SwiftUI/EdgeStudio` → the
   definition, **both** funnels, and `SyncStatusViewModel` — i.e. a producer and a
   consumer, not a definition in isolation.

**Verification (must cover the shipping path, rule 2):**
- Update every existing assertion on the old stored property — `SyncStatusViewModelTests`
  `:24`, `:47`, `:56`, **`:76`**, and `SyncStatusViewModelMoreTests` `:47`, `:69` — for
  the new source of truth. The mock `DittoManagerProtocol` start/stop must publish to
  the injected `SyncRuntimeState`, so the test drives the same property the toolbar
  reads (`MainStudioView.swift:415`, `DetailViews.swift:137/397/700`) — not a parallel
  field.
- New test: a `startSync` that **throws** leaves `isRunning == false` (the
  publish-after-success rule); a `stopSync` that throws still leaves it `false`.
- Make the state **mechanically readable from the UI**, so the fix is not provable only
  at the view-model layer — the exact gap that let five tests certify a bypassed
  control. `MainStudioView.swift:420` already carries
  `.accessibilityIdentifier("SyncButton")`, and so do three bottom-bar buttons
  (`DetailViews.swift:139`, `:399`, `:702`), which makes an XCUITest query ambiguous.
  So: change the **toolbar** button's identifier to `"SyncToggleButton"` (verified safe
  — `grep -rn SyncButton SwiftUI/EdgeStudioUITests/` returns nothing, no test depends on
  it) and add `.accessibilityValue(isSyncEnabled ? "on" : "off")` to **all four** sites,
  since all four render the same state and leaving three without it invites divergence.

  **But do not claim a UI test for it.** Reading that value requires an *open* database,
  which requires real credentials and a real `Ditto.open` — and
  `testDatabaseConfig.plist` does not exist in this checkout, so
  `UITestBase.openStudio()` throws `XCTSkip` (`UITestBase.swift:259`, `:339`). Unlike
  Phase 3's editor assertion, there is **no** credential-free route to a running sync
  session. So the `accessibilityValue` is added as the *seam* — the thing that makes the
  state readable the moment credentials are available — and the verification for this
  phase is the view-model tests plus the manual smoke step below. Recorded in §10 as
  known-unverified. Writing a UI test that skips would be worse than writing none.

**Left unverified:** that `DittoManager`'s real start/stop paths publish correctly under
a live instance (needs credentials). Guarded by the SwiftLint check above, the Phase 5
rule that makes it permanent, and a manual smoke step: open a database → indicator "on";
toggle off → "off"; Sync ▸ Settings ▸ apply a transport change with a failing sync scope
→ indicator "off", and **one** tap restarts.

**6b — the confirmed single-source findings**

Only findings the Phase-1 adjudication confirmed with **two** independent sources.
Executed in **small batches with a gate between them** (failure mode 4), grouped by
blast radius:

- Batch 1 (error presentation, no behavior change): S3.
- Batch 2 (editor behavior): S1, S2, S10.
- Batch 3 (storage lifecycle): S9, and S7 **only if** its threat trace was written and
  the finding confirmed.
- Batch 4 (build-configuration surface): S8 — gated on the **Release** build, since
  that is the configuration whose compilation the `#if DEBUG` changes.
- Batch 5 (repository decode reporting): S4, S6 — S6 only if it survives the C3
  interaction noted in §4.

Each batch: its own tests naming the production path, its own build+test+lint gate,
its own §9 entry. Refuted findings are recorded and **not touched**.

---

### 5.1 Phase 5 (executes after Phase 6) — C4: make the lint gate real

**The step order inside this phase is load-bearing.** The `.swiftlint.yml` corrections
must land, and the resulting violation list must be resolved, **before** `|| true` is
removed. Reversed, the build breaks on comment prose (§3.C4) and the only apparent way
out is reverting C4.

**Step 1 — fix the rules (config only, build phase still tolerant)**

- `.swiftlint.yml`, `sync_start_choke_point`:
  - add `match_kinds: [identifier]` (§3.C4 — verified this catches
    `try ditto.sync.start()` and suppresses both comment prose and string literals);
  - `:98` — `excluded: ".*/AdvancedSettingsApplier\\.swift"` (drop `DittoManager`);
  - `:89-99` — rewrite the comment and `message` to claim only what the regex can do.
- `.swiftlint.yml`, `sync_scopes_via_applier`:
  - add `excluded_match_kinds: [comment, doccomment]` — **not** `match_kinds:
    [identifier]`, which would make the rule a permanent no-op (§3.C4);
  - `:106` — `regex: "(?i)SET\\s+USER_COLLECTION_SYNC_SCOPES"`.
- `SwiftUI/EdgeStudio/Data/DittoManager.swift`: **one**
  `// swiftlint:disable:next sync_start_choke_point` above the `sync.start(` inside
  `startSyncNow`, with a one-line reason. **None** on `stopSyncNow` — the regex only
  matches `start`, so a disable there would trip the default-enabled
  `superfluous_disable_command` rule.

**Step 2 — enumerate and resolve, before making the gate fatal**

Run `swiftlint lint --config .swiftlint.yml` and **record the complete violation list**.
Expected: zero. If anything appears — including a comment or string match this plan did
not anticipate — resolve it here and log it in §9.3. Do not proceed to step 3 with a
non-empty list, and do not resolve it by re-adding an exclusion.

**Step 3 — make the gate fatal**

`SwiftUI/Edge Debug Helper.xcodeproj/project.pbxproj` (`:370`): remove `|| true`. Keep
`--quiet`; do **not** add `--strict` (§3.C4). Note the phase has
`alwaysOutOfDate = 1`, so it runs on every build.

**Verification — the point of this phase is that the gate *fails* when it should:**

1. `swiftlint lint --config .swiftlint.yml` → zero violations. (Baseline: already zero
   today, per §9.1 — so any violation here is introduced by this plan.)
2. **Negative test, run and recorded:** temporarily add `try someDitto.sync.start()` to
   a file outside the exclusion, build, and confirm the **build fails** with the
   custom-rule message. Revert. Paste the failing output into §9.3. Without this step
   the phase repeats the original defect — a gate asserted to work, never observed
   working.
3. **Positive-control test, also recorded:** temporarily add a `// comment mentioning
   sync.start()` line to the same file, build, and confirm the build **succeeds** —
   proving `match_kinds` is doing its job and the rule has not merely been silenced.
4. Same negative test for `sync_scopes_via_applier` with a lowercase
   `"alter system set user_collection_sync_scopes"` string, confirming both `(?i)` bites
   and that the rule still sees string literals (its whole purpose).
5. All three builds clean afterwards.

**Left unverified:** aliased forms (`let s = ditto.sync; try s.start()`) are **not**
caught, by design and now by documentation. There is no CI, so the gate only fires for
developers who build in Xcode with SwiftLint installed — recorded, and the reason CI is
deferred is in §3.C4.

---

### Phase 7 — C2 (delete the dead code) + C7/D1 (documentation truth)

**7a — C2**

- `SwiftUI/EdgeStudio/Data/DittoManager.swift`: delete `reapplyAdvancedSettings`
  (`:303-330`) and fix the comment at `:207-210` that names it.
- `docs/ADVANCED_DATABASE_CONFIG.md:160-162`: replace the claim that scopes are
  re-applied to guard against a query-editor `RESET ALL` with the honest statement —
  scopes are applied by `OpenSequence` on every path that **starts** sync; an
  `ALTER SYSTEM RESET ALL` typed into the query editor against a **running** instance
  clears them until the database is closed and reopened, and the SDK requires scopes to
  be set before `start_sync()` so re-applying to a live session is not a fix.
  Add the user remedy explicitly.

**Wiring (rule 1) — inverted for a deletion:**
`grep -rn --include="*.swift" "reapplyAdvancedSettings" .` → **no hits**, and all three
builds clean (a deletion with a live caller fails to compile — the strongest possible
wiring proof).

**7b — C7 / D1**

- **Every** false encryption claim in the affected files, not just the one phrase C7
  quotes. Enumerated by `grep -rniE "encrypt"` — **16 assertive claims across 6 files** in
  the table below, plus four more in `SQLCipherService.swift` (`:67` "the encrypted
  database connection", `:70-71` "Opens encrypted connection with SQLCipher PRAGMAs",
  `:331` "includes encrypted credentials", `:981` "the encrypted credential store") —
  **20 in total.** Verified. The table is the minimum edit list; the read-don't-count
  gate below is what actually bounds the phase, and it is the authority if this
  enumeration is still short:

  | File | Lines |
  |---|---|
  | `HistoryRepository.swift` | `:3` "secure encrypted storage", `:8` "Write-through persistence to encrypted database", `:11` "All history encrypted at rest with AES-256 (SQLCipher)" |
  | `FavoritesRepository.swift` | `:3`, `:8`, `:11` (same three shapes) |
  | `SubscriptionsRepository.swift` | `:4`, `:9`, `:13` |
  | `ObservableRepository.swift` | `:4`, `:9`, `:13` |
  | `DatabaseRepository.swift` | `:7` "All data (credentials + metadata) → SQLCipher encrypted database", `:16` "All data encrypted at rest with AES-256 (SQLCipher)", `:17` "Encryption key stored in local file with 0600 permissions" (a key that encrypts nothing) |
  | `SQLCipherService.swift` | `:570` "// Credentials (stored encrypted in SQLCipher database)" |

  Each is replaced with a factual line plus a pointer to
  `docs/CREDENTIAL_STORAGE.md`. **An earlier draft listed only the six `AES-256` lines
  and gated on `grep "encrypted at rest\|AES-256"`** — which would have deleted one line
  and left "secure encrypted storage" and "Write-through persistence to encrypted
  database" two lines above it, then certified C7 closed with a command that could not
  see them. That is failure mode 5 applied to the one defect §2.D1 calls "fixable now,
  cheaply and verifiably". The corrected gate is below.
- Rename `SQLCipherServiceTests.swift:377`
  `` `Credentials stored encrypted at rest` `` → `` `Credentials round-trip through the local store` ``,
  and add a comment stating the test cannot and does not prove encryption.
- `docs/ADVANCED_DATABASE_CONFIG.md`: delete the duplicated
  `### Acknowledgement is persisted` heading (`:102`, keeping the fuller `:96` section)
  and repair the spliced sentence at `:210-211`.
- `docs/ADVANCED_DATABASE_CONFIG.md`, "Testing" section (`:236-254`): add that the live
  `ALTER SYSTEM` round-trip suite (**N1**) does not exist, so the SDK-encoder questions
  at `:251-254` are unverified by *any* automated test, not merely credential-gated.
- **From the S7 refutation (Phase 1):** fix the stale doc comment at
  `SQLCipherService.swift:212-217`, which still describes the Keychain implementation
  ("Stores in Keychain with kSecAttrAccessibleAfterFirstUnlock…") that `:222-224`
  superseded ("NO KEYCHAIN"). Both adjudicators identified this stale text as the actual
  defect behind S7 — it is what made `.completeFileProtection` look wrong. Correct the
  comment; **do not** change the protection class.
- `docs/CREDENTIAL_STORAGE.md`: add a **Decision (2026-08-21)** section recording D1 —
  option 3 chosen, the reasoning from §2.D1, what is deliberately deferred (type
  rename, file rename, options 1/2), and that the follow-up needs its own plan.

**Verification — case-insensitive, on the word, not the phrase:**

`grep -rniE "encrypt" --include="*.swift" SwiftUI/EdgeStudio/Data/Repositories/ SwiftUI/EdgeStudio/Data/SQLCipherService.swift`
→ **every surviving hit must be either a denial of encryption or a pointer to
`docs/CREDENTIAL_STORAGE.md`.** Read them; do not count them. (Hits will legitimately
remain: `SQLCipherService.swift:20-32`'s ⚠️ header, `getOrCreateEncryptionKey`,
`SQLCipherError.keychainSaveFailed`, `rotateEncryptionKey`. The gate is that none of
them *asserts* the store is encrypted.)

Then widen once, to catch anything outside those paths:
`grep -rniE "encrypted at rest|AES-?256" --include="*.swift" SwiftUI/` → **no hits**.

`grep -c "### Acknowledgement is persisted" docs/ADVANCED_DATABASE_CONFIG.md` → **1**.
Full suites (the renamed test must still run and pass); all three builds; the in-app
Help window renders `Resources/Help/UserGuide.md` without a broken section.

**Left unverified:** the store is plaintext and stays plaintext. Documented, not fixed.

---

### Phase 8 — D2: coverage measurement, gate renegotiation, and the final readiness pass

**8a — measure and close the gap on what is closable**

1. `xcodebuild test … -enableCodeCoverage YES` then
   `xcrun xccov view --report --files-for-target <target> <path>.xcresult` —
   **per file, not aggregate.**
2. Record actual coverage for: `Models/AdvancedDatabaseSettings.swift`,
   `Data/AdvancedSettingsApplier.swift`, `Data/DittoManager.swift`,
   `Views/Database/DatabaseEditorView.swift`,
   `Views/StudioView/ViewModels/SyncRuntimeState.swift`.
3. Add tests until the two new pure files are each **≥80%**. Target the uncovered
   branches by name from the report — not by writing tests that restate what passing
   tests already assert.

**8b — renegotiate in writing**

Amend `docs/TESTING.md` with the **SDK-boundary exemption** exactly as drafted in
§2.D2, listing `DittoManager.swift`'s three functions by name with their measured
coverage pasted in, and the manual procedures from Phases 4 and 6 as their substitute
coverage. Update `docs/TESTING.md:43` ("Overall Coverage: 15.96%") to the measured value.

**8c — readiness review (a separate pass, per `FIX_VERIFICATION_RULE.md` §5)**

Run **after** all fixes have settled, with its own reviewers, asking only *is this
shippable?* — not *is anything broken?* Inputs: the completed §9, the coverage report,
and the known-unverified register in §10.

**Gate:** the three builds, both test commands, and both lint/format commands from §8
are clean on the full changed-file list; §9 is complete; §10 lists every unverified
claim.

**Left unverified:** `hydrate`'s SDK statement sequence, the identity post-conditions,
and everything in §10.

---

## 6. Ordering safety

Reviewers are asked specifically whether a later step depends on an earlier one that
could fail half-way. The answers:

- **No schema migration is introduced by this plan.** C1 is resolved without a v6
  migration (§3.C1), so the "half-applied migration bricks the config store" class —
  the worst hazard in this codebase — is **not reintroduced at all**. Nothing in
  Phases 0-8 writes `PRAGMA user_version` or `ALTER TABLE`.
- **Phase 2 before Phase 3**, because C1's regression test asserts the row count that
  C6 changes. Reversed, C1 would need re-verifying.
- **Phase 3's internal sub-order (UI → SQL → tests) is not optional.** SQL first leaves
  a window where an edit is silently discarded — worse than today's loud failure.
- **Phase 6 before Phase 5.** C3 concentrates `sync.start`/`sync.stop` into two
  funnels; Phase 5's lint rule and inline disables depend on that shape. Reversed, the
  disables would be written three times and then rewritten.
- **Phase 4 before Phase 6.** Phase 6 rewrites the same start/stop sites in
  `resetSystemSettingsToDefaults` that Phase 4 restructures; doing 6 first means
  editing them twice.
- **Phase 1 before Phases 4 and 6b.** Both act on adjudicated findings (S5 for Phase 4;
  S1-S10 for 6b) and must not act on unconfirmed ones.
- **Phase 7 after Phase 6**, because C2's honest documentation depends on C3's funnels
  being the actual mechanism, and Phase 7's `grep`-must-be-empty gate is cleanest once
  no other phase touches `DittoManager`.
- **Phase 0b before everything behavioral.** It clears the eight error-severity lint
  violations this change set introduced (plus the six pre-existing `sorted_imports` that
  the config-conflict resolution necessarily retires with them). Left until Phase 5, they would be
  indistinguishable from violations Phase 5 caused, and every intervening gate would
  have to carry a wrong "known-acceptable" threshold.
- **Phase 5's internal order (fix rules → enumerate and resolve → remove `|| true`) is
  not optional.** Reversed, the build fails on comment prose and the apparent fix is to
  revert C4. This is the one place in the plan where a wrong sub-order is
  self-concealing, because the symptom (build red) points at the wrong cause.
- **Phase 8 last**, per `FIX_VERIFICATION_RULE.md` §5.

Every phase is independently revertable: no phase leaves persistent state (no schema,
no file-format, no on-disk layout change). The worst case for an abandoned phase is an
uncompilable working tree, recoverable with `git checkout --` on that phase's files.

**Execution order: 0 → 0b → 1 → 2 → 3 → 4 → 6a → 6b → 5 → 7 → 8.**

---

## 7. Explicitly out of scope

Recorded so a later reader does not mistake omission for oversight:

- Linking SQLCipher / moving credentials to the Keychain (D1 follow-up, own plan).
- Renaming `SQLCipherService` or `ditto_encrypted.db` (folded into the D1 follow-up).
- An injection seam around `Ditto.open` (D2, refused with reason).
- Standing up CI (`.github/workflows`) — separate project (§3.C4).
- Writing the live `AlterSystemTests` suite (**N1**) — needs credentials and a scheme
  `environmentVariables` change.
- A "change database identity" feature, and the pre-existing store-directory orphaning
  on rename (**N2**).
- Any change to the Android tree, or to unrelated modified files in the dirty worktree
  (`PresenceViewer/*`, `MCPServer/*`, `Metrics/*`, `LogEntry.swift`, …). Preserve them.
- Committing anything.

---

## 8. Verification commands

Run **all** of these at every phase gate. The changed-file list is the one captured in
Phase 0, refreshed for files the phase added.

```bash
# builds — all three must be clean (ignore only the appintentsmetadataprocessor warning)
xcodebuild -project "SwiftUI/Edge Debug Helper.xcodeproj" -scheme "Edge Studio" -configuration Debug   -destination "platform=macOS,arch=arm64" build
xcodebuild -project "SwiftUI/Edge Debug Helper.xcodeproj" -scheme "Edge Studio" -configuration Release -destination "platform=macOS,arch=arm64" build
xcodebuild -project "SwiftUI/Edge Debug Helper.xcodeproj" -scheme "Edge Studio" -configuration Debug   -destination "platform=iOS Simulator,name=iPad Pro 13-inch (M5)" build

# tests
xcodebuild test -project "SwiftUI/Edge Debug Helper.xcodeproj" -scheme "Edge Studio" -destination "platform=macOS,arch=arm64" -only-testing:EdgeStudioUnitTests -only-testing:EdgeStudioIntegrationTests
xcodebuild test -project "SwiftUI/Edge Debug Helper.xcodeproj" -scheme "Edge Studio" -destination "platform=macOS,arch=arm64" -only-testing:EdgeStudioUITests/AdvancedConfigurationUITests

# coverage (per file, not aggregate) — Phase 8
xcodebuild test -project "SwiftUI/Edge Debug Helper.xcodeproj" -scheme "Edge Studio" -destination "platform=macOS,arch=arm64" -enableCodeCoverage YES -resultBundlePath /tmp/edgestudio.xcresult
xcrun xccov view --report --only-targets /tmp/edgestudio.xcresult              # target list first
xcrun xccov view --report --files-for-target "Edge Studio.app" /tmp/edgestudio.xcresult   # then per-file

# lint/format — on the CHANGED files explicitly, tests included (failure mode 5)
swiftlint lint --strict $(git status --short | awk '{print $2}' | grep '\.swift$')
swiftformat --dryrun $(git status --short | awk '{print $2}' | grep '\.swift$')

# repo-config lint, production only — this is what the build phase runs (Phase 5)
swiftlint lint --config .swiftlint.yml
```

Note the two lint invocations are **different** and both are required: the first covers
the changed files including tests (which `included: SwiftUI/EdgeStudio` excludes); the
second is what the build phase actually enforces after Phase 5. Run the first from the
repo root with explicit paths — passing paths overrides `included:` for the file set but
still uses the repo config's rule set, which is what we want.

> **Trap, hit while writing this plan and independently reproduced by a reviewer.** If
> the passed paths do not resolve from the current directory, swiftlint **silently falls
> back** to the config's `included:` set and lints the 145 production files instead,
> reporting `Found 0 violations` — a false clean on the very gate meant to prevent
> failure mode 5. **Every gate must therefore assert the file count in swiftlint's
> summary line matches the changed-file list — today `in 51 files`, never
> `in 145 files`.** A clean result with the wrong file count is a failed gate, not a
> pass. The expected number **grows** as phases add files (Phase 6a adds
> `SyncRuntimeState.swift`; Phase 8 adds tests), so each gate asserts
> `in <len(changed-file list)> files`, re-derived at that gate — not a hard-coded 51.
>
> **Shell trap, reproduced twice:** in zsh, assigning the list to a variable and passing
> `$FILES` word-splits differently than inline `$(...)` and can silently produce the
> 145-file false clean. Pass the command substitution inline, and read the summary line.
>
> Related: `included:` is resolved relative to the **config file's** directory, so
> Phase 6a's temporary config must be written at the repo root or it lints nothing
> ("No lintable files found") and again reports clean.

**Known-acceptable at every gate — after Phase 0b:**

| Command | Accepted value |
|---|---|
| `swiftlint lint --strict <changed files>` | **0 violations.** Summary must read `in <len(list)> files` (51 at Phase 0b; grows as phases add files). |
| `swiftlint lint --config .swiftlint.yml` | **0 errors**, exit 0. Measured 2026-08-22: `142 violations, 0 serious in 216 files` — the 142 are warnings, every one in the test targets, none in this change set. This is the value the fatal build phase enforces. **Corrected here on 2026-08-22:** this row previously read `0 violations in 145 files`, which was unmeetable once Phase 5a pointed `included:` at all four targets, and which §9.1 repeated |
| `swiftformat --dryrun <changed files>` | `0/N files would have been formatted` |
| `swiftlint lint --strict` over all four targets | **Do not use as a gate.** `--strict` promotes those 142 test-code warnings to errors (exit 2). The strict gate is the *changed-file* row above, which is clean. The earlier `0 violations in 580 files` was wrong twice over: the count (there are 216 lintable files, not 580) and the severity |

**Achieved 2026-08-21 (Phase 0b executed — see §9.1).** There is now no standing lint
exception at all: any error of any rule, a wrong file count, or a non-zero swiftformat
count is a **regression** and fails the gate.

**Before Phase 0b the swiftlint number is 15** — see the measured breakdown in Phase 0.
Phase 0b clears 14 of them (8 introduced by this change set, plus the 6 pre-existing
`sorted_imports` that the config-conflict resolution necessarily retires with them). Do
not use the post-0b figures as the acceptance threshold at the Phase 0 gate.

---

## 9. Result ledger — filled in during execution

Per `FIX_VERIFICATION_RULE.md` "What to write down". **Empty until executed, except
cells marked as measured while planning** — those carry the command that produced them
and exist so the executor is not misled by the prompt's baseline. Everything else must
stay blank until the phase actually runs.

### 9.1 Baseline (Phase 0)

| Item | Prompt claims | Measured | Agrees? |
|---|---|---|---|
| Debug macOS build | clean | **BUILD SUCCEEDED** | ✅ |
| Release macOS build | clean | **BUILD SUCCEEDED** | ✅ |
| Debug iPad build | clean | **BUILD SUCCEEDED** (iPad Pro 13-inch M5) | ✅ |
| Unit tests | 478 pass | **478 tests in 89 suites passed** | ✅ |
| Integration tests | 160 pass | **160 tests in 52 suites passed** | ✅ |
| `AdvancedConfigurationUITests` | "passes" | **expected to pass** — it is credential-free (N6 refutation). Record passed/failed/**skipped** anyway | ✅ expected. The six `openStudio()`-based classes are the ones that skip; a skip on any assertion this plan relies on is a failed gate from here on |
| `swiftlint --config .swiftlint.yml` (production only) | clean | **0 violations (measured)** | ✅ |
| `swiftlint --strict` on the 51 changed files | "6 pre-existing `sorted_imports`" | **15 errors (measured), `in 51 files`:** 12 `sorted_imports`, 2 `sync_scopes_via_applier`, 1 `force_unwrapping` | ❌ — corrected in Phase 0; **7 pre-existing, 8 introduced by this change set** |
| **After Phase 0b (EXECUTED 2026-08-21)** | — | **0 violations in 51 files** (changed files, `--strict`); `swiftformat --dryrun` → `0/51`. **Corrected 2026-08-22:** this cell also claimed `0 violations in 145 files` and `0 violations in 580 files`; both were false — see the §8 table. The repo-config run is `0 errors / 142 warnings in 216 files` | ✅ |

### 9.2 Adjudication verdicts (Phase 1)

**EXECUTED 2026-08-21.** Two independent adjudicators, neither seeing the other's
output. **They agree exactly on all ten verdicts** — 8 confirmed, 2 refuted, 0 unproven.

| ID | Verdict | Confirmations | Evidence / reasoning | Disposition |
|---|---|---|---|---|
| **S1** | **CONFIRMED** — real, near-harmless | 2 | `setType` (`DatabaseEditorView.swift:1027-1039`) is the shipping path (`bindingForSettingType:633`) and is the one mutator that changes `value` without going through `setValue`. Both adjudicators noted the bound blast radius: the only value it can introduce is `"True"`, so it cannot widen a listener address or add a CA. Adjudicator B's concrete case: `sqlite3_synchronous` = `FULL`, acknowledged → switch Type to Boolean → applies `= true`, a durability setting never approved at that value, no re-prompt. | Fix in Phase 6b, batch 2 — revoke in `setType` when the seeded value changes and the row is sensitive |
| **S2** | **CONFIRMED** | 2 | Picker tags are exactly `["True","False"]` (`AdvancedDatabaseSettings.swift:225`), and a lowercase value is reachable **without any external ingress**: `setType`'s `isBooleanText` uses `caseInsensitiveCompare` (`:1034-1036`), so typing `false` as a String then switching to Boolean keeps `"false"`. `typedValue` lowercases (`:216-220`) so the row is *valid* — no error, Save enabled, blank picker. `DatabaseEditorAdvancedViewModelTests.swift:317-331` certifies the unrenderable state. | Fix in Phase 6b, batch 2 — canonicalize on load/type-change **and correct the test** |
| **S3** | **CONFIRMED** | 2 (+ empirical) | Adjudicator B replicated the enum standalone: `localizedDescription` → "The operation couldn't be completed. (…error 0.)" while `String(describing:)` gives the real text. `CustomStringConvertible` is not consulted by the NSError bridge. Both render sites use `localizedDescription` (`ContentView.swift:505`, `Ditto_Edge_StudioApp.swift:128`); logs too (`AppState.swift:23`). | Fix in Phase 6b, batch 1 — add `LocalizedError` |
| **S4** | **REFUTED** | 2 refutations | The lenient path is the **documented, intended** policy, stated independently in code (`DatabaseRepository.swift:60-61`) and docs (`ADVANCED_DATABASE_CONFIG.md:65-66`). Both adjudicators: the scope banner exists because an overwrite there destroys a *containment* control; startup settings guard nothing, and losing them cannot leak data. Degrades in the safe direction. | **Do not fix.** Recorded, not re-litigated |
| **S5** | **CONFIRMED** — latent, unreachable today | 2 (+ 2 threat traces) | Bypass is real (`DittoManager.swift:380-386` vs `hydrate:217-220`). Both traces independently reached the **same critical constraint**: the gate must go at the reset **call site**, never inside `applyTransportConfig` — that function is also called by `TransportConfigView.swift:268` and `MCPToolHandlers.swift:527`, so gating inside would silently no-op the user's own transport toggles under UI tests while `loadCurrentSettings` still displays the stored values. Unreachable today: no UI test taps `ResetToDefaultsButton`. | Phase 4 passes `isUITesting: isRunningUITests()` **at the call site only** |
| **S6** | **CONFIRMED** | 2 | `selectedDatabaseStartSync:414` is a silent success-shaped return in a `throws` function; `SyncStatusViewModel.swift:131-133` then sets `isSyncEnabled = true` unconditionally. Reachable via multi-window: `closeDatabaseIfSelected` nils the config (`:471-474`), and `hydrate`'s catch nils it (`:291`) after closing the prior instance. Both adjudicators independently confirmed **C3 dissolves the flag half**; the silent return remains a missing error message. | C3 (Phase 6a) closes the indicator lie; make the return throw in Phase 6b, batch 5 |
| **S7** | **REFUTED** | 2 refutations (both with complete traces) | The "accessible after first unlock" intent the finding rests on is a **stale Keychain-era doc comment** (`SQLCipherService.swift:212-217`), superseded at `:222-224` ("NO KEYCHAIN"); the live rationale at `:277-285` deliberately chooses `.completeFileProtection`. Sole reader is `getOrCreateEncryptionKey:240`, sole caller `initialize():83`, which short-circuits on `_isInitialized`. The destructive path is closed (`:243`, `:247` now throw instead of regenerating). Worst case is an inert, self-healing error + Retry. Changing it would **weaken** protection on the file guarding every credential. | **Do not fix.** Both adjudicators recommend fixing the stale comment instead → added to Phase 7b |
| **S8** | **CONFIRMED** — cosmetic | 2 | Both ship in Release (`QRCodeGenerator.swift:125`, `:131`), but neither exposes anything new: `testPayloadString(config:favorites:)` forwards to `encodePayload`, which already runs in Release behind `generate` and already applies `sanitizedForSharing()`. Adjudicator B notes the convention is **not** uniform — `SQLCipherService.resetForTesting():968-974` is likewise unguarded and strictly more powerful — so "comparable seams are all `#if DEBUG`" overstates the norm. | Fix in Phase 6b, batch 4 (low priority, `#if DEBUG`); harmless either way |
| **S9** | **CONFIRMED** | 2 | `sqlite3_open` assigns `db` at `:86`; six `executePragma` calls, `verifyEncryption`, `getSchemaVersion` and the migration can all throw before `_isInitialized = true` at `:116`, with no `catch`/`defer`/`close`. Retry (`ContentView.swift:509-518`) re-enters and overwrites the handle. Leaks an fd plus WAL/SHM references and a lock per press. Adjudicator A notes the correct teardown already exists at `:968-974` and simply isn't used. Both note `keyFileUnreadable` fires *before* the open, so it leaks nothing — the leak needs a **post-open** failure (e.g. a failed migration, which never clears, so repeated Retry is exactly what the UI invites). | Fix in Phase 6b, batch 3 |
| **S10** | **CONFIRMED** — safe to delete | 2 | Both traced the enforcement chain end to end and found it intact: Save `.disabled(… \|\| hasAdvancedValidationErrors)` (`:138`) → `:1055` → `startupSettingError:972` → `validateSetting` → `.needsAcknowledgement` (`AdvancedDatabaseSettings.swift:440-442`). The apply path re-checks independently via `partitionSettings` (`AdvancedSettingsApplier.swift:69`). Deleting removes a redundant predicate, not the control. | Fix in Phase 6b, batch 2 — delete, and **re-point** the three test assertions at `hasAdvancedValidationErrors` (where the shipping behavior lives) |

**SUMMARY: confirmed = S1, S2, S3, S5, S6, S8, S9, S10 · refuted = S4, S7 · unproven = none**

### 9.3 Fixes and their production call sites

| Phase | Defect | Production call site (grep output) | Verification | Gate result |
|---|---|---|---|---|
| **0b** | lint debt: 8 introduced + the `sorted_imports` config conflict | n/a (config + tests) | `swiftlint --strict` 15 → 0 errors; `swiftformat --dryrun` 0/51; negative control proves SwiftFormat still rejects unsorted imports | ✅ 2026-08-21 |
| **5a** | C4 — make the gate real | `project.pbxproj:370` (`\|\| true` removed); `.swiftlint.yml` `match_kinds`/`excluded_match_kinds`/`(?i)`; `included:` extended to the 3 test targets | **Negative test:** real `sync.start()` → `BUILD FAILED` exit 65. **Positive control:** comment prose → build succeeds. **Test-file negative test:** violation in `AdvancedSettingsApplierTests` → `BUILD FAILED` exit 65. `empty_count` → warning (9 pre-existing test sites, none mechanically convertible) | ✅ 2026-08-21. Phase 5b (drop `DittoManager` exclusion) still pending C3 |
| **2** | C6 — `changedRowCount` read after finalize | `SQLCipherService.updateDatabaseConfig:660` now consumes `execute`'s return value; `changedRowCount()` **deleted** (grep: only a historical doc-comment mention remains) | Both guard branches already covered by existing tests, all passing: `Updating a config that no longer exists throws` (≠1) and every successful-update test (==1) | ✅ 2026-08-21 — 478 + 160 pass |
| **4** | C5 — missing identity post-conditions + S5 transport gate | New `nonisolated static transportFlags(for:isUITesting:)` (`DittoManager.swift:505`) with **two** production call sites — `hydrate:216` and `resetSystemSettingsToDefaults:391`. `self.applyTransportConfig(...)` removed from the reset closure (grep: only a comment mention remains) — the reset now configures the **captured** `ditto` directly, as `hydrate` does. `dittoSelectedApp === ditto` post-condition count **3** (`:269` hydrate, `:421` reset, `:473` startSync). `createDatabaseConfig` → `nonisolated static`, non-private; grep count 2 (definition + `hydrate`) | 9 new unit tests: the transport truth table (UI-testing forces all three off; production passes each flag through independently) and `createDatabaseConfig`'s URL validation (bare UUID / empty / `ftp://` / hostless rejected with a message naming the database and quoting the value; http/https/ws/wss accepted; small-peer-only ignores `url` entirely). Verified `applyTransportConfig` still has its two production callers (`MCPToolHandlers.swift:527`, `TransportConfigView.swift:268`) — so it is not dead, and the adjudicators' warning against gating inside it was correct | ✅ 2026-08-21 — **487** unit (+9) + 161 integration pass; 3 builds clean; sync start/stop sites now **9**, exactly as Phase 6a predicts |
| **3** | C1 — foreign-key regression (BLOCKER) | **3a** `DatabaseEditorView.swift:86` `.disabled(!viewModel.isNewItem)` + `DatabaseIdLockedCaption`; `save()` persists `original.databaseId` for existing configs; `EditDatabaseMenuItem`/`DeleteDatabaseMenuItem` added at `ContentView.swift:439/:445` and `DatabaseListPanel.swift:68/:76`. **3b** `databaseId` removed from the `SET` list — anchored grep `^\s+databaseId = \?,?$` returns **no hits**; `WHERE _id = ?` retained | **3c** two doomed tests rewritten (`A submitted Database ID change is ignored while the rest of the save lands` — now with a `history` **child row**, the fixture the old test lacked — and `Editing one config never overwrites another`, retargeted off the UNIQUE-index throw); new `Registering a duplicate Database ID is rejected` keeps INSERT-path coverage; new **UI test** `DatabaseIdImmutabilityUITests` on the credential-free route. **Mutation-tested:** removing `.disabled()` makes the UI test fail on the exact assertion (exit 65), so it is not vacuous | ✅ 2026-08-21 — 478 + **161** pass; full UI suite 0 failures, 10 credential-gated tests still skip cleanly; no leftover sandbox state |
| **6a** | C3 — one source of truth for "is sync running" | New `SyncRuntimeState` (`Views/StudioView/ViewModels/SyncRuntimeState.swift`), written **only** by `DittoManager.startSyncNow:490` / `stopSyncNow:504`. **All nine** start/stop sites route through the funnels (`:29`, `:249`, `:268`, `:364`, `:401`, `:417`, `:450`, `:462`, `:555`) — the count Phase 4's gate predicted. `SyncStatusViewModel.isSyncEnabled` is now a **computed** read of the injected state (`:43`), so `toggleSync`/`reset` *cannot* write it — the old stored property is gone, not merely unassigned. UI seam: toolbar identifier `SyncButton` → `SyncToggleButton` (`MainStudioView.swift:424`) plus `.accessibilityValue` on **all four** render sites (`MainStudioView.swift:425`, `DetailViews.swift:140/:401/:705`) | **Wiring:** `ditto.sync.start()\|ditto.sync.stop()` in `DittoManager.swift` → exactly **2** hits (`:494`, `:505`), both inside the funnels; `SyncRuntimeState` → definition + both funnels + the view model (producer *and* consumer). **Negative lint test, executed:** a rogue `try? ditto.sync.start()` injected into `stopSyncNow` is reported as a `sync_start_choke_point` **error** — `Found 2 violations, 1 serious`, vs `0 serious` before and after — file restored and `shasum -c` verified. This is the authoritative syntax-aware check Phase 6a specified, and it needed no probe config because Phase 5b had already dropped the `DittoManager` exclusion from `.swiftlint.yml`. **Tests:** 5 new in `SyncRuntimeStateTests` (fresh state stopped; start-then-stop both ways; a repeated stop — the shape every abort path takes, including a `stopSyncNow` whose SDK call threw — still reads stopped; a repeated start still reads running; the seeded init) + the existing `a failed start leaves sync reported as stopped`, whose mock now publishes through the injected `SyncRuntimeState` only *after* the simulated SDK call succeeds. The protocol's `selectedDatabaseStopSync()` is **non-throwing**, so the plan's "a `stopSync` that throws" case is unreachable at the view-model layer; the equivalent contract (unconditional publish) is covered at the state layer instead | ✅ 2026-08-21 — **494** unit (+5) + 161 integration pass; all three builds clean; changed-file lint **0 violations in 62 files**, `swiftformat --dryrun` 0/62; repo-config lint 0 errors in 214 files. Also collapsed Phase 4's 3-tuple `transportFlags` return into a named `TransportFlags` struct (`DittoManager.swift:530`): it was the single `large_tuple` violation standing between the changed-file gate and the literal `0 violations` §8 demands, and three same-typed `Bool`s positionally is the shape a caller transposes silently |
| **6b/1** | S3 — storage errors reached the user as "The operation couldn't be completed" | `SQLCipherError` now conforms to `LocalizedError` with `errorDescription { description }` (`SQLCipherService.swift:1118`). Render sites unchanged and unchanged-by-design: `ContentView.sqlCipherInitErrorView:509` and `Ditto_Edge_StudioApp.swift:128`'s `else` branch, both of which read `localizedDescription` | 3 new `SQLCipherErrorPresentationTests`: `keyFileUnreadable`'s "NOT regenerated" guidance survives the bridge (and the generic text does not appear); all ten cases render identically through both conformances, so a new case cannot ship textless; the duplicate-Database-ID message keeps its constraint name | ✅ 2026-08-21 — 497 unit + 161 integration |
| **6b/2** | S1, S2, S10 — editor behaviour | **S1** `setType` now revokes `isAcknowledged` when it *seeds* `"True"` over a non-boolean value and the row is sensitive — gated on `canonical == nil`, so a pure re-spelling does not force a needless re-tick. **S2** `StartupSetting.canonicalBooleanValue` (`AdvancedDatabaseSettings.swift:227`) + canonicalisation in `setType` **and** on load (`DatabaseEditorView.ViewModel.init` → `startupSettings = …map(Self.canonicalizingBooleanValue)`), the init the view actually constructs (`DatabaseEditorView.swift:23`, from `ContentView.swift:302/:356`). Picker tags confirmed to be `StartupSetting.booleanValues` (`DatabaseEditorView.swift:583`). **S10** `needsSensitiveAcknowledgement(id:)` **deleted** — grep: no reference left outside one explanatory comment | **S10's three orphaned assertions re-pointed** at `hasAdvancedValidationErrors` / `startupSettingError` — the chain the Save button reads (`:138`) — rather than dropped. **The test that certified the defect is corrected**: `switching to Boolean…` asserted `value == "false"` as "an existing boolean is kept", which was an unrenderable row; it now asserts `"False"` and that the value is one of the picker's tags. 3 new tests: seeding revokes a sensitive acknowledgement and blocks Save; re-spelling keeps it; a stored `true`/`FALSE` boolean row is canonicalised on load while a String row spelling `true` is left alone | ✅ 2026-08-21 — 500 unit + 161 integration |
| **6b/3** | S9 — `initialize()` leaked a connection per Retry press | Every throwing path after a successful `sqlite3_open` now goes through one `closeConnection()` (`SQLCipherService.swift:141`), used by the open-failure guard, a `catch` around the pragmas/verify/migration block, and `resetForTesting()` — the correct teardown already existed there and simply wasn't reachable from the path that needed it. Production re-entry point: `ContentView.swift:511-518`'s Retry → `loadApps` → `initialize()` | 3 new integration tests over a deliberately corrupt store file (post-open failure — the only kind that can leak): a failed init leaves no handle; **five** Retry presses accumulate none; the failure stays a failure. **Mutation-tested:** deleting the `catch`'s `closeConnection()` fails the suite with 6 issues, exit 65 — including "Retry press 4/5 leaked its connection handle" — so the assertions are not vacuous. Needed a `#if DEBUG` `hasOpenConnectionForTesting` seam (`db` is private); DEBUG-gated per the convention S8 was filed about | ✅ 2026-08-21 — 500 unit + **164** integration |
| **6b/4** | S8 — test seams shipped in Release | `QRCodeGenerator.testPayloadString(config:favorites:)` and `(rawJSON:)` wrapped in `#if DEBUG` (`:132`, `:139`). Grep confirms no production caller — the only references are inside the file's own comment | **Release build** is the gate, since that is the configuration whose compilation changes: clean, 0 errors. Debug unit tests (`QRCodeAdvancedExclusionTests`) still compile against the seams and pass | ✅ 2026-08-21 — Release clean, 500 unit |
| **6b/5** | S6 — silent success-shaped return | `selectedDatabaseStartSync` now throws `AppError` when no database/config is selected instead of `return`ing from a `throws` function (`DittoManager.swift:435-446`). All three callers already handle a throw — `SyncStatusViewModel.toggleSync:157`, `TransportConfigView:300` and `MCPToolHandlers.swift:631` (the last already guarded `dittoSelectedApp != nil` itself) — and the function's own `catch` routes it to `appState.setError`, so the user gets a message where they previously got nothing | 1 new unit test in `DittoManagerPureDecisionsTests`, asserting the no-database-open precondition with `#require` first so it cannot pass vacuously if a future test opens one. C3 had already stopped the indicator from lying; this adds the missing message | ✅ 2026-08-21 — **501** unit + 164 integration |
| **6b — phase gate** | — | S4 and S7 **not touched** (refuted, §9.2). S7's stale Keychain-era comment stays queued for Phase 7b | 3 builds clean (Debug macOS, **Release** macOS, iOS Simulator iPad Pro 13-inch M5); **full** UI suite `Executed 15 tests, 10 skipped, 0 failures` — the 10 are the credential-gated classes (**N6**), and the 5 that run include Phase 3c's `DatabaseIdImmutabilityUITests`; changed-file lint **0 violations in 64 files**; `swiftformat --dryrun` 0/64; repo-config lint 0 errors in 216 files | ✅ 2026-08-21 |
| **5b** | C4 — drop the `DittoManager` exclusion now that C3 makes it satisfiable | `.swiftlint.yml` `sync_start_choke_point.excluded` is now `".*/AdvancedSettingsApplier\\.swift"` only — `DittoManager.swift`, the one file that contains any `sync.start()` at all, is **linted**. The single legitimate site carries an inline `swiftlint:disable:next` (`DittoManager.swift:493`) | Executed this session: with the exclusion dropped, a rogue call **inside** `DittoManager.swift` is an error (see the 6a row); without C3's funnels the file had nine sites and the rule would have been unusable. Fatality of a lint error is Phase 5a's proven property (`\|\| true` removed, build exits 65) | ✅ 2026-08-21 |
| **7a** | C2 — `reapplyAdvancedSettings` was dead code documenting a caller that never existed | **Deleted**, doc comment and all. `grep -rn "reapplyAdvancedSettings" SwiftUI --include=*.swift` → **0 hits**. The comment at `DittoManager.swift:209` that named it now names the two functions that really read the `(instance, config)` pair — `resetSystemSettingsToDefaults` and `selectedDatabaseStartSync`, both of which now throw on a nil config rather than applying nothing. `docs/ADVANCED_DATABASE_CONFIG.md` no longer claims the reset guards a query-editor `RESET ALL`; it states what actually holds (every path that *starts* sync re-applies and re-verifies scopes) and what does not (a `RESET ALL` against an already-syncing instance), and gives the only remedy — close and reopen, or toggle sync | **Deletion is its own wiring proof:** a deleted function with a live caller does not compile. Debug build clean, then all three builds clean at the phase gate | ✅ 2026-08-21 |
| **7b** | C7 + D1 — documentation that asserted a property the code does not have | All 15 false encryption claims across the five repositories replaced with a denial plus a pointer to `docs/CREDENTIAL_STORAGE.md`; `SQLCipherService`'s four (`initialize()`'s doc, the schema comment, the row-struct comment, the test-seam comment) likewise. **From the S7 refutation:** the stale Keychain-era doc comment on `getOrCreateEncryptionKey` (`kSecAttrAccessibleAfterFirstUnlock`, Secure Enclave) is deleted — it was the actual defect behind S7, and the protection class is **unchanged**. `rotateEncryptionKey`'s doc now says why it cannot work as written (`PRAGMA rekey` is another no-op). `docs/CREDENTIAL_STORAGE.md` gains a **Decision (2026-08-21)** section recording D1 option 3, what shipped, and what is folded into the option-1 follow-up. `docs/ADVANCED_DATABASE_CONFIG.md`: duplicated `### Acknowledgement is persisted` heading merged into the fuller section (`grep -c` → **1**), the spliced migration sentence repaired, the Testing section now states **N1** — the live `ALTER SYSTEM` suite does not exist, so those four questions are unverified by *any* test, not merely credential-gated. Test renamed: `Credentials stored encrypted at rest` → `Credentials round-trip through the local store`, with a comment saying what an assertion that *could* prove encryption would look like and that it would fail today | **Read, not counted:** `grep -rniE "encrypt"` over `Data/Repositories/` + `SQLCipherService.swift` — every surviving hit is an identifier, a denial, or a pointer here. Two stragglers the enumeration missed were caught by reading it: `// Get encryption key from Keychain` and `// Verify encryption worked`. Widened gate `grep -rniE "encrypted at rest\|AES-?256" --include=*.swift SwiftUI/` → only the five denials and the renamed test. Also renamed `SQLCipherError.keychainSaveFailed` → `keyFileWriteFailed` with accurate text: that string is thrown on a **file** write failure, and S3 had just made it reach the user verbatim | ✅ 2026-08-21 — 501 unit + 164 integration; all three builds; changed-file lint 0 violations in 68 files; `swiftformat --dryrun` 0/68 |
| **8a** | D2 — measure per file, and close the gap where it is closable | No production code needed: **both** pure files were already over the bar. Measured 2026-08-21 (`-enableCodeCoverage YES` + `xccov view --report --files-for-target "Ditto Edge Studio.app"`): `AdvancedDatabaseSettings.swift` **91.23%**, `AdvancedSettingsApplier.swift` **86.27%**, `SyncRuntimeState.swift` **100%**, `SQLCipherService.swift` **93.13%**, `DatabaseRepository.swift` **93.98%**. `DittoManager.swift` **13.19%** (from 3.38%), `DatabaseEditorView.swift` **13.51%** (2,176 lines, almost all `body`), `SyncStatusViewModel.swift` **23.14%**, app target overall **15.51%** | Per-function, for the exemption's condition 1: `transportFlags` **100%** (8/8), `createDatabaseConfig` **100%** (38/38), `selectedDatabaseStartSync` **40.43%** (19/47 — the S6 guard), `hydrateDittoSelectedDatabase` **0%** (0/198), `resetSystemSettingsToDefaults` **0%** (0/85), `startSyncNow`/`stopSyncNow` **0%** (0/8, 0/4). No `Ditto.open` injection seam was built — refused in §2.D2 item 3 and still refused | ✅ 2026-08-21 — 501 unit + 164 integration under coverage |
| **8b** | D2 — renegotiate the gate in writing | `docs/TESTING.md`: new **SDK-boundary exemption** section with its three conditions, the four exempt functions named with their measured coverage and the extracted decisions that carry each one, and a statement that listing a file there is a *claim* a reviewer may reject. The 80% rule now points at it in all three places it is stated (`:31`, the PR checklist, the summary). The stale "Overall Coverage: 15.96% (target: 50%)" and "SQLCipherService: 62.19%" are replaced with the measured per-file table | The discrepancy is stated, not hidden: nothing in `docs/TESTING.md` now claims 80% on `DittoManager.swift`, and the substitute coverage points at this plan's §5 manual procedures and §10 | ✅ 2026-08-21 |
| **8c** | readiness review — *is this shippable?*, as a separate pass per `FIX_VERIFICATION_RULE.md` §5 | Two independent reviewers, `model: opus`, spawned in parallel in one message, neither seeing the other's output or any rebuttal. Both were told the question was **only** ship/no-ship, given §9, §10, §2's decisions, `docs/TESTING.md`, `docs/CREDENTIAL_STORAGE.md` and the diff, and told that S4/S7, D1 options 1-2, the type/file rename and CI were out of scope | **Both returned SHIP with zero blocking objections.** Neither took the plan's word for anything: reviewer A re-ran the mutation test on `sync_start_choke_point` **twice** (a probe file and an injection into `stopSyncNow`, restoring by checksum), independently reproduced the plaintext store with the stock `sqlite3` CLI, and re-verified C1 in both the SQL and the UI layer; reviewer B re-ran all three builds, both test targets, `xccov` (matching all eight coverage figures to two decimals), all the invariant greps, and got the UI suite's `15 tests, 10 skipped, 0 failures` from a clean store. 19 non-blocking observations between them | ✅ 2026-08-22 — **converged.** Post-review actions in §9.5 |

### 9.4 Deliberately not fixed

| Finding | Reason |
|---|---|
| D1 options 1/2, type rename, file rename | §2.D1 |
| Injection seam around `Ditto.open` | §2.D2 item 3 |
| CI | §3.C4 |
| `AlterSystemTests` (N1) | §7 |
| Store-directory orphaning on rename (N2) | §7 — pre-existing |
| ~~6 `sorted_imports` + 1 `force_unwrapping` in pre-existing test files~~ | **No longer deferred — resolved in Phase 0b, 2026-08-21.** The `sorted_imports` set went with the config-conflict resolution; the `force_unwrapping` was fixed on request rather than carried as a standing exception. See §9.1 |
| `DatabaseCard.onEdit` dead parameter, `DatabaseList.swift:13`'s `onEdit: {}` (N5) | Pre-existing; Phase 3c adds only the accessibility identifier C1's UI test needs |
| Creating `testDatabaseConfig.plist` / a credentialed UI-test lane (N6) | Needs real credentials; handled as process (skip-counting + a credential-free route) rather than code |
| Refuted S* findings | §9.2 |

---

### 9.5 Post-review actions (Phase 8c, 2026-08-22)

Both reviewers said SHIP, so nothing here was blocking. Each item below was **re-verified by
execution before being touched** — the reviewer's report counts as one source, my own
evidence as the second, per `FIX_VERIFICATION_RULE.md` §2.

| Finding | Sources | Verified how | Action |
|---|---|---|---|
| **Regression introduced by Phase 6b:** the `original` snapshot was built from the raw config while the live rows were canonicalised, so opening the editor on a stored `.boolean` row spelled `true` set `hasUnsavedChanges` with no user input — arming `interactiveDismissDisabled` and a "Discard changes?" prompt | Reviewer B + code read | `normalize` preserves `value` verbatim (`DatabaseEditorView.swift:961-972`), so `"True" != "true"` | **Fixed.** The canonicalised rows go into a local that feeds both the property and the snapshot. New test `canonicalising a stored boolean on load is not an unsaved change`, **mutation-tested**: reverting the fix fails that exact assertion, exit 65. Worth recording that the first attempt at this fix (`Self.normalize(startupSettings)`) **did not compile** — `self` used before all stored properties are initialised — and the mutation run had compiled the *reverted* code, so it looked green. The full gate is what caught it, which is the whole argument for running it rather than reasoning about it |
| `SQLCipherService`'s rewritten doc comment claimed a "**Test mode (`UI-TESTING`)** fixed 64-character key" branch that does not exist | Reviewer B + grep | No `isRunningUITests`/`UI-TESTING` anywhere in `getOrCreateEncryptionKey`; the file's only such check is in `getDatabasePath` | **Fixed.** Claim deleted and replaced with how isolation actually works (per-mode directories, so each gets its own generated key). A falsehood I carried forward from the stale comment I was rewriting |
| `keyFileUnreadable`'s user-facing text claimed regeneration "would make the existing database permanently unreadable" — false while the store is plaintext, and now visible to users because S3 added `LocalizedError` | Reviewer A + D1's own evidence | `PRAGMA key` is a no-op on system SQLite, so the key is not consulted today | **Fixed.** Reworded to state the real reason (rotating a key without warning is unsafe *for an encrypted store*) with an actionable check, in the message, the enum's doc comment and the inline comment. Test now also asserts the old wording is **absent** |
| `docs/CREDENTIAL_STORAGE.md` credited `0600` on the database file, in a table framed as measured | Reviewer A + my own `ls -la` | The db file is `-rw-r--r--` (`0644`); the only `setAttributes` in the codebase is on `sqlcipher.key` (`:332`); the container chain is `drwx------` | **Fixed.** Table corrected, the real mechanism named (the 700 container, not the file mode), and the container-relative paths written down. The document's **conclusion is unchanged** |
| `docs/TESTING.md`'s exemption claimed the lint rule enforces that the funnels are the *only* writers of sync state | Reviewer A + the regex | `sync_start_choke_point` matches `sync\s*\.\s*start\s*\(` — the **start** side only | **Fixed.** The row now says so explicitly, and that a rogue `sync.stop()` is the direction that reproduces C3's bug. `.swiftlint.yml`'s own comment was already honest; TESTING.md was not |
| §10 item 13's recovery path does not exist | Reviewer B + `ls` | No `~/Library/Application Support/ditto_edge_studio*` directories; the stores are container-relative | **Fixed**, and item 13 now records B's end-to-end reproduction: a run dying before `tearDown` leaves a config that made the **next run fail 13 of 15 tests** |
| The UI suite is unreliable outside an interactive Xcode session (window-focus failures), and some failure modes degrade to `XCTSkip`, which reports green | **Both reviewers, independently** | A: `Window is not foreground…` at `UITestBase.swift:123`. B: same, plus a clean-store run that did reproduce `15 / 10 skipped / 0 failures` | **Recorded**, §10 item 12 promoted from a conditional to a measured fact. C1's shipping-path proof stands; the suite must be read as an interactive check, not a gate |
| `SyncRuntimeState`'s single-global caveat was claimed to be in §10 and was not | Reviewer B + reading §10 | — | **Fixed.** Now §10 item 15 |
| Intermittent `signal term` in the unit target; coverage figures reproduced by one reviewer only | Reviewer A / reviewer B | — | **Recorded**, §10 items 16 and 17 |

**Left for the user, deliberately not acted on:**

- **Commit hygiene (both reviewers).** Untracked and un-ignored at the repo root: `backup.ab`
  (0 bytes) and `data/dto.db{,-wal,-shm}`. `git check-ignore` matches neither, so `git add -A`
  would commit a SQLite database. Pre-existing and unrelated to this change set — and
  `.gitignore` already carries the user's own edits, so this is theirs to decide.
- **Isolating `DatabaseIdImmutabilityUITests`' store** — the durable fix for item 13. Touches a
  harness six other classes share; outside this plan's scope.
- Reviewer observations judged correct but not worth a change: the duplicate-Database-ID alert
  shows raw SQL (a known choice, §9.3 6b/1); `encodeJSON`'s `"[]"` fallback comment overstates a
  case `JSONEncoder` cannot reach; the migration dispatch inside `initialize()` is read-verified
  but untested; `KeychainService.swift` has no production references and `CLAUDE.md`'s
  "0 unused declarations" summary is stale; `scopesUnverified` and the discard toggle are not in
  the user guide; SwiftFormat's in-place build phase keeps regenerating whitespace churn.

### 9.6 Pre-commit adversarial review (2026-08-22)

One adversarial reviewer, mandate "is this safe to commit as-is?", with veto. It returned
**BLOCK on five findings — every one a false claim in documentation or a comment, none a
functional defect.** All five were re-verified by my own execution before being fixed
(reviewer + my measurement = two sources, per `FIX_VERIFICATION_RULE.md`). It independently
re-ran all three builds, both test targets, `AdvancedConfigurationUITests` (green,
**non-interactively** — better than §10 item 12 feared), `:app:compileDebugKotlin`, and
reproduced both the v4→v5 migration rollback and C1's foreign-key failure on the real table
shapes in the `sqlite3` CLI.

| Blocking finding | Verified how | Fix |
|---|---|---|
| `SQLCipherService.swift`'s ⚠️ header said "the only real protection today is `0600` permissions plus the app sandbox container" — the database file is `0644` | My own `ls -la` on the live production store; the only `setAttributes` is on `sqlcipher.key` | The header now names the **container** as the protection and states the `0644` fact explicitly. This is the same falsehood I had already corrected in `docs/CREDENTIAL_STORAGE.md` and missed here — one claim, two places |
| `.swiftlint.yml` asserted "All 580 files across the four targets are clean" | `swiftlint lint --config .swiftlint.yml` → `142 violations, 0 serious in 216 files`; `--strict` → exit 2 | Replaced with what "clean" actually means here: **0 errors**, 142 test-code warnings, 216 files — plus an explicit "do not add `--strict` to the build phase, it fails every build" |
| `docs/CODE_QUALITY_GUIDE.md` and `docs/FIX_VERIFICATION_RULE.md` both still said swiftlint **excludes** the test targets | Contradicted by `.swiftlint.yml`'s own `included:` and by the 216-file count | Both corrected. This one mattered most: `FIX_VERIFICATION_RULE.md` is mandatory reading, and it was telling readers to skip the lint pass it exists to require |
| §8's acceptance table gave `0 violations in 145 files` and `0 violations in 580 files` — unmeetable once Phase 5a broadened `included:`, and §9.1 repeated them | Same measurement | Table and §9.1 cell corrected, with the correction called out rather than silently overwritten. §8 is the authority every phase gate uses, so a stale table there is worse than a stale narrative |
| `SyncRuntimeState.swift`'s hazard 3 described `selectedDatabaseStartSync` returning silently — S6 made it throw **in this same change set** | Read `DittoManager.swift:416-421` | Rewritten as history, with why the derivation is still the right shape |

Non-blocking items also acted on, because they were cheap and real:

- **The encryption key could reach a log file.** `executePragma` threw
  `pragmaFailed(pragma:)` with the failing statement verbatim — including
  `PRAGMA key = '<64 hex>'` — and S3's `LocalizedError` had just routed that text to an
  on-screen alert *and* `~/Library/Logs/io.ditto.EdgeStudio/`, the log users are asked to
  attach to GitHub issues. Key-bearing pragmas are now redacted, with two tests. The reviewer
  established the path is effectively unreachable (Apple's SQLite returns `ok` for
  `PRAGMA key` on any file, and a key must be 64 UTF-8 bytes to get that far) — fixed anyway,
  because "unreachable" is a worse guarantee than "not printed".
- **The sync-scope DQL statements were never pinned to a literal.** Every scope test compared
  them to `AdvancedSettingsDQL`'s own constants, and the recording fake keyed its read-back row
  off the same constant — so a typo in `USER_COLLECTION_SYNC_SCOPES`, the parameter carrying
  the containment control, passed the entire suite including the read-back "verification"
  tests. New `AdvancedSettingsDQLSpellingTests` pins all three statements and the
  upper/lower-case split.
- Stale figures and references corrected: `docs/TESTING.md`'s 501 → **502** and its
  "2,176-line file" (that is the xccov *executable*-line count; the file is ~1,300 lines);
  stale `file:line` citations in `SyncRuntimeStateTests` and `docs/CREDENTIAL_STORAGE.md`
  replaced with symbol names, which do not drift; `docs/ADVANCED_DATABASE_CONFIG.md` no longer
  says `SyncRuntimeStateTests` proves publish-after-success — it drives `setRunning` directly,
  so it proves the state machine and nothing about the funnels' ordering.

One of these fixes tripped the gate, which is worth recording: the new
`AdvancedSettingsDQLSpellingTests` writes `ALTER SYSTEM SET USER_COLLECTION_SYNC_SCOPES` as a
string literal, so `sync_scopes_via_applier` fired on it and **failed the build (exit 65)** —
the custom rule catching a real occurrence, in a test target, through the fatal build phase,
unprompted. Resolved with a justified inline `swiftlint:disable:next` (it is an equality
assertion, not a write path). Phase 5a's negative test was synthetic; this one was not.

Left alone, with reason: the `rtk` shell convention and the missing `android-development`
skill in `AGENTS.md` (the user's own tooling choices, and pre-existing); the SDK bump from
`5.0.1-5.0.4` to exactly `5.1.0` riding along (load-bearing for the new `.multicast` cases,
green on both platforms, and called out in the commit message); `resetForTesting()` shipping
in Release and the `AppState`/`loadApps` double-`initialize()` race (both pre-existing,
verified against `HEAD`).

---

## 10. Known-unverified register

Shipping something unverified is acceptable; describing it as verified is not.
This list must be complete at Phase 8 sign-off.

**Carried in from the prompt — do not re-litigate, do not claim resolved:**

1. Exact `ALTER SYSTEM RESET ALL` syntax.
2. Whether `RESET ALL` reverts `updateTransportConfig`'s values.
3. Whether the SDK's argument encoder accepts `UInt64 > Int64.max` and
   `JSONSerialization`'s bridged objects (including `null`).

**Already proven against SDK 5.1.0 by a scratch SPM probe — do not re-litigate:**
`ALTER SYSTEM SET USER_COLLECTION_SYNC_SCOPES = :scopes` accepts a named parameter as
the whole right-hand side, accepts an empty map, and `SHOW user_collection_sync_scopes`
returns the shape `coerceScopeMap` parses.

**Added by this plan:**

4. **N1** — the live `ALTER SYSTEM` round-trip suite does not exist, so (1)-(3) are
   unverified by *any* automated test, not merely credential-gated.
5. C5's identity post-conditions are covered by a grep invariant and manual smoke only
   (Phase 4).
6. C3's publication from `DittoManager`'s real start/stop paths is covered by a grep
   invariant, the Phase 5 lint rule, and manual smoke only (Phase 6a).
7. The lint gate does not catch aliased `sync.start()` forms, and fires only for
   developers building in Xcode with SwiftLint installed (no CI) (Phase 5).
8. The local configuration store is plaintext (D1, option 3).
9. `hydrateDittoSelectedDatabase` (0/198), `resetSystemSettingsToDefaults` (0/85),
   `selectedDatabaseStartSync` (19/47) and the two sync funnels (0/8, 0/4) remain below
   the 80% coverage gate under the written SDK-boundary exemption (D2). Measured
   2026-08-21 and recorded in `docs/TESTING.md`; the substitute is manual smoke, not a
   test.
10. An existing config with an untrimmed stored `databaseId` keeps it (Phase 3).
11. **C3's UI-level assertion is not automated.** Reading `SyncToggleButton`'s
    accessibility value needs an open database, which needs real credentials; no
    `testDatabaseConfig.plist` exists (**N6**). The `accessibilityValue` ships as the
    seam; verification is the view-model tests plus the Phase 6a manual smoke step.
12. **Six of the seven UI-test classes currently skip** (**N6** — `AdvancedConfigurationUITests`
    does not). Everything this plan proves via UI test rests on Phase 3c's
    credential-free route working.

    **Promoted from a conditional to a measured fact by the Phase 8c review (2026-08-22),
    confirmed independently by both reviewers:** the UI suite is **not a reliable gate
    outside an interactive Xcode session**. Driven from a non-interactive shell it fails on
    `Window is not foreground and does not allow background interaction`
    (`UITestBase.swift:123`) and on `Failed to get matching snapshot` — harness-environment
    failures, not assertion failures. Reviewer B reproduced the claimed
    `15 tests, 10 skipped, 0 failures` only from a clean store in an interactive context, and
    isolated runs of `DatabaseIdImmutabilityUITests` and `AdvancedConfigurationUITests` both
    pass. So: **C1's shipping-path proof stands, but the UI suite must be read as an
    interactive check, not a CI-style gate**, and a green `xcodebuild` exit code from a
    script is not evidence about it. Note also `activateAppWindow`'s doc comment
    (`UITestBase.swift:113-117`) claims it "never fails the test"; `window.click()` can and
    does.
13. **Phase 3c's UI test can leave state behind, and it poisons the rest of the suite.**
    Cleanup runs in `tearDown`, but a run that dies before `tearDown` — including on the
    window-focus failure in item 12 — leaves a `UITest-ID-Lock-…` config in
    `ditto_edge_studio_test`. Reviewer B reproduced the consequence: the leftover card stops
    `addDatabasesFromPlist()` (`UITestBase.swift:255-259`) from skipping, and the **next run
    failed 13 of 15 tests**. Recovery is one command, and the path is
    **container-relative** — the path this register carried until 2026-08-22
    (`~/Library/Application Support/ditto_edge_studio_test`) does not exist:

    ```bash
    rm -rf ~/Library/Containers/*dittoedgestudio*/Data/Library/Application\ Support/ditto_edge_studio_test
    ```

    A durable fix (pointing `DatabaseIdImmutabilityUITests` at an isolated store rather than
    the persisted one) is **not** done — it would touch the harness six other classes share,
    which is outside this plan's scope. Recorded as a recommendation.
14. **`sorted_imports` is no longer enforced by SwiftLint** (Phase 0b). Import ordering
    is enforced only by SwiftFormat's `sortImports`, i.e. only where
    `swiftformat --dryrun` is actually run. That is a mandatory §8 gate today and there
    is no CI, so it holds exactly as far as the developer's discipline does.
15. **`SyncRuntimeState` is one process-wide flag, so it describes "the session", not "an
    instance"** (Phase 6a). On the abort paths the *losing* `Ditto` is stopped, and
    publishing `false` there can contradict a winning instance that is still syncing —
    reachable only via iPad multi-window concurrent opens. Strictly narrower than the
    hard-coded `true` it replaced. The caveat is written at `SyncRuntimeState.swift:23-30`;
    it is listed here too because revision 5's changelog claimed it was, and it was not.
16. **The unit-test target intermittently reports `Test crashed with signal term`** under
    repeated back-to-back runs (observed by the Phase 8c review at roughly 40% of runs,
    planning 404 of 501 tests, always in `AttachmentViewModel` — a pure-mock suite whose only
    diff in this change set is SwiftFormat whitespace). Three consecutive runs after clearing
    lingering `Build/Products/Debug/Ditto Edge Studio.app` host processes passed 501/501.
    **Not attributed to this change set and not diagnosed** — establishing that would need a
    HEAD comparison, which needs stashing a worktree carrying unrelated user changes. Read
    every test count in §9 as a clean-run number.
17. **Coverage percentages in §9.3 row 8a and `docs/TESTING.md` were reproduced by one
    reviewer, not two.** Reviewer B re-ran `-enableCodeCoverage YES` + `xccov` and matched all
    eight file-level figures to two decimals; reviewer A verified the exemption's *structure*
    (that the named extracted decisions exist, are pure/`nonisolated static`, and have the
    tests claimed) but did not re-measure.
