# Component Testing Initiative (2026-06-07)

Goal: start lifting the largely-untested `Components/` (10,228 lines @ 0.22%) and
`Views/` (16,642 @ 8.77%) coverage. Chosen approach: **hybrid** — fast Swift
Testing logic tests that run in CI today, plus a scaffolded XCUITest harness for
when credentials + Accessibility permissions are in place.

## Ground truth
- All test targets are **file-system-synchronized roots** — drop a `.swift` file
  into the target dir and it's auto-compiled. No pbxproj/Xcode-MCP edit needed.
- Test module: `@testable import Ditto_Edge_Studio`.
- Unit/integration tests use **Swift Testing** (`import Testing`, `@Suite`/`@Test`).
- UI tests use **XCTest/XCUITest** (no Swift Testing alternative).
- UI tests are blocked at runtime on: missing `testDatabaseConfig.plist` (real
  credentials) and manually-granted macOS Accessibility permissions. They must
  `XCTSkip` gracefully when those are absent.
- Existing patterns to mirror: `EdgeStudioUnitTests/ViewModels/QueryViewModelTests.swift`,
  `ViewModels/ViewModelMocks.swift`, `Components/PlanNodeBoxTests.swift`,
  `Models/QueryProfileParserTests.swift`, `TestTags.swift`.

## Workstreams (parallel, write-only — no xcodebuild in agents to avoid
## DerivedData/CodeSign contention; one consolidated build+test pass at the end)

### A. ViewModel logic tests  → `EdgeStudioUnitTests/ViewModels/`
AttachmentViewModel, SyncStatusViewModel, MainStudioViewModel (and extend
QueryViewModel / SubscriptionObserverViewModel where gaps exist). Test observable
state transitions, computed properties, error paths — using the mock set.

### B. Component logic tests  → `EdgeStudioUnitTests/Components/`
Logic-bearing components only (NOT view-body layout): PaginationControls page math,
Pill/badge logic, Result/Json viewer formatting helpers, ProfileViewer card helpers,
MetricCard/NetworkInterfaceCard formatting, DetailBottomBar state. Skip components
whose logic can't be reached without @Environment/@State.

### C. XCUITest harness + smoke flows → `EdgeStudioUITests/`
Foundational base case + helpers per docs/TESTING.md (waitForAppToFinishLoading,
addDatabasesFromPlist with XCTSkip, ensureMainStudioViewIsOpen, screenshot helper)
and a few smoke tests (launch→ContentView, add-DB flow, navigate to Collections/
Observer). Must compile and XCTSkip cleanly without credentials/permissions.

## Verification (orchestrator, after agents return)
1. `xcodebuild clean` then `build-for-testing` (macOS) — fix any compile errors.
2. `test-without-building -only-testing:EdgeStudioUnitTests` — all green.
3. iOS app build sanity (test targets are macOS).
4. Re-measure Components/Views coverage delta.

## Out of scope (this pass)
Exhaustive per-component UI tests; snapshot/ViewInspector tooling; moving the 50%
pre-push gate (tracked separately).
