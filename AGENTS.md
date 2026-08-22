# Edge Studio agent guide

This is the canonical repository guidance for coding agents. `CLAUDE.md` is
retained for Claude Code compatibility and deeper historical Swift guidance;
do not assume that every agent loads it automatically.

## Repository map

- `SwiftUI/`: primary macOS/iPadOS app (Swift and SwiftUI)
- `android/`: Android companion app (Kotlin and Jetpack Compose)
- `dotnet/`: archived Avalonia implementation; reference only, no new features
- `docs/`: approved technical and user documentation
- `plans/`: implementation plans and research awaiting implementation
- `screens/`: screenshots and design references

More specific `AGENTS.md` files under `SwiftUI/` and `android/` add platform
rules. Read the nearest file before changing code in either tree.

## Working agreements

- Preserve unrelated user changes. The worktree is often intentionally dirty.
- Search with `rg`/`rg --files` and prefix shell commands with `rtk`.
- Keep plans in `plans/`; Android plans belong in `plans/android/`.
- Put approved implementation documentation in `docs/`; Android documentation
  belongs in `docs/android/`.
- Resolve named screenshots under `screens/`, or `screens/android/` for Android.
- Never commit credentials, local SDK paths, database exports, or device data.
- Update relevant documentation when behavior, setup, or commands change.

## Reviewing and fixing (MANDATORY — read before acting on any review)

**A reported problem is not actionable until two independent reviewers confirm it.**
**A fix is not complete until a reviewer who did not write it verifies the wiring.**

Full rule, rationale and workflow: [`docs/FIX_VERIFICATION_RULE.md`](docs/FIX_VERIFICATION_RULE.md).

In short:

- One reviewer's finding is a hypothesis. Two independent confirmations make it
  actionable. Your own evidence-based verification counts as one.
- Single-source findings go to a targeted adjudication round (confirm **or refute**)
  before any code changes. Never fix an unconfirmed finding.
- After fixing, grep for the **production call site**. "It compiles and the tests
  pass" is not verification — that was true of three fixes on this repo that were
  either not wired up or actively harmful.
- Test the path the user takes. A test that calls a view-model method the view
  bypasses proves nothing.
- Fix in small batches and verify each. Never batch-fix a long review list in one
  pass.
- Run readiness review as a separate pass from bug-hunting.
- Record confirmation counts, what you chose not to fix, and which claims are
  **unverified**. Shipping something unverified is fine; describing it as verified is
  not.

## Platform selection

Determine the target platform from the requested files or feature. Do not make
parallel changes across SwiftUI and Android unless the user asks for parity.
Do not implement new work in `dotnet/`.

## Verification

Run the narrowest relevant checks first, then the platform-required suite. Do
not claim a check passed unless it was run. If the environment prevents a
check, report the exact command and reason.

For Swift implementation work, read `docs/TESTING.md` before starting. New code
requires tests; use Swift Testing for unit/integration tests and XCTest only for
UI tests.

## MCP integration

Edge Studio exposes the currently selected database through a local MCP server
at `http://localhost:65269/mcp`. Tools can mutate database contents. Confirm the
active database and review write queries before executing them.

## Skills

For Android architecture, Compose screens, ViewModels, repositories, or modules,
check the installed project skills with `npx openskills list` and load relevant
ones (e.g. `navigation-3`, `styles`, `testing-setup`) with
`npx openskills read <skill-name>` before implementation.

## Code review rules

- Flag destructive Android device commands that clear or uninstall app data.
- Flag use of transitive presence peers where direct connections are required;
  follow `docs/PRESENCE_GRAPH.md`.
- Flag new production code without proportionate tests.
- Flag feature work added to the archived `dotnet/` implementation.
