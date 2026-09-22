# iPhone Duo and iPad UI tests

The shared `Edge Studio` scheme uses one multiplatform `EdgeStudioUITests`
target. Desktop tests compile on macOS; `Mobile/` tests compile on iOS and
iPadOS. UI tests use XCTest/XCUIAutomation; fixture decision tests use Swift
Testing. The UI target's minimum iOS version matches the app at 26.0.

## Plans

| Runner plan | Xcode test plan | Coverage | Credentials |
| --- | --- | --- | --- |
| `smoke` | Edge Studio Mobile Smoke | Empty launch, registration validation/cancel, touch editing, rotation preserves a draft | None |
| `regression` | Edge Studio Mobile Regression | Smoke plus offline queries, pagination, errors, persistence, navigation, inspector, Presence/Logs actions, background/rotation | Offline Ditto license |
| `accessibility` | Edge Studio Mobile Accessibility | Native accessibility audits of the empty database list and registration form, default and dark/large-text configurations | None |
| `macos` | Edge Studio | Existing desktop UI suites | Existing desktop fixture setup |

Mobile tests fail on missing required controls or fixtures; they do not turn
failures into skips. Plans randomize ordering and run serially. Navigation
helpers open the compact sidebar and native toolbar overflow when needed.
Touch input, native edit menus, long presses, and scrolling exercise the
production controls.

The `Dark Large Text` configuration passes an environment flag to the harness,
which requests dark appearance through `XCUIDevice` and launches the app with
the largest accessibility content-size category. Device appearance is restored
afterward. On the tested iPad 27.0 beta, screenshots verify larger text but
still show a light palette; dark rendering is **not verified**. Keep that
limitation separate from the configuration name.

## Running

Install the desired simulator runtimes in Xcode, then discover destination IDs:

```bash
rtk proxy xcrun simctl list devices available
rtk proxy bash SwiftUI/run_ui_tests.sh --plan smoke \
  --destination 'platform=iOS Simulator,id=<DUO-UUID>' \
  --destination 'platform=iOS Simulator,id=<IPAD-UUID>'
```

Use IDs to avoid ambiguous names when multiple devices share a model/runtime.
Start with Duo and iPad Pro 11-inch; add iPad mini and the minimum supported
runtime to scheduled runs. Destinations are independent of test-plan
configurations. Naming a configuration “folded” would not change device pose.

```bash
rtk proxy bash SwiftUI/run_ui_tests.sh --plan regression \
  --fixture /private/path/testDatabaseConfig.plist \
  --destination 'platform=iOS Simulator,id=<UUID>'

rtk proxy bash SwiftUI/run_ui_tests.sh --plan accessibility \
  --destination 'platform=iOS Simulator,id=<UUID>'

# Run a single accessibility configuration:
rtk proxy bash SwiftUI/run_ui_tests.sh --plan accessibility \
  --configuration 'Dark Large Text' \
  --destination 'platform=iOS Simulator,id=<UUID>'
```

Each invocation creates a unique artifact directory, printed before testing.
Use `--output-dir /path/to/artifacts` to choose its parent. Each destination
gets an `xcodebuild.log`, `results.xcresult`, and, after successful Xcode
execution, a structured `summary.json`. Xcode failures retain their exit
status. Empty runs, failures, expected failures, or any skipped mobile test
fail the runner gate. Open the result bundle in Xcode for screenshots,
hierarchies, and audit details.

`--diagnostics never` disables verbose simulator diagnostic collection while
retaining test attachments and result bundles. This is useful when a beta
runtime stalls during sysdiagnose collection after a failed test.

## Offline fixture and isolation

The regression plist follows the existing `databases` array format and must
contain exactly one offline configuration with `mode: smallPeerOnly`, a
`databaseId`, and a valid `developmentToken` for offline operation. An optional
`secretKey` is supported. Provision this outside version control. Never put
credentials on the command line or copy them into documentation/results.

The runner forwards only this offline identity through Xcode's `TEST_RUNNER_`
environment mechanism. The UI runner explicitly forwards the encoded fixture
to the app process. App startup creates `Mobile UI Test Database` through the
real SQLCipher repository; cloud URLs, HTTP credentials, and all transports
are disabled. Query tests run the actual Ditto query path.

