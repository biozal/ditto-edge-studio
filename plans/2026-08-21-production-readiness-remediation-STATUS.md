# STATUS / RESUME — Production-Readiness Remediation (Advanced Database Configuration)

**Written 2026-08-21; updated 2026-08-22 after Phase 8c. Nothing is committed.**

Read this first, then
[`2026-08-21-production-readiness-remediation.md`](2026-08-21-production-readiness-remediation.md)
— that plan is the authority: its §9 ledger is filled in through Phase 8c, §9.5 records what
the readiness review changed, and §10 is the known-unverified register. This file exists only
so a fresh session knows where to stand.

---

## One-line state

**All eight phases are done and gated, and the readiness review converged: two independent
reviewers both returned SHIP with zero blocking objections.** What is left is not review
work — it is the two decisions listed under "Left for you" below, and then the commit.

---

## Phase status

| Phase | What it was | State |
|---|---|---|
| 0, 0b | baseline; clear this change set's lint debt | ✅ done (earlier session) |
| 1 | adjudication round — 8 confirmed, **2 refuted (S4, S7)** | ✅ done (earlier session) |
| 2 (C6) | `changedRowCount()` deleted; count returned from `execute` | ✅ done (earlier session) |
| 3 (C1, blocker) | Database ID immutable after registration | ✅ done (earlier session) |
| 4 (C5) | identity post-conditions; reset stops calling back into the actor | ✅ done (earlier session) |
| 5a | SwiftLint build gate made real and fatal | ✅ done (earlier session) |
| **6a (C3)** | `isSyncEnabled` derived from `SyncRuntimeState`; nine start/stop sites funnelled | ✅ **this session** |
| **5b** | `DittoManager` exclusion dropped from `sync_start_choke_point` | ✅ **this session** |
| **6b** | the eight confirmed single-source findings, five gated batches | ✅ **this session** |
| **7** | C2 dead code deleted; C7/D1 documentation truth | ✅ **this session** |
| **8a/8b** | coverage measured per file; gate renegotiated in writing | ✅ **this session** |
| **8c** | readiness review — *is this shippable?* | ✅ **converged 2026-08-22 — both reviewers SHIP, 0 blocking** |
| 8c follow-up | act on the review's non-blocking findings | ✅ done — plan §9.5 |

S4 and S7 were **refuted** by two independent adjudicators and must not be "fixed" by a
later session. A refutation is a result, not a gap. See §9.2 of the plan.

---

## Gate numbers as of this handoff

Re-run these before trusting them; they were green at the last Swift change. Read them as
**clean-run** numbers — see §10 item 16 on the intermittent `signal term` in the unit target,
and item 12 on the UI suite needing an interactive Xcode session.

- **506** unit + **164** integration tests passing (+5 from the two reviews: the Phase 8c
  regression test, two pragma-redaction tests and two DQL-spelling tests)
- three builds clean: Debug macOS, **Release** macOS, iOS Simulator (iPad Pro 13-inch M5)
- full UI suite: `Executed 15 tests, with 10 tests skipped and 0 failures` — the 10 are the
  credential-gated classes (no `testDatabaseConfig.plist` in this checkout, finding **N6**)
- changed-file lint: **0 violations in 68 files**; `swiftformat --dryrun` **0/68**
- repo-config lint: **0 errors** in 216 files (142 warnings, all pre-existing test-file style)
- coverage, measured per file: `AdvancedDatabaseSettings` 91.23%, `AdvancedSettingsApplier`
  86.27%, `SyncRuntimeState` 100%, `SQLCipherService` 93.13%, `DatabaseRepository` 93.98%,
  `DittoManager` 13.19% (was 3.38%), app target overall 15.51%

## Verification commands

```bash
# builds — all three must be clean (ignore only the appintentsmetadataprocessor warning)
xcodebuild -project "SwiftUI/Edge Debug Helper.xcodeproj" -scheme "Edge Studio" -configuration Debug   -destination "platform=macOS,arch=arm64" build
xcodebuild -project "SwiftUI/Edge Debug Helper.xcodeproj" -scheme "Edge Studio" -configuration Release -destination "platform=macOS,arch=arm64" build
xcodebuild -project "SwiftUI/Edge Debug Helper.xcodeproj" -scheme "Edge Studio" -configuration Debug   -destination "platform=iOS Simulator,name=iPad Pro 13-inch (M5)" build

# tests
xcodebuild test -project "SwiftUI/Edge Debug Helper.xcodeproj" -scheme "Edge Studio" -destination "platform=macOS,arch=arm64" -only-testing:EdgeStudioUnitTests -only-testing:EdgeStudioIntegrationTests
xcodebuild test -project "SwiftUI/Edge Debug Helper.xcodeproj" -scheme "Edge Studio" -destination "platform=macOS,arch=arm64" -only-testing:EdgeStudioUITests

# lint/format — pass the file list INLINE (a variable word-splits and silently lints the
# wrong set), and check the summary says the changed-file count, not 145/216
swiftlint lint  $(git status --short | awk '{print $2}' | grep '\.swift$')
swiftformat --dryrun $(git status --short | awk '{print $2}' | grep '\.swift$')
swiftlint lint            # repo config — what the fatal build phase runs
```

