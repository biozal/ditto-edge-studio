# Phase 5 Complete — Handoff for Phase 6

**Created**: 2026-05-08
**Branch**: `release-1.0b5`
**Last Phase 5 commit**: `perf: stable cell identity, .task-driven attachment detection, debounced log filter`

## Read first
- The execution plan: `plans/2026-05-07-pre-v1-shipping-fixes.md`
- Previous handoff: `plans/handoffs/phase-4-complete.md`
- This file is the entry point if Phase 6 starts in a fresh `/clear`'d session

## Project facts that don't change
- This is the SwiftUI Edge Studio at `/Users/labeaaa/Developer/ditto-edge-studio/SwiftUI/`
- Xcode workspace tab identifier for MCP: `windowtab1` (verify with `XcodeListWindows` if a fresh session)
- Apple Xcode MCP server **is registered for this project** — tools are namespaced `mcp__xcode__*`
- Xcode MCP project tree paths use `Edge Debug Helper/EdgeStudio/...` but **on-disk paths are `SwiftUI/EdgeStudio/...`** — `swiftlint` / `swiftformat` need the on-disk form, but `XcodeRead` / `XcodeUpdate` need the MCP form
- Test baseline is **396 tests** (254 unit + 142 integration) on macOS — Phase 5 added zero new tests (perf changes; manual scroll/typing test gates per plan). Result bundle from Phase 5: 395 passed, 1 skipped, 0 failed = baseline. **Run with a clean DerivedData** (`rm -rf ~/Library/Developer/Xcode/DerivedData/Edge_Debug_Helper-*` then `xcodebuild -resolvePackageDependencies`) when test runs intermittently fail with `Command CodeSign failed` on the EdgeStudioUITests bundle.
- Build commands: see top of `plans/2026-05-07-pre-v1-shipping-fixes.md`. Both macOS AND iPadOS must build green per CLAUDE.md.
- Use `mcp__xcode__BuildProject` for the active Xcode destination (typically macOS); use `xcodebuild` from Bash for the other platform. **Don't run both simultaneously** — they share `Edge_Debug_Helper-*` DerivedData and the BuildProject side will fail with `database is locked`. Wait for one to finish before starting the other.
- **Beware `XcodeUpdate` recursive `replaceAll` bug**: if `newString` contains `oldString` as a literal substring, replaceAll runs 1000 times. Either use a marker pattern OR include surrounding whitespace/context in `oldString`.

## What Phase 5 changed

### `perf: stable cell identity, .task-driven attachment detection, debounced log filter`

#### `EdgeStudio/Components/ResultJsonViewer.swift`
- **C9** — `ForEach(items.indices, id: \.self)` → `ForEach(Array(items.enumerated()), id: \.offset)`. `items: [String]` is not `Identifiable` so `\.offset` is the right canned form.
- **HIGH-Perf — detectTokens off the render path**:
  - `ResultItem` got `@State private var attachments: [AttachmentInfo] = []`
  - New `.task(id: jsonString) { let detected = await Task.detached(priority: .utility) { AttachmentInfo.detectTokens(in: jsonString) }.value; guard !Task.isCancelled else { return }; attachments = detected }` — runs JSON parse on a utility-QoS detached task so big docs don't block MainActor
  - `contextMenu` `.disabled(attachments.isEmpty)` (was `.disabled(AttachmentInfo.detectTokens(in: jsonString).isEmpty)`)
- **GCD → structured concurrency**: `DispatchQueue.main.asyncAfter(deadline: .now() + 1.5)` replaced with tracked `@State private var resetTask: Task<Void, Never>?`; `copyToClipboard()` now does `resetTask?.cancel(); resetTask = Task { @MainActor in try? await Task.sleep(for: .milliseconds(1500)); guard !Task.isCancelled else { return }; withAnimation { isCopied = false } }`. `.onDisappear` cancels and nils. Prior pending reset is cancelled on a fresh tap so the green check-mark always shows for the full 1.5s.

#### `EdgeStudio/Components/ResultTableViewer.swift`
- **CRITICAL-Layout** — Outer `GeometryReader` removed on macOS branch; `.frame(minWidth: geometry.size.width)` per row → `.frame(maxWidth: .infinity)`; `.frame(minHeight: geometry.size.height, alignment: .top)` on the LazyVStack dropped (LazyVStack sizes to content, headers pin via `pinnedViews:` regardless). The iOS branch had no GeometryReader to drop.
- **HIGH-Perf** — Both context menus (macOS + iOS) replaced `let attachments = AttachmentInfo.detectTokens(in: row.originalJson)` + `.disabled(attachments.isEmpty)` with `.disabled(!row.hasAttachments)` — no per-render JSON parse.
- **GCD-style upgrade (consistency with JSON viewer)**: `Task { try? await Task.sleep(nanoseconds: 1_500_000_000); await MainActor.run { ... } }` → tracked `@State private var copyResetTask: Task<Void, Never>?` with cancel-prior-on-new pattern, same as `ResultJsonViewer.ResultItem`.

#### `EdgeStudio/Models/TableResultRow.swift`
- Added `let hasAttachments: Bool`. **Pre-computed at parse time** so contextMenu builders never re-parse JSON during scrolling.

#### `EdgeStudio/Data/TableResultsParser.swift`
- `parseJsonResults` populates `hasAttachments = !AttachmentInfo.detectTokens(in: jsonString).isEmpty` once per row during the actor-isolated parse pass (already off-main).
- `parseMutationResults` always sets `hasAttachments: false` (mutation responses contain `"Document ID:"` / `"Commit ID:"` strings — no JSON to scan).

