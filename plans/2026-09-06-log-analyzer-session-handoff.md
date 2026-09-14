# Session handoff — Log Analyzer parity + UI fixes (2026-09-05 → 2026-09-06)

**Branch:** `swiftui-presence-multicast` · **Nothing is committed** (44 modified, 28 new).
**Companion docs:** [`docs/LOG_ANALYZER_SPEC.md`](../docs/LOG_ANALYZER_SPEC.md) (normative, tri-platform),
[`plans/2026-09-05-log-analyzer-tri-platform-parity.md`](2026-09-05-log-analyzer-tri-platform-parity.md) (original plan).

Everything below was verified by running builds/tests, not by inspection alone. Claims that are
**unverified** are labelled as such — do not upgrade them without evidence.

---

## 0. Environment gotchas (read first — these cost time repeatedly)

| Thing | Value / workaround |
|---|---|
| **Xcode 27** | `/Applications/Xcode-beta.app`. Use `export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer` — do **not** `xcode-select` (global). `/Applications/Xcode.app` is 26.6. |
| **DerivedData conflict** | The user usually has Xcode open on this project. Pass `-derivedDataPath <scratch>/DD27` or builds fail with `database is locked`. |
| **Android JDK** | Plain `./gradlew` fails with `jlink … redhat.java … does not exist` (Gradle auto-detects a VS Code JRE). Always prefix `JAVA_HOME=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home`. |
| **Gradle flakiness** | A first build reporting FAILED then an immediate retry reporting `BUILD SUCCESSFUL … up-to-date` means it **did not recompile**. Happened 4×. Always `./gradlew --stop` then `--rerun-tasks` before believing a green result. |
| **Test device** | Samsung **Galaxy Z Fold 5**, serial `RFCW90F7G4B` (`SM_F946U1`). This is *not* the tablet `R5GL15XPVGA` in the older memory note. Unfolded = **690dp** wide (1812px @ 420dpi). |
| **Instrumented tests** | Standing instruction: **never** run `connectedAndroidTest` / managed-device tests. `adb install` is fine and is how the user smoke-tests. |
| **Real SDK captures** | `~/Library/Containers/com.costoda.dittoedgestudio/Data/Library/Application Support/ditto_edge_studio/*/database/ditto_logs/*.log*` — 33 files, ~746k records. Include `.log.gz`; forgetting them caused a wrong measurement (see §4). |

### Verification commands

```bash
# SwiftUI (both platforms + tests + lint)
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
DD=/tmp/DD27
xcodebuild -project "SwiftUI/Edge Debug Helper.xcodeproj" -scheme "Edge Studio" -configuration Debug \
  -destination "platform=macOS,arch=arm64" -derivedDataPath "$DD" build
xcodebuild -project "SwiftUI/Edge Debug Helper.xcodeproj" -scheme "Edge Studio" -configuration Debug \
  -destination "platform=iOS Simulator,name=iPad Pro 13-inch (M5)" -derivedDataPath "$DD" build
xcodebuild test -project "SwiftUI/Edge Debug Helper.xcodeproj" -scheme "Edge Studio" \
  -destination "platform=macOS,arch=arm64" -derivedDataPath "$DD" -only-testing:EdgeStudioUnitTests
swiftlint lint --strict --quiet <changed files>

# Android
cd android && JAVA_HOME=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home \
  ./gradlew :app:assembleDebug :app:testDebugUnitTest --rerun-tasks

# Install on the Fold
~/Library/Android/sdk/platform-tools/adb -s RFCW90F7G4B install -r \
  android/app/build/outputs/apk/debug/app-debug.apk
```

**Green baseline as of this handoff:** SwiftUI macOS + iPad build clean, **797 unit tests**, swiftlint
`--strict` exit 0. Android `assembleDebug` clean, **743 unit tests**.

---

## 1. What shipped

### SwiftUI

- **Log Analyzer analytics layer** — `LogAnalytics`, `LogConnectionTracker`, `LogEntryContext`,
  `LogScanResult`, `LogAnalyticsSection`, `LogFilterTabs`, + 3 test suites.
- **`LogEntryRowView` refactor** — expansion state lifted to the parent, ±5 context lines from the
  **unfiltered** buffer, raw-line display, Copy With Context.
- **Summary block removed** (user call — duplicated the filter-tab badges). Histograms retuned to
  150pt charts / 340pt bounded region so they don't scroll.
