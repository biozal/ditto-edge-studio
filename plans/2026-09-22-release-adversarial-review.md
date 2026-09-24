# Release adversarial review — 2026-09-22

Release: [PR 32](https://github.com/biozal/ditto-edge-studio/pull/32), `release-1.0` baseline `194f36d`, compared with main `4622fae` (761 changed files). Review and builds ran in `/tmp/edge-release-review-20260922`, preserving the original checkout's version bumps and untracked documentation. The requested pre-push hook removal remains in effect.

## Review method and scope

Three reviewers independently examined the initial release: Swift A, Swift B and Android A. The coordinator independently adjudicated Android findings and later runtime failures. No reported defect was changed before two independent confirmations. Non-authors traced the shipping callers after each fix. Separate Swift and Android readiness passes followed the initial bug hunt; they approved the verified source changes conditionally, not the entire release without runtime gates.

Coverage included persistence and upgrade compatibility, session teardown/concurrency, configuration writes, logs/regex handling, query editing and result rendering, metrics, direct presence, UI harnesses, packaging and test commands. This is not a claim of exhaustive execution of every path in all 761 files. Android and Swift were both included because the request covers the release.

## Confirmed production and setup fixes

| ID | Finding and resulting behavior | Independent confirmations | Non-author verification |
|---|---|---|---|
| S1 | Rename recovery now preserves the supplied newest-first directory order instead of sorting alphabetically; explicit current name still wins | Swift A, Swift B, coordinator | Android A and Swift B traced open/delete through the resolver; ordering regressions pass |
| S2 | Swift regex preview rejects patterns barred by validation, both at editor and engine boundaries | Swift A, Swift B | Coordinator traced preview call; rejection/control tests pass; engine line coverage 100% |
| S3 | Sustained log ingestion no longer continually cancels the scan debounce; one lifecycle cadence samples the latest inputs | Swift A, Swift B | Coordinator and Swift B traced view task, background scan and guarded publication; scheduler regressions pass |
| S4 | Metrics totals belong to the Swift database session and survive destination changes; Close ends the service before teardown awaits and rejects late completions | Swift A, Swift B | Swift A and coordinator verified owner/injection/Close/deinit; production-owner regressions pass |
| S4b | Transient metrics errors no longer move the displayed zero point while retaining older totals | Android A, coordinator | Coordinator and Swift B verified independent timestamp/reset; success→interruption→recovery tests pass |
| S6 | Small-peer-only opens safely adopt a single unambiguous SDK-default store before opening the explicit persistence directory | Swift A, Swift B; coordinator SDK probe | Coordinator and Swift B verified pre-open helper wiring, conflict refusal and destination config; filesystem tests and new-store SDK reopen probe pass |
| S8 | Focused iOS editor accepts A→B→A programmatic replacements by advancing its reconciliation baseline | Swift B, coordinator | Coordinator and Android A verified updateUIView/delegate policy use; helper tests pass |
| S9 | Empty database guidance scrolls instead of clipping at accessibility text sizes | Swift A, coordinator, audit capture | Coordinator verified actual picker branch; follow-up Duo/iPad list audits pass |
| S10 | Empty-list instructions use sufficient foreground contrast | Android A, coordinator, audit capture | Coordinator verified app-owned instruction text; follow-up list audits pass |
| S11 | Registration authentication choices fall back to wrapping vertical buttons when equal-width segments do not fit | Swift A, Android A, coordinator | Coordinator verified same selection binding and form content; default/large-text interaction regression added |
| S12 | Light-mode selected segmented labels no longer disappear white-on-white; use primary fill with white text while retaining dark yellow/black | Swift A, coordinator; exported Default screenshots and actual accent asset | Coordinator traced DatabaseEditorView→authModePicker→shared component; source pair verified, fresh Duo/iPad screenshots confirm readable selected label; both mode-switch tests pass |
| A1 | Direct transport totals deduplicate two-sided edges without collapsing distinct local-only links | Android A, coordinator | Coordinator verified observer→endpoint/transport union→counts; observer-path regressions pass |
| A2 | Log-level writes update Room, session state and manager config, serialized with whole-row transport writes | Android A, coordinator | Coordinator traced dropdown→session method→mutex→all config copies; overlap regression passes |
| A3 | Server subscription imports deduplicate by trimmed query and use consistent unique row/selection keys | Android A, coordinator | Swift B verified mapper→list keys→checkbox identity; regressions pass |
| A4 | Android metric totals and zero point survive dashboard stop/start; terminal close resets them and blocks late results | Android A, coordinator | Coordinator traced session polling/disposal; lifecycle regressions pass |
| A5 | Android regex preview and matching boundary honor rejection policy | Android A, coordinator | Swift B verified editor and engine callers; rejection/control tests pass |
| A6 | Direct peer cards include local-advertised transports, matching exact endpoints and enabled transports | Swift B, coordinator | Android A and coordinator verified observer/card mapper and graph-path tests |
| A7 | Old queued teardown captures ownership before dispatch; conditional detach cannot close a replacement; config/handle pairing changes atomically | Swift B, coordinator; failing real-manager scheduling reproduction | Android A and coordinator verified identity guard, all config writers and actual-manager regressions, including same-ID replacement and multicast release |
| P1 | Release excludes ignored `testDatabaseConfig.plist` while Debug can use it | Swift A, coordinator | Coordinator verified Archive=Release and built unsigned Release bundle with no fixture present |
| P2 | Make/coverage commands select current targets, honor host/signing defaults and operate on the current checkout | Android A, coordinator | Coordinator verified commands, syntax pass, shell checks and dry runs |

Root-directory modification time remains the existing candidate ordering policy; preserving that order does not prove which divergent copy contains the newest document write. S6 moves whole directories without merging or overwriting populated stores. On case-insensitive filesystems, aliases count as one source. Multiple populated copies stop opening with an error.

## Confirmed test corrections

Each row received two independent confirmations before editing. The coordinator verified the changed interaction/assertion afterward unless noted.

| ID | Defect in the check | Confirmations and correction |
|---|---|---|
| T1 | Migration fixture opened current schema using only 5→6 | Android A + coordinator; add existing 6→7 migration to test path; production migration was already registered |
| T2 | Detached socket-test worker wrote after timeout and crashed instrumentation; blocked accept outlived cleanup | Android A + coordinator runtime/source; track/join workers, wake blocked listener, ignore only expected disconnects and propagate unexpected failures |
| T3 | Desktop harness generated touch events rather than native mouse events | Swift B + coordinator event archives; macOS click changes only, mobile taps preserved |
| T4 | Delete cleanup selected a Touch Bar button rather than confirmation | Android A + coordinator; scope to alerts/sheets; actual register/edit/delete test passes |
| T5 | Help test queried Compose semantics for a native asynchronously loaded TextView | Swift A + coordinator; bounded native Espresso wait and display assertion |
| T6 | macOS Raw JSON was exposed as value, not label | Swift A + coordinator AX captures; scoped field+token assertion accepts either representation |
| T7 | Table test could pass from editor query text | Swift A + coordinator; require selected Table segment and exact marker cell within the real results scroll view; full-plan check passes |
| T8 | Picker tests skipped when intended scene restoration reopened a studio | Swift A + coordinator; close through shipping Close control, require picker, fail if a loaded app cannot return; all four checks pass |
| T9 | iPad inspector tap was consumed by a sidebar overlay scrim | Swift B + coordinator recording/geometry; conditionally dismiss an overlapping sidebar before one inspector toggle; regular navigation selects the actual native Show Sidebar control when the compact custom toggle is absent; compact-sheet dismissal preserved |
| T10 | Large-text form helper required a lazy offscreen field before scrolling | Swift A + coordinator log/source; bounded scroll locates missing lazy fields; independent inspector helper preserved |
| T11 | Android metrics test expected no warning for unequal totals and an impossible reorder action after moving a row | Android A + coordinator; equal-total fixture and explicit original boundary-action assertions; all 19 metrics UI tests pass |
| T12 | Android presence fixture used a zero-size covered host toggle and tapped a peer hidden by a centered detail card | Android A + coordinator source/runtime geometry; real fixture button plus removal/reentry assertions; physical Back/card gestures; all 13 focused tests pass |

The registration audit has one deliberately narrow contrast exception: only `.contrast` for the identified native Save button while disabled. Swift A and coordinator confirmed the inactive-control exception in WCAG 1.4.3 and Apple's issue-specific audit workflow. Enabled Save has a separate unfiltered audit; Dynamic Type and other findings are not suppressed. Rationale and official links are in [Mobile UI testing](../docs/MOBILE_UI_TESTING.md).

## Runtime evidence

Artifacts reside under `/tmp` and are not committed. They contain local test diagnostics and should not be published indiscriminately.

- Baseline Android: 893 JVM tests passed; managed-device run exposed migration/socket failures. First complete remediation run exposed further test defects. Final full command `./gradlew assembleDebug test check assembleRelease tabletApi34DebugAndroidTest --console=plain` passed. JVM: **908 passed, zero failures/errors/skips**. Managed-device XML: **189 passed, 12 skipped, zero failures/errors** (201 actual cases; console progress count differs). Artifact: `/tmp/edge-release-android-final3-20260922.log`.
- Baseline macOS: 1064 passed, 9 UI failures, 5 skipped. Final broad run before the picker/service follow-up: **1095 test IDs passed, 0 failed, 7 skipped**, `/tmp/edge-release-macos-final-20260922.xcresult`. Parameterized execution counts differ from test IDs; do not add them together.
- Final settled macOS full run: **1104 test IDs / 1177 executions passed, 0 failed, 3 skipped**, `/tmp/edge-release-macos-final3-20260922.xcresult`. The real SDK metrics polling/Refresh/navigation test passes. Skips: credential-gated DebugSocketPoC, external MCPInsertFromFile valid-file scenario, and legacy NavigationSmoke sidebar selector. These remain explicit coverage gaps.
- Desktop picker/service follow-up: **12 test IDs / 14 executions passed, 0 skipped**, `/tmp/edge-release-macos-followup-20260922.xcresult`. This covers the four formerly skipped picker checks and service startup, retention, recovery and terminal teardown. It is not an invented all-green full-suite count.
- Fresh Duo regression: **10/10 passed, no skips**, `/tmp/edge-release-mobile-20260922/edge-ui-regression-3o6fttrl/1/results.xcresult`. Updated inspector helper also passed a focused Duo rerun.
- Fresh iPad regression: **8/10 passed**; inspector overlay and query recovery timeout required follow-up. Two runs reproduce the timeout: exact replacement text and a hittable Execute button are verified, then two 60-second UIKit animation-idle waits consume the budget. The first wait occurs before event synthesis, so this is not evidence of a 120-second SDK query execution. The next editor interaction exceeds the 180-second test budget. Swift A and coordinator found no confirmed execution-state leak or editor cause; incomplete recording and no-sample spindump do not resolve app versus UIKit/XCTest behavior. No speculative editor change or timeout increase was made.
- Accessibility follow-ups verify unclipped, sufficient-contrast list instructions on Duo/iPad. Fresh rebuilt Duo pre-audit captures verify dark appearance and AXXXL text. Earlier light captures do not establish dark coverage or prove their own cause. Latest full matrix: **4/8 executions passed per device, 4 failed, zero skipped** (two of four unique methods pass in both configurations). List and authentication-mode checks pass; empty/enabled registration audits fail. Duo reports contrast and a Dark Large Text native Save Dynamic Type flag; iPad reports contrast. Artifacts: `/tmp/edge-release-accessibility-final2-20260922/edge-ui-accessibility-bourfeie/{1,2}/results.xcresult`. This matrix precedes S12; its focused visual follow-up is recorded below.
- Coverage: DQLTextReconciliation **100% (16/16)**, LogScanScheduler **90.48% (19/21)**, PersistenceDirectoryPreparation **81.43% (57/70)**, LogPatternEngine **100%**. Service lifecycle tests cover its non-SDK functions; the separate live dashboard test exercises the real SDK reader. The final passing full run measures SystemMetricsService **100% (99/99)**, including its live SDK reader. Line coverage is not exhaustive branch or behavioral proof.
- SDK5.1 adoption probe: generated a fresh UUID default store, compiled the actual helper/AuthMode, closed/adopted/reopened the store, verified the same peer identity and resolved directory. Only generated probe stores were removed. Default SDK5.1 path preserved ID case; older documentation's lowercase assumption was not relied upon alone.
- Python mobile-runner tests: 5 passed. Full Swift syntax check passed; changed files receive strict SwiftLint and diff checks. Unsigned macOS Release builds passed (latest `/tmp/edge-release-macos-release-last-20260922.log`) and the actual app bundle contained zero test credential plists. The latest packaging check includes S12. Android Release APK is unsigned.

## Refuted, disputed and unverified claims

- Universal scan freeze at buffer capacity was refuted; sustained-ingestion cancellation starvation was confirmed separately.
- Android JSON-import result leak was refuted against installed SDK signatures.
- Slow native close after capturing an old handle could not close a newer handle. The separate delayed-before-capture race was reproduced and fixed as A7.
- HTTP advice Apply routing remains disputed: supported actionable HTTP advice responses were not established; documentation says HTTP custom indexes are unsupported. No speculative fix.
- Compact QR-sheet width remains a source hypothesis without a confirming narrow-window runtime capture. No fix.
- Native Save Dynamic Type and enabled-Save contrast flags remain unresolved. Exported Save crops show black text on pale fill in Default and white text on dark gray in Dark Large Text, refuting the assumed white-accent→white-Save-label explanation. No Dynamic Type or enabled-control contrast exemption is claimed. The separately confirmed white-on-white selected auth mode is S12.
- macOS results contain SDK/platform QoS warnings. Integration fixtures also log teardown-related SQLite messages. They were not established as shipping defects or silently described as clean runtime diagnostics.

## Release gates and decision

**Decision: not yet production ready.** The repeated iPad query recovery timeout and unresolved registration accessibility audits block a clean release-validation sign-off. Their root causes remain unconfirmed; no speculative fixes or broad audit waivers were applied. Source approval of corrected paths does not certify the whole product.

Physical transport/multicast behavior, signed/notarized installation, real authentication/HTTP end-to-end flows, the minimum supported OS matrix (only iOS 27.0/27.1 runtimes installed; 26.0 unavailable), interactive Duo fold/pose transitions, iPad Stage Manager resizing, RTL and manual VoiceOver remain unverified. Simulator rotation is not fold/resize verification. Eleven Android query-workbench scenarios remain explicitly ignored for lack of a hydrated SDK fixture and one debug-socket PoC is credential-gated; these 12 skips are gaps, not passes. Large historical store upgrades and in-app ambiguous-store error presentation need additional verification beyond the fresh SDK probe.

### Final follow-ups

- S12 desktop registration: **4/4 passed, zero skips**, `/tmp/edge-release-macos-registration-final-20260922.xcresult`, after the picker color change. The preceding full macOS plan was green as recorded above.
- S12 mobile interaction: **1/1 passed per device, zero skips**, `/tmp/edge-release-{duo,ipad}-picker-final-20260922.xcresult`. Coordinator inspected the exported Default screenshots: Development is now visible white-on-black on both devices. These focused interaction checks do not replace the failed full accessibility matrix or certify the native Save audits.
- iPad inspector/navigation/Close: **1/1 passed, zero skips**, `/tmp/edge-release-mobile-ipad-inspector-final-20260922.xcresult`. Nine of ten regression cases have passed across the full run and this follow-up; no all-green full iPad regression is claimed. The repeated query recovery timeout remains open.
- Final unsigned macOS Release build passed; app bundle exists with **zero** `testDatabaseConfig.plist` files. Android builds/checks remain green as above.
- Full Swift test syntax check passed; strict SwiftLint passed on all **32 changed/new Swift files**, and `git diff --check` passed. Generated formatter-only edits and Python caches were removed. Copied credential fixtures, SDK paths and diagnostic artifacts are excluded from the commit.
- Confirmed fixes and this ledger are committed to the existing `release-1.0` branch for PR 32. The user's unrelated version edits and untracked documents are preserved; the pre-push hook remains removed.