#### `EdgeStudio/Views/Logging/LoggingDetailView.swift`
- **CRITICAL-Perf** — `filteredEntries` is no longer a computed `var`. New `@State private var cachedFilteredEntries: [LogEntry] = []` and `private func computeFilteredEntries() -> [LogEntry]` (the old logic, lifted verbatim).
- New `private struct FilterInputs: Equatable` aggregates: `selectedSource`, `entryCount`, `levels`, `component`, `searchText`, `dateEnabled`, `dateStart`, `dateEnd`. New `private var currentFilterInputs: FilterInputs` builds it cheaply.
- New `.task(id: currentFilterInputs) { try? await Task.sleep(for: .milliseconds(150)); guard !Task.isCancelled else { return }; cachedFilteredEntries = computeFilteredEntries() }` modifier on the body — SwiftUI's `.task(id:)` cancels the prior task on input change and starts a new one. Net effect: typing in search debounces filtering at 150ms.
- New `private var activeSourceEntryCount: Int` avoids the `historicalEntries + liveEntries` array concat that `activeSourceEntries.count` was forcing on every body invocation. Used in the footer total label and in `FilterInputs.entryCount`.
- The view's existing `.task { ... }` lifecycle block (load active config log level, start live capture) is unchanged. Two `.task` modifiers coexist; SwiftUI manages each independently.
- All callers in body of the old `filteredEntries` (count in footer, list display, `ForEach`) replaced with `cachedFilteredEntries`. The footer's `total` switched from `activeSourceEntries.count` to `activeSourceEntryCount`.

### Verification (Phase 5)
- ✅ macOS build SUCCEEDED (Xcode MCP `BuildProject`)
- ✅ iPadOS build SUCCEEDED (`xcodebuild` for iPad Pro 13-inch (M5))
- ✅ Zero compile warnings (`XcodeListNavigatorIssues` returns empty)
- ✅ 395 passed, 1 skipped, 0 failed on clean DerivedData (matches baseline; no new tests added)
- ✅ SwiftFormat clean on changed files (cached, no changes)
- ✅ SwiftLint clean on changed files (zero output)
- ✅ Aaron's manual smoke test (200+ doc query scroll, Logging search typing, copy-feedback) approved

## What's left in the plan

Read `plans/2026-05-07-pre-v1-shipping-fixes.md` for full detail. Remaining phases:
- **Phase 6** — HIGH concurrency cleanups (untracked Tasks in `MainStudioView.ViewModel.init`, parallelize loads with `async let`, `DittoLogCaptureService` cancel checks, replace `DittoManager.getCachedUntrustedSession` static+NSLock with instance state).
- Phases 7-11 cover remaining HIGH/MEDIUM/LOW items.

## How to start Phase 6 in a fresh session

After `/clear`:
1. Tell Claude: "Continue v1 shipping work. Read `plans/handoffs/phase-5-complete.md` then start Phase 6 per `plans/2026-05-07-pre-v1-shipping-fixes.md`."
2. Claude should invoke `axiom-concurrency` (the primary skill — async lifecycle / Task management) and verify the Xcode MCP tab via `XcodeListWindows`.
3. Phase 6 is single-agent work. Manual test gate involves opening a database and immediately closing it before load completes (verifies deinit fires, no zombie observers), repeat 5 times to confirm no memory growth.

## Open notes / risks for next phase

- **`MainStudioView.ViewModel.init` Tasks (Phase 6 main item)**: extract into a single `func load() async` called from the view's `.task` modifier. Currently `init` spawns 5 untracked `Task { ... }` blocks with strong `self` capture. Replacement: store `private var loadTask: Task<Void, Never>?`, cancel in `closeSelectedApp` and `deinit`, use `[weak self]` on captures. Use `async let` to parallelize the independent repository loads (subscriptions / collections / history / favorites / observers).
- **Async cascade**: Phase 2 made `CollectionsRepository.stopObserver()` async. If Phase 6's load orchestration changes when stopObserver is called, ensure all `await` propagation is intact (the `MainStudioView.performCleanupOperations` `TaskGroup` already awaits it).
- **DittoLogCaptureService cancel checks (`:73,...`)**: add `guard !Task.isCancelled else { return }` before flush body. The capture service's flush tasks should bail when the view they were started for has gone away.
- **`DittoManager.getCachedUntrustedSession` (`DittoManager.swift:292-313`)**: replace `static var` + `NSLock` with `private var cachedUntrustedSession: URLSession?` on the actor instance. Drop the NSLock entirely — actor isolation already serializes access. Watch for any extension files that read/write the static.
- The Phase 5 `cachedFilteredEntries` initialization is `[]` and the first compute happens after a 150ms debounce. While `capture.isLoading == true`, the loading view masks the empty cache so users don't see a flash. Phase 6 doesn't touch this, but if Phase 9 (UX) revisits the Logging tab loading states, the 150ms initial-render gap is benign here because the capture loading state covers it — there's no need to add an `.onAppear { cachedFilteredEntries = computeFilteredEntries() }` synchronous prefetch unless something else changes.
- Phase 5's `.task(id:)` debounce relies on `.task(id:)` automatically cancelling the prior task when the id changes. SwiftUI 6.2 honors this. If Phase 6 or later adds a manual `.onChange` that also recomputes filtered entries, prefer modifying the `FilterInputs` struct rather than adding a parallel cancellation pathway.
- The Phase 5 `Task.detached(priority: .utility)` inside `.task(id: jsonString)` for `detectTokens` is fine for SwiftUI cells — `jsonString` is `String` (Sendable). If Phase 10 splits `MainStudioView.ViewModel`, none of the JSON viewer / table viewer code needs to change in lockstep.
