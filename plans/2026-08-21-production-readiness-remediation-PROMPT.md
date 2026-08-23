# PROMPT — Advanced Database Configuration: plan the remediation, then loop adversarial plan review until two reviewers agree

Paste everything below the line into a fresh session in `/Users/labeaaa/Developer/ditto-edge-studio`.

---

You are working in `/Users/labeaaa/Developer/ditto-edge-studio` — Edge Studio, a
SwiftUI macOS/iPadOS app on Ditto SDK 5.1.0 (Swift 6.2, Xcode 26.2). A large feature
("Advanced Database Configuration": per-database collection sync scopes + startup
`ALTER SYSTEM` settings, SQLCipher schema v5, editor UI, QR-sharing exclusion) is
implemented and uncommitted in the working tree. It has been through five adversarial
review rounds. It is **not production ready**, and every previous fix round introduced
at least one new defect.

## Your task, in this order

1. **Read these first** (they are the accumulated context — do not skip):
   - `docs/FIX_VERIFICATION_RULE.md` — the mandatory two-reviewer rule you must follow.
   - `plans/2026-08-19-advanced-database-config.md` — the feature plan (revision 2).
   - `docs/ADVANCED_DATABASE_CONFIG.md` — feature docs (contains known-false statements,
     listed below).
   - `docs/CREDENTIAL_STORAGE.md` — the unencrypted-store finding.
   - `docs/TESTING.md` — testing rules (Swift Testing, AAA, 80% coverage on new code).
   - `git diff` and `git status` — the full uncommitted change set.

2. **Write a remediation plan** to `plans/2026-08-21-production-readiness-remediation.md`.
   It must be an *executable* plan: ordered phases, each with the exact files/functions
   to change, the smallest correct change, the verification command or test that proves
   it, and an explicit statement of what is left unverified. **Write no production code
   in this step.**

3. **Then run the review loop below until two independent reviewers approve the plan.**

4. **Only after approval, stop and report.** Do not implement. The user will decide when
   to execute the plan.

---

## The review loop (this is the core of the task)

Repeat until convergence or the iteration cap:

1. Spawn **exactly two adversarial reviewers in parallel**, in one message, using the
   Agent tool with `run_in_background: false` and `model: opus`. They must be
   **independent**: each gets the plan and the codebase, never the other's output, and
   never your rebuttals.
2. Each reviewer returns a verdict: **APPROVE** or **BLOCK**, plus a numbered list of
   blocking objections with `file:line` evidence and a concrete failure scenario.
3. **Convergence = both reviewers APPROVE with zero blocking objections.** Then stop.
4. If either BLOCKs: revise the plan to address **every** blocking objection (or record,
   in the plan, a reasoned refusal with evidence — a reviewer can be wrong, and refuting
   is a valid outcome under the rule). Then spawn **two fresh reviewers** and repeat.
5. **Iteration cap: 5.** If you have not converged after 5 iterations, stop and report
   the specific unresolved disagreement rather than looping further. Do not weaken the
   plan just to obtain approval — a plan that gets approved by removing scope is a
   failure, and say so if a reviewer pushes that way.

Each reviewer prompt must instruct them to judge **only**:
- Does the plan, executed exactly as written, close every confirmed defect listed below?
- Does any step introduce a regression, or repeat one of the historical failure modes?
- Is every step verifiable — is there a command, test, or observation that proves it
  worked, and does the plan say what remains unverified?
- Is the ordering safe (does a later step depend on an earlier one that could fail
  half-way, especially schema migrations)?

Reviewers may raise **new** blockers, but only with `file:line` evidence, and they must
not expand scope beyond making this change set shippable.

---

## Confirmed defects the plan MUST fix

Each was confirmed by two or more independent sources (reviewer + executed evidence).

**C1 — `updateDatabaseConfig` foreign-key regression (BLOCKER; introduced by the last fix round).**
`SwiftUI/EdgeStudio/Data/SQLCipherService.swift` (~:648-691) now includes `databaseId`
in the `SET` list with `WHERE _id = ?`. Four child tables declare
`FOREIGN KEY(databaseId) REFERENCES databaseConfigs(databaseId) ON DELETE CASCADE`
(~:363, :374, :385, :399) with **no `ON UPDATE`**, and `PRAGMA foreign_keys = ON` (:99).
Reproduced in `sqlite3`: updating the parent key with a child row present →
`FOREIGN KEY constraint failed (19)`, `changes=0`. Every database that has ever run a
query has a `history` row, so editing a Database ID now fails the whole save and loses
the name/token/scope edits submitted with it.
Smallest fix: keep `WHERE _id = ?`, remove `databaseId` from the `SET` list, and disable
the Database ID field for existing configs (`DatabaseEditorView.swift` ~:71).
Full fix (if the plan chooses it): a v6 migration recreating the four child FKs with
`ON UPDATE CASCADE`, **plus** renaming the on-disk Ditto store, because
`DittoManager.localDirectoryPath` embeds `name-databaseId`. The plan must pick one and
justify it.