## Invariant greps (all currently hold)

```bash
grep -c 'ditto\.sync\.start()\|ditto\.sync\.stop()' SwiftUI/EdgeStudio/Data/DittoManager.swift   # → 2, both in the funnels
grep -rn "reapplyAdvancedSettings" SwiftUI --include='*.swift'                                    # → no hits (C2 deleted)
grep -rn "needsSensitiveAcknowledgement" SwiftUI/EdgeStudio --include='*.swift'                   # → no hits (S10 deleted)
grep -c "### Acknowledgement is persisted" docs/ADVANCED_DATABASE_CONFIG.md                       # → 1
grep -rniE "encrypted at rest|AES-?256" --include='*.swift' SwiftUI/                              # → only the five denials
```

---

## What changed this session, file by file

**New files**
- `SwiftUI/EdgeStudioUnitTests/ViewModels/SyncRuntimeStateTests.swift` — 5 tests
- `SwiftUI/EdgeStudioUnitTests/Services/SQLCipherErrorPresentationTests.swift` — 3 tests
- `SwiftUI/EdgeStudioIntegrationTests/Services/SQLCipherInitFailureTests.swift` — 3 tests

**Production**
- `Data/DittoManager.swift` — `transportFlags` returns a named `TransportFlags` struct
  (was a 3-tuple; the one `large_tuple` violation); `reapplyAdvancedSettings` **deleted**
  and the comment naming it corrected; `selectedDatabaseStartSync` **throws** instead of
  returning silently (S6)
- `Data/SQLCipherService.swift` — `LocalizedError` on `SQLCipherError` (S3); one
  `closeConnection()` on every throwing path after `sqlite3_open` (S9); `#if DEBUG`
  `hasOpenConnectionForTesting` seam; `keychainSaveFailed` → **`keyFileWriteFailed`** with
  accurate text; stale Keychain-era doc comment deleted; `rotateEncryptionKey` doc says why
  it cannot work as written; false encryption claims removed
- `Data/Repositories/{Database,History,Favorites,Subscriptions,Observable}Repository.swift`
  — every "encrypted at rest with AES-256 (SQLCipher)" claim replaced with a denial plus a
  pointer to `docs/CREDENTIAL_STORAGE.md`
- `Models/AdvancedDatabaseSettings.swift` — `StartupSetting.canonicalBooleanValue` (S2)
- `Views/Database/DatabaseEditorView.swift` — `setType` revokes a sensitive
  acknowledgement when it *seeds* a value, canonicalises boolean spelling in `setType` and
  on load; `needsSensitiveAcknowledgement` deleted (S1, S2, S10); the `original` snapshot is
  taken from the canonicalised rows (the Phase 8c regression fix)
- `Utilities/QRCodeGenerator.swift` — both test seams behind `#if DEBUG` (S8)

**Tests changed**
- `DatabaseEditorAdvancedViewModelTests` — three orphaned assertions re-pointed at
  `hasAdvancedValidationErrors` / `startupSettingError`; the test that asserted the
  blank-picker defect corrected; 3 tests added
- `DittoManagerPureDecisionsTests` — 1 test for S6's throw
- `SQLCipherServiceTests` — `Credentials stored encrypted at rest` renamed
  `Credentials round-trip through the local store`, with a comment saying what it cannot prove

**Docs**
- `docs/TESTING.md` — **SDK-boundary exemption** section (three conditions, four exempt
  functions named with measured coverage); stale 15.96%/62.19% figures replaced
- `docs/CREDENTIAL_STORAGE.md` — **Decision (2026-08-21)**: D1 option 3, what shipped, what
  is folded into the option-1 follow-up
- `docs/ADVANCED_DATABASE_CONFIG.md` — honest `RESET ALL` statement + the only remedy;
  duplicated heading merged; spliced migration sentence repaired; N1 recorded in Testing
