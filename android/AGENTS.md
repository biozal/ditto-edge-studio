# Android agent guide

These rules apply under `android/` and extend the repository root `AGENTS.md`.

## Required workflow

- Load `android-development` with
  `npx openskills read android-development` before Android implementation work.
- Keep documentation in `../docs/android/`, plans in `../plans/android/`, and
  screenshots in `../screens/android/`; do not add Markdown files here.
- Follow `../docs/android/ARCHITECTURE.md` and
  `../docs/android/UI_TERMINOLOGY.md`.
- Run Gradle from this directory.

## Build and test

```bash
./gradlew assembleDebug
./gradlew test
./gradlew check
```

Use focused tests during iteration. Run instrumented tests only on a designated
wipe-safe device because `connectedAndroidTest` reinstalls the app.

## Device safety

- With multiple devices attached, prefix install and device-test commands with
  `ANDROID_SERIAL=<serial>`.
- Never clear package data or uninstall the app on a device containing a real
  Edge Studio configuration.
- Do not use a nonexistent Gradle `deviceSerial` property; it does not safely
  select one device.
- Treat `local.properties` as machine-local and do not commit it.

## Architecture

Use unidirectional state flow, lifecycle-aware collection, immutable UI state,
and constructor-injected dependencies. Keep database and network work outside
composables. Add previews and tests appropriate to UI and state changes.

`CLAUDE.md` in this directory remains a supplementary project reference.
