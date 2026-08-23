# SwiftUI agent guide

These rules apply under `SwiftUI/` and extend the repository root `AGENTS.md`.

## Project

- Open `Edge Debug Helper.xcodeproj`; use the `Edge Studio` scheme.
- Target macOS ARM64 for routine builds to avoid ambiguous destinations.
- The app uses Swift 6 concurrency and Ditto SDK 5 APIs.
- Preserve actor isolation and keep UI state changes on the appropriate main
  actor. Do not add detached tasks as a default concurrency workaround.

## Source and project files

Prefer Xcode-aware tools for creating, moving, or renaming compiled sources and
resources when they are available. Existing source files may be read and edited
with normal workspace tools. After structural changes, verify target membership
and that the project still opens and builds.

## Required context

- Read `../docs/TESTING.md` before implementation work.
- Read `../docs/PRESENCE_GRAPH.md` before changing presence or peer logic.
- Use `../docs/BRAND_COLORS.md` for UI colors.
- Treat `CLAUDE.md` in this directory as supplementary architecture and
  troubleshooting reference, not as agent-specific authority.

## Verification

From this directory:

```bash
xcodebuild -project "Edge Debug Helper.xcodeproj" -scheme "Edge Studio" \
  -configuration Debug -destination "platform=macOS,arch=arm64" build
xcodebuild -project "Edge Debug Helper.xcodeproj" -scheme "Edge Studio" \
  -destination "platform=macOS,arch=arm64" test
```

Run focused tests while iterating and the relevant broader suite before handoff.