**C2 — `reapplyAdvancedSettings` is dead code with a doc comment naming a caller that does not exist.**
`SwiftUI/EdgeStudio/Data/DittoManager.swift` ~:315. Zero callers (verified by grep). It
was documented as the mitigation for a user typing `ALTER SYSTEM RESET ALL` into the
query editor, which clears in-memory scopes under a running session. Either delete it
and remove the claim, or wire it and name the call site.

**C3 — post-reset sync state is not reflected in the UI.**
`DittoManager.resetSystemSettingsToDefaults` stops sync (and on failure deliberately
leaves it stopped) without informing `SyncStatusViewModel.isSyncEnabled`
(`SyncStatusViewModel.swift` ~:31, :126-134). The toolbar keeps showing the old state,
and the first recovery tap takes the wrong branch. The `TransportConfigView` restart
path (~:293-320) has the same gap.

**C4 — the SwiftLint rules that replaced a deleted test enforce nothing.**
`.swiftlint.yml` `custom_rules: sync_start_choke_point` / `sync_scopes_via_applier`.
Three independent problems: the build phase is
`swiftlint lint --config .swiftlint.yml --quiet || true` (`project.pbxproj` ~:370) so
the exit status is discarded; there is no CI (`.github/workflows` does not exist); and
`excluded: ".*/(AdvancedSettingsApplier|DittoManager)\.swift"` exempts
`DittoManager.swift`, which contains **all three** `sync.start()` sites. Both reviewers
defeated the regexes with `let s = ditto.sync; try s.start()` and a lowercase
`user_collection_sync_scopes`. Either make the gate real (fail the build / add CI, drop
the `DittoManager` exclusion and use inline `swiftlint:disable:next` on the three
legitimate sites, case-insensitive regex) or withdraw the claim that the invariant is
enforced and rely on the `OpenSequence` type plus its tests.

**C5 — the reset path lacks the identity post-condition `hydrate` has.**
`DittoManager.resetSystemSettingsToDefaults` awaits `OpenSequence.run`, whose
`applyTransportConfig` closure calls back into the actor and reads `dittoSelectedApp`
fresh rather than the captured `ditto`. `hydrate` guards this with
`guard dittoSelectedApp === ditto`; reset and `selectedDatabaseStartSync` do not.
Switching or closing the database mid-reset either throws "No Ditto app is currently
selected" or configures a different instance while the `ALTER SYSTEM` statements and
`sync.start()` target the captured one.

**C6 — `changedRowCount()` is latently wrong.**
`SQLCipherService.swift` ~:993, used at ~:685. `sqlite3_changes` is connection-wide and
read after the statement is finalized; correct only because nothing on that path
suspends. Return the count from `executeWithParameters` instead.

**C7 — documentation still contains false statements.**
Five repository files still claim "encrypted at rest with AES-256 (SQLCipher)"
(`DatabaseRepository`, `HistoryRepository`, `ObservableRepository`,
`SubscriptionsRepository`, `FavoritesRepository`), and
`EdgeStudioIntegrationTests/Services/SQLCipherServiceTests.swift` ~:377 has a test named
`Credentials stored encrypted at rest` that only round-trips strings. Also in
`docs/ADVANCED_DATABASE_CONFIG.md`: a duplicated `### Acknowledgement is persisted`
heading and a garbled spliced sentence around the migration section.

## Single-source findings — ADJUDICATE, do not fix on sight

Per `docs/FIX_VERIFICATION_RULE.md`, each of these has one source. The plan must state,
for each, whether it will be adjudicated (two independent confirmations) before any code
change, or deliberately deferred with a reason. Do **not** plan speculative fixes.

- `ViewModel.setType` seeds `value = "True"` directly, without revoking a sensitive
  row's `isAcknowledged` (`DatabaseEditorView.swift` ~:1037).
- The Boolean value `Picker` tags are exactly `"True"`/`"False"`, so a stored lowercase
  `true` renders with no selection — and `DatabaseEditorAdvancedViewModelTests` ~:317
  asserts that state as correct.
- `SQLCipherError` conforms to `CustomStringConvertible` but not `LocalizedError`, so
  every storage error reaches the user as "The operation couldn't be completed. (… error
  N.)" — including the new `keyFileUnreadable` guidance and the duplicate-Database-ID
  case (`ContentView.swift` ~:505, `Ditto_Edge_StudioApp.swift` ~:127).
- Corrupt `startupSettings` JSON decodes leniently to `[]` and is then silently
  overwritten with `"[]"` on the next save — no banner, no discard toggle, unlike the
  sync-scope path.
- The reset path passes `config.isBluetoothLeEnabled` etc. straight through, bypassing
  the `isRunningUITests()` gate that `hydrate` uses to keep BLE/LAN off under UI tests.
- `selectedDatabaseStartSync` returns silently when `dittoSelectedAppConfig` is nil,
  after which `toggleSync` sets `isSyncEnabled = true`.
- `.completeFileProtection` may be the wrong class for the documented
  "accessible after first unlock" intent (`.completeFileProtectionUntilFirstUserAuthentication`).