- **Window lock-up fixed** — the app uses `.windowResizability(.contentSize)`, so the window is sized
  from content's *minimum*. ~330pt of incompressible fixed height (two `frame(height: 110)` charts +
  a `GeometryReader`) pushed the window past the screen. Now inside a bounded `ScrollView`;
  `GeometryReader` deleted.
- **Connection Durations** rebuilt as a `label │ ProgressView │ count` row list (Swift Charts was
  wrong for 5 categorical buckets at that height).
- **Peers scroll-stutter fixes** — equality gates on `mergeStatusItems` + `connectionsByTransport`,
  `SyncStatusInfo.==` widened to "identical as rendered", hot reads confined to leaf views,
  `PeerCard: View, Equatable` extracted, grid animation re-keyed to `map(\.id)`.
- **Sidebar** — collection name + count now stack (was hyphenating `cus-tomer s` and wrapping
  `25,000` into `25,00` / `0`, i.e. a **wrong number**).
- **`DittoSegmentedPicker`** — brand-yellow selection in **dark mode only**; light mode falls back to
  `Color.accentColor`. Applied to 10 of 12 segmented pickers.
- **QR** — module scale 10→20, EC `"M"`→`"L"` (147→131 modules at the 2200-byte cap), quiet zone no
  longer clipped by `cornerRadius`, window 620×800, display 500pt (380 on iPadOS).
- **`no-use-throwing-unstructured-task`** warnings (Xcode 27) fixed in `QueryToolbarView`.
- **iPadOS `openWindow` guard** — `welcome-window` / `help-window` / `font-debug-window` receivers
  were unguarded while the scenes are macOS-only.

### Android

- **Full Log Analyzer port** — data layer + Compose UI, built by subagents, verified by me.
- **P0: microsecond timestamps** — `SimpleDateFormat("…ss.SSSSSS'Z'")` parsed `.784135` as *784,135
  milliseconds*. Proven on JDK 21: `20:43:51.784135Z` → `20:56:55.135`, **13 minutes late**. Now
  `java.time.Instant.parse`. This corrupted every duration/bin/range.
- **P0: live stream truncated to 200 entries** — `emitSnapshot()` published
  `liveBackingStore.takeLast(200)` into the only StateFlow the UI reads, so all analytics ran on ≤200
  live lines. Now publishes the whole store; the 200 cap moved to the display layer, with the merge
  moved off the composition thread (`combine(...).conflate().flowOn(Default)`, linear two-pointer
  merge).
- **A11 rescan stall** — live store trims to *exactly* the cap with no slack, so a size-keyed
  `snapshotFlow` goes permanently silent at 10,000 entries. Fixed with a monotonic `ingestSequence`.
- **Re-init marker** — keyed on `"starting Ditto"` (message-scoped), recovering **+28 sessions**,
  longest 22.99h.
- **Component classification** — 866 divergent records → **0**; Transport rows 3,367 → 4,233.
- **QR decode fixed** (see §3), time-domain histograms, level chips on all sources, full badge
  numbers, Copy With Context, persisted SDK log level, collapsed-by-default histograms.