- the plan's §9.3 / §9.5 / §10 / status header
- **Phase 8c corrections (2026-08-22):** `SQLCipherService`'s non-existent test-mode-key claim
  and `keyFileUnreadable`'s "permanently unreadable" wording; `docs/CREDENTIAL_STORAGE.md`'s
  protection table (`0644`, not `0600`, plus the container-relative paths);
  `docs/TESTING.md`'s lint-scope claim; §10 items 12-13 corrected and 15-17 added

---

## Phase 8c outcome (2026-08-22)

Two independent reviewers (`model: opus`, parallel, neither seeing the other's output) both
returned **SHIP with zero blocking objections**. Neither took the plan's word for anything:
one re-ran the `sync_start_choke_point` mutation test twice and reproduced the plaintext store
with the stock `sqlite3` CLI; the other re-ran all three builds, both test targets, `xccov`
(matching all eight coverage figures to two decimals) and the invariant greps, and reproduced
the UI suite's `15 tests, 10 skipped, 0 failures` from a clean store.

They raised 19 non-blocking observations. Each was re-verified by execution before being
touched, and the dispositions are in **plan §9.5**. The substantive ones:

- **One real regression, found and fixed:** Phase 6b's boolean canonicalisation-on-load made
  the editor report unsaved changes on open (the `original` snapshot was built from the raw
  config). Fixed, with a mutation-tested regression test.
- **Three false claims corrected** — a non-existent "test-mode fixed key" branch in a comment I
  had rewritten; `keyFileUnreadable`'s user-facing "permanently unreadable" consequence, which
  is false while the store is plaintext; and `docs/CREDENTIAL_STORAGE.md` crediting `0600` on a
  database file that is measurably `0644` (the real protection is the 700 container).
- **Two overstated guarantees narrowed** — `docs/TESTING.md` claimed the lint rule enforces the
  funnels are the *only* writers of sync state, but its regex covers `sync.start(` only; and
  §10 item 13's recovery command pointed at a path that does not exist.
- **§10 grew four items** (12 promoted to a measured fact, plus 15-17).

### Left for you — two decisions, not work

1. **Commit hygiene.** Untracked and un-ignored at the repo root: `backup.ab` (0 bytes) and
   `data/dto.db{,-wal,-shm}`. `git check-ignore` matches neither, so `git add -A` would commit
   a SQLite database. Pre-existing and unrelated; `.gitignore` already carries your own edits,
   so I left it alone.
2. **Whether to commit**, and how to split it. Nothing has been committed at any point.

Optional, recorded but not done: pointing `DatabaseIdImmutabilityUITests` at an isolated store
(the durable fix for §10 item 13 — it touches a harness six other classes share).

## If you want to re-run the readiness review

It has already converged once (above). If you want a fresh pass — for instance after the
commit is split, or if you disagree with a §9.5 disposition — paste this into a new session in
`/Users/labeaaa/Developer/ditto-edge-studio`:

> Run Phase 8c of `plans/2026-08-21-production-readiness-remediation.md`: the readiness
> review. Spawn **two independent reviewers in parallel** (one message, `model: opus`),
> neither seeing the other's output. They judge **only one question — is this change set
> shippable?** — not "is anything broken?". Inputs: the completed §9 ledger, the §10
> known-unverified register, `docs/TESTING.md`'s SDK-boundary exemption,
> `docs/CREDENTIAL_STORAGE.md`'s D1 decision, and `git diff`/`git status`. A reviewer
> objection is actionable only under the two-confirmation rule in
> `docs/FIX_VERIFICATION_RULE.md`; a single-source objection goes to adjudication, and
> refuting it is a valid outcome. Do not open new scope: S4 and S7 are refuted, D1 option
> 1/2 and the type/file rename are deliberately deferred, and CI does not exist. Record the
> verdicts in §9 and stop — do not fix anything without confirmation.

## Constraints for whoever picks this up

- **Nothing is committed, and the worktree is intentionally dirty** — it carries unrelated
  user changes. Preserve them. Do not commit without being asked.
- Use the **Xcode MCP server** for Swift file create/move (`CLAUDE.md`); the test targets are
  file-system-synchronized groups, so a new file lands in the target and compiling proves it.
- Follow `docs/FIX_VERIFICATION_RULE.md`: one reviewer's finding is a hypothesis, two
  independent confirmations make it actionable, and after any fix grep for the **production
  call site**. "It compiles and the tests pass" is not verification.
- Fix in small batches with a gate between them. Do not batch-fix a review list in one pass.
- Known recovery, if the UI suite starts failing on leftover state:
  `rm -rf "~/Library/Application Support/ditto_edge_studio_test"`.