Every test gets a fresh UUID namespace before app initialization. SQLCipher,
its adjacent encryption key, Ditto directories, log patterns, and preferences
use that namespace. The persistence test deliberately reuses its UUID across
relaunches. Smoke uses an empty fixture and does not load bundled developer
credentials. Ordinary launches retain the production paths/preferences;
legacy macOS UI launches retain their existing test sandbox.

Namespaced data is retained for failure investigation. The harness does not
erase a simulator or delete another run's directories. Prefer disposable CI
simulators and retire those simulators through the CI lifecycle. Local runs
accumulate test namespaces until their dedicated simulator is retired.

## Adaptive layout and manual checks

Automated tests request rotation within a running session, check exact draft values,
exercise background/foreground transitions, and retain geometry screenshots.
They do not claim folding or Stage Manager coverage. In the initial Duo 27.1
run, the main window stayed 466 × 678 after orientation requests; those
artifacts establish draft preservation, not a landscape geometry transition. The inspected public
`XCUIDevice` and `simctl` interfaces provide orientation but no verified Duo
fold/pose command.

iPad 27.0 hierarchies confirm a window transition from 834 × 1210 to
1210 × 834 with the drafts preserved. Its immediate landscape screenshots
contain capture artifacts, so they do not establish full visual layout quality.

For release verification, use Device Hub/Simulator on a dedicated test device:

1. Open the offline workspace, type a distinctive query, and open its inspector.
2. Switch Duo inner/outer displays and supported folded poses without
   relaunching. Rotate both directions; try Split View on both sides.
3. On iPad, resize between narrow and wide windows and rotate with the software
   keyboard shown. Include the smallest supported iPad.
4. Verify the selected database, destination, query draft, and results survive.
   Reach Sidebar, Close, Inspector, query execution, Presence, and Logs actions,
   including actions moved into More. Check safe areas and scrollable forms.
5. Save before/after screenshots and hierarchy with device/runtime/pose details.
   Run manual VoiceOver/focus checks; automation audits do not replace them.

Workspace accessibility audits, RTL, physical devices, fold transitions, and
minimum-runtime compatibility are additional coverage beyond the initial
automated plans. Record their results explicitly rather than inferring them
from a successful launch on an iPhone Duo destination.

## Validation status (2026-09-22)

Tested with Xcode 27.1 beta, Duo simulator 27.1 and iPad Pro 11-inch (M5)
simulator 27.0. These results do not establish compatibility with the 26.0 floor.

| Check | Result |
| --- | --- |
| Duo regression | All 10 cases passed across the full run and focused correction reruns; no single all-green full run is claimed. |
| iPad regression | 8/10 in the full run; pagination and final registration passed focused reruns. 9 cases passed across runs; inspector dismissal remains a visible failure. |
| Accessibility | Duo: 0/4 executions passed; iPad: 1/4. Audits expose text clipping, Dynamic Type, and contrast findings. |
| Isolation unit tests | 12 methods / 19 parameterized executions passed. |
| Runner / build / lint | 5 runner tests, macOS ARM64 build, mobile build, and strict lint on all 35 changed/new Swift files passed. |
| Full macOS suite | 1062 passed, 9 UI failures, 5 skipped. Failure causality is unresolved; no pre-change baseline comparison was made. |

The failing assertions remain enabled. See the implementation record for
independent confirmations, result-bundle paths, and unverified visual claims.

## References

- [Apple: UI automation](https://developer.apple.com/videos/play/wwdc2025/344/)
- [Apple: reliable tests](https://developer.apple.com/videos/play/wwdc2022/110361/)
- [Apple: organizing tests with plans](https://developer.apple.com/documentation/xcode/organizing-tests-to-improve-feedback)
- [Apple: accessibility audits](https://developer.apple.com/documentation/accessibility/performing-accessibility-audits-for-your-app)
- [Repository Xcode skills](xcode-skills/)
- [Investigation and implementation record](../plans/2026-09-22-mobile-ui-test-strategy.md)