- `QRCodeGenerator.testPayloadString(config:favorites:)` / `(rawJSON:)` ship in Release
  while the comparable seams are `#if DEBUG`.
- `initialize()` leaks a `sqlite3` connection per Retry press when `verifyEncryption`
  throws.
- `ViewModel.needsSensitiveAcknowledgement(id:)` has tests but no production caller.

## Two decisions the plan must make explicitly

**D1 — the unencrypted credential store.** `docs/CREDENTIAL_STORAGE.md` proves the store
is plaintext: no SQLCipher is linked, `import SQLite3` is Apple's system library where
`PRAGMA key` is a silent no-op, and the live file begins with `SQLite format 3`. Choose
option 1 (link SQLCipher + `sqlcipher_export` migration), option 2 (move the five
credential columns to the Keychain), or option 3 (accept plaintext and purge every
contrary claim, including the type and file names). State the migration for existing
installs and whether this blocks release or ships as a tracked follow-up.

**D2 — the coverage gate.** Measured coverage of the new code is ~35-40% against
`docs/TESTING.md`'s mandatory 80%. `DittoManager` is at 3.38%, with
`hydrateDittoSelectedDatabase` at 0/200 lines, because it needs a live `Ditto`. Either
plan the seam that makes it testable (inject the instance creation), or renegotiate the
gate in writing with the reason. Do not leave the discrepancy unstated.

## Known-unverified — do not claim otherwise

- Exact `ALTER SYSTEM RESET ALL` syntax.
- Whether `RESET ALL` reverts `updateTransportConfig`'s values.
- `UInt64 > Int64.max` and `JSONSerialization`'s bridged objects (including `null`)
  through the SDK's argument encoder.

Already **proven working** against SDK 5.1.0 by a scratch SPM probe — do not re-litigate:
`ALTER SYSTEM SET USER_COLLECTION_SYNC_SCOPES = :scopes` accepts a named parameter as
the whole right-hand side, accepts an empty map, and `SHOW user_collection_sync_scopes`
returns the shape `coerceScopeMap` parses.

## Historical failure modes the plan must actively guard against

These are the ways previous rounds failed. The plan must state how each is prevented:

1. **Fix-by-assertion** — a method written and declared done with no production caller
   (`sanitizedForSharing`, then `setParameter`/`setValue`/`setType`, then
   `reapplyAdvancedSettings`). Every fix step must name the call site that will use it.
2. **Tests aimed at the fix, not the feature** — five tests once certified an
   acknowledgement control the UI bypassed; the Database-ID test passed because its
   fixture had no child rows. Every test step must state the production path it covers.
3. **Hardening without a threat trace** — `.completeFileProtection` was correct in
   isolation and created a data-destruction path in context.
4. **Batch-fixing a long list in one pass** — plan small batches with verification
   between them.
5. **Claiming clean tooling without running it on the changed files** — `swiftlint`'s
   config excludes test targets, so "lint clean" was true of the config, not the code.

## Verification commands (use these, in the plan and in review)

```bash
# builds — all three must be clean (exclude the appintentsmetadataprocessor warning)
xcodebuild -project "SwiftUI/Edge Debug Helper.xcodeproj" -scheme "Edge Studio" -configuration Debug   -destination "platform=macOS,arch=arm64" build
xcodebuild -project "SwiftUI/Edge Debug Helper.xcodeproj" -scheme "Edge Studio" -configuration Release -destination "platform=macOS,arch=arm64" build
xcodebuild -project "SwiftUI/Edge Debug Helper.xcodeproj" -scheme "Edge Studio" -configuration Debug   -destination "platform=iOS Simulator,name=iPad Pro 13-inch (M5)" build

# tests
xcodebuild test -project "SwiftUI/Edge Debug Helper.xcodeproj" -scheme "Edge Studio" -destination "platform=macOS,arch=arm64" -only-testing:EdgeStudioUnitTests -only-testing:EdgeStudioIntegrationTests
xcodebuild test -project "SwiftUI/Edge Debug Helper.xcodeproj" -scheme "Edge Studio" -destination "platform=macOS,arch=arm64" -only-testing:EdgeStudioUITests/AdvancedConfigurationUITests

# coverage (per file, not aggregate)
xcodebuild test ... -enableCodeCoverage YES && xcrun xccov view --report --only-targets <path-to-xcresult>

# lint/format — on the CHANGED files explicitly, tests included
swiftlint lint --strict $(git status --short | awk '{print $2}' | grep '\.swift$')
swiftformat --dryrun $(git status --short | awk '{print $2}' | grep '\.swift$')
```

Baseline as of this prompt: 478 unit + 160 integration tests pass, the UI test passes,
all three builds are clean, production lint is clean, 6 pre-existing `sorted_imports`
errors remain in test files whose import blocks predate this work.

## Constraints

- `plans/` for plans, `docs/` for approved documentation (repo convention).
- Preserve unrelated user changes; the worktree is intentionally dirty.
- Do not commit anything.
- Note: `SwiftUI/EdgeStudio/Data/SQLCipherService.swift` contained pre-existing
  uncommitted edits before this work began — do not attribute all of it to the feature.