- **List pane width** — was a flat 300dp (**43%** of the Fold's 690dp window). Now
  `LIST_PANE_WIDTH_FRACTION = 0.30f` bounded 200–320dp, **plus a draggable divider**.
- **Collection tap** now loads `SELECT * FROM <name>` (chevron still expands indexes).
- **Query Metrics header fixed** — title wrapped one character per line at the narrower pane.

---

## 2. What's left

### 2a. SwiftUI review ledger — **highest value, all verified as still broken**

Android is now *more correct than SwiftUI* on the first four, because the porting agents were told not
to copy them forward and SwiftUI was never gone back to.

| # | Finding | file:line | Agents | Impact |
|---|---|---|---|---|
| 1 | `get_ditto_logs` returns `[]` **unconditionally** — `parseDirectory` is non-recursive and is handed the bare persistence dir | `Data/MCPServer/MCPToolHandlers.swift:871` | 3 | MCP tool 100% dead, fails silently |
| 2 | `span.connection_id` unread (only top-level) — **92%** of records fall back to fuzzy `remote::role` | `Data/LogConnectionTracker.swift` `StructuredFields` | 3 | 24–34% of sessions mis-paired |
| 3 | Tracker rebuilt over the 5,000-entry scan window | `Data/LogAnalytics.swift:223` `LogConnectionTracker.track(entries)` | 3 | `5m+` bucket reads 0 where truth is 17 |
| 4 | Badges computed over the scan window, list filters the whole buffer | `LoggingDetailView` | 3 | Badges under-report above 5,000 entries |
| 5 | Pause gates the **filter task**, disabling search/chips/tabs | `LoggingDetailView` `guard !Task.isCancelled, !isPaused` | 4 | Controls interactive but inert |
| 6 | Scan debounce 500ms > flush cadence 250ms | `LoggingDetailView` `milliseconds(500)` | 3 | 1–22s staleness (measured over 20 captures) |
| 7 | `FilterInputs` keyed on id-set **counts**; `userTagsByID` in neither task id | `LoggingDetailView` | 3 | Stale rows after a pattern edit |
| 8 | "Level filtered by the Problems tab" is false (`.problem`/`.critical` constrain no level) | `LoggingDetailView` + `LogFilterTabs.swift` | 3 | Android already has honest copy |
| 9 | Two level palettes on one screen | `LogAnalyticsSection.swift` vs `LogEntryRowView.levelColor` | 3 | Cosmetic |
| 10 | Severity-1 colour `.gray`, spec says `#888888` | `LogPatternManagerView.swift:10` | — | SwiftUI is the off-spec side; Android is correct |
| 11 | Dead output: `LogAnalytics.sessions`, `tracker.reinits`, `unmatchedEnds` | — | 2 | Cost per scan, no readers |
| 12 | `await Task.detached(...).value` is non-cancellable — a cancelled scan burns ~25ms | `LoggingDetailView:161` | 1 | Wasted CPU |
| 13 | `[PresenceDiag]` debug logging, one line per peer per emission | `SystemRepository.swift:250-260, 435-447, 789-813` | 2 | Its own comment says temporary |

Also: **`QueryToolbarView` is dead code** — only reference is its own `#Preview`. `InspectorViews`
is the live equivalent. Keep-or-delete is a decision, not a bug.

### 2b. VS Code — **not started**

Work Item B from the original plan. Both APIs confirmed present in `@dittolive/ditto` 5.1.0
(`types/ditto.d.ts`): `Ditto.observeTransportConditions(cb)` at :2891, `Presence.connectionRequestHandler`
at :1766. Design is written up in the plan doc §3. Recommended approach: emit into the existing
`Logger` with dedicated tags so the lines flow through `AnalyzerSink` and get search/patterns/histograms
for free. **Must** close the `Observer` on disconnect (the d.ts warns it prevents process exit) and the
handler must always return `'allow'` — it is log-only. ~2 days. Then optionally §4 (transport-condition
problem patterns) once real text is observed.

### 2c. Needs the device / a human — cannot be settled by code review

- Whether the **peers scroll stutter** actually improved → Instruments **Animation Hitches** + SwiftUI
  template on the iPad. No agent can do this.
- **`.textSelection(.enabled)` blocking row expansion** (`LogEntryRowView.swift:51` vs the
  `onTapGesture` at `:63`). Two reviewers independently concluded it is undecidable statically; Apple
  documents no gesture-precedence contract. Test: click directly on message glyphs.
- **Light mode** appearance of the segmented pickers, both platforms.
- Whether the **QR scans** now. **Try "Include favorites" off first** — that toggle defaults on and is
  what pushes the payload to the 2200-byte cap (147 modules). Without favorites ≈83 modules.
- Android: analytics continuing to update **past 10,000 live entries** (the A11 fix is proven by unit
  tests + a wiring grep, never observed running).
- Android: `rememberSaveable` histogram state across rotation/process death; the Copy With Context
  clipboard payload; the Room round-trip of the persisted log level.

### 2d. Smaller / opportunistic

- SwiftUI peer cards use `.frame(minHeight: 280)` → non-uniform grid rows → scroll content height
  corrected mid-gesture. Making them fixed-height would stabilise it but is a visible design change.
- SwiftUI peer cards contain nested vertical `ScrollView`s + `.textSelection(.enabled)` inside
  `DisclosureGroup`s — best remaining explanation for "fine on Mac, bad on iPad" gesture arbitration.
- `DittoSegmentedPicker` not applied to `QueryResultsView` — its segments carry per-segment ids that
  `QueryResultsUITests.swift:173` queries as `app.radioButtons[...]`. A custom `Button`-based control
  exposes them as `buttons`, so converting **requires** updating that test.
- Android pane drag position may not survive fold/unfold or process death — `rememberPaneExpansionState`
  is called without a key provider. Unverified.
- QR payload is `EDS2:` + base64(zlib(JSON)). base64 inflates 33% *and* forces QR byte mode. **base45**
  (what EU COVID certs use) maps to alphanumeric mode, ~23% fewer bits ≈ 15 fewer modules. This is a
  **cross-platform wire-format change** — SwiftUI and Android decoders must ship together.

---

## 3. The QR bug — worth understanding, it will recur

The Mac-generated QR failed on Android with *"not a valid database config"*. **Not a QR problem.**

SwiftUI's SDK-5 rename changed the payload keys and Android was never updated:

| SwiftUI emits | Android required |
|---|---|
| `developmentToken` | `token` |
| `url` | `authUrl` |
| *(not emitted — derived from auth URL)* | `websocketUrl` |

With `ignoreUnknownKeys = true`, kotlinx silently dropped the new keys then threw
`MissingFieldException` on the three missing required ones. SwiftUI keeps the old spellings as
`LegacyCodingKeys` for decode; Android had no equivalent.

Fixed via `@JsonNames` aliases + `useAlternativeNames = true`, with regression tests pinning **both**
generations. The VS Code extension is **not** part of this protocol (no `EDS2` anywhere in it).

**The lesson:** both sides had passing tests, each testing itself against its own format. Nothing tested
Swift-encode → Kotlin-decode. The new tests pin the *wire format*, which is the part that must agree.

---

## 4. Refutations — recorded so they are not re-litigated

Several confident claims (some mine) were disproved by measurement. Do not act on them again.

| Claim | Verdict |
|---|---|
| LIFO session pairing is a regression vs VS Code's FIFO | **Refuted.** Scored against ground truth by two agents: LIFO 67–82% exact-pair vs FIFO 29–57%. FIFO over-counts `5m+` 2.4×. Porting the reference would make it worse. Only the *comment* was wrong (cites the wrong key). |
| `ditto_init` re-init never fires | **Refuted.** `LogFileParser` falls back to the whole raw line when a record has no `message` key, and the init record is exactly that shape. It fires and is load-bearing (closes 37/162 sessions on the largest corpus). My own "verification" measured the JSON `message` field, not what Swift actually puts in `.message`. |
| SwiftUI closes killed sessions with inflated durations | **Refuted.** Measured downtime gap between last log line and restart: **0.0 min in all 27 cases**. `ditto_init` fires when the user *switches databases*, not on a crash — the app keeps running. SwiftUI's durations are correct; Android's old behaviour (dropping them) was wrong. |
| Mixed-id mis-pairing is reachable | **Refuted.** 0 occurrences in 383 real events; the two encodings are temporally disjoint by SDK version. Latent only. |
| Peers stutter is caused by `.animation(value: syncStatusItems)` + cell transitions | **Refuted.** `SyncStatusInfo.==` is hand-written and *excludes* the volatile fields blamed. Real cause is invalidation rate + `syncStatusCard` being a function with no `Equatable` boundary. |
| QR is black-on-transparent in dark mode | **Refuted.** Background is opaque white (`a=1.00`). |
| The re-init marker is 1:1 with `starting Ditto` in every file | **Refuted.** 11 vs 14 — three captures have `starting Ditto` and no span marker. My count only globbed `*.log`, not `*.log.gz`. |
| `ditto_init` appears inside `path` values | **Refuted.** It lives in `span` / `spans`. My spec doc asserted `path` as measured fact; it was wrong. |

---

## 5. Process notes

- The user's standing bar: **two agents must independently agree before a finding is worked on.**
  Single-source findings go to a targeted adjudication round (confirm *or refute*) first. See
  [`docs/FIX_VERIFICATION_RULE.md`](../docs/FIX_VERIFICATION_RULE.md).
- 8 agents ran on the SwiftUI review (4 finders + 4 adjudicators), 5 on Android. Confirmation counts
  are in the table in §2a.
- **Three of my own "verified" claims were wrong**, each caught by an agent, each because I measured
  something adjacent to what the code actually does. Prefer executing the real code path over
  reasoning about it.
- The user does the visual verification. Layout claims are not verified until they say so — the window
  lock-up, the hyphenated sidebar, and the Query Metrics header were all found by the user *after*
  clean builds and green tests.

---

## 6. Recommended order

1. **Commit** the current tree — 72 files of working, verified work on one branch is a lot to carry.
2. **SwiftUI ledger §2a**, smallest first: #1 (one-liner), then #2 and #3 (both make the durations
   chart wrong today), then #5/#6/#7. Fix in small batches, verify each — do not batch-fix the list.
3. Decide **`QueryToolbarView`** (delete or keep) and the **`[PresenceDiag]`** logging.
4. **VS Code Work Item B** (§2b).
5. Revisit **§2d** opportunistically.
