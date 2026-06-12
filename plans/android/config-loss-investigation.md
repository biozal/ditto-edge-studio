# Configuration Data Loss — Investigation & Remediation Plan

**Date:** 2026-06-12 · **Status:** Investigation complete, remediation pending approval
**Symptom:** The Samsung tablet (R5GL15XPVGA) lost all saved database configurations twice
(2026-06-11 and 2026-06-12) during development/testing sessions.

---

## 1. Evidence gathered

| Evidence | Finding |
|---|---|
| `dumpsys package com.costoda.dittoedgestudio` on the Samsung | `firstInstallTime=2026-06-12 13:32:13` — equal to `lastUpdateTime`, i.e. the package was **fully uninstalled and reinstalled** minutes before the loss was noticed. App-private data (Room DB, Ditto store) is destroyed by uninstall. |
| Agent transcript (loss #2, 2026-06-12) | Exact command sequence recovered: ① `./gradlew :app:installDebug -PdeviceSerial=R5GL15XPVGA` → `-PdeviceSerial` is **not an AGP property**; Gradle attempted install on ALL five connected devices and failed on one → ② `pm uninstall --keep-data` (leaves package in a half-removed state where reinstall fails) → ③ `adb uninstall com.costoda.dittoedgestudio` (full uninstall, data destroyed) → ④ fresh install. |
| Gradle/AGP behavior (loss #1, 2026-06-11) | `connectedDebugAndroidTest` **uninstalls the app and test APKs after the run by design**. The suite was executed on the Samsung that day. |

**Conclusion for the two incidents:** both were tooling-driven uninstalls, not the app
deleting its own data.

## 2. BUT — the audit found two real end-user data-loss paths in the app

These are exactly the class of bug the incidents made us look for:

### 2a. `AppDatabase.kt:83` — `.fallbackToDestructiveMigration(dropAllTables = true)`  ⚠️ CRITICAL

Any future Room schema change shipped without a hand-written `Migration` silently
**drops every table** (configs, subscriptions, observers, favorites, history) on app
update. The failure is invisible in development (fresh installs never migrate) and
catastrophic in production. This is a standing landmine, independent of testing.

### 2b. `AndroidManifest.xml:40` — `android:allowBackup="true"` + SQLCipher key in Android Keystore  ⚠️ HIGH

Auto Backup copies the **encrypted** Room DB to the user's Google backup, but Android
Keystore keys never leave the device. On restore (new device, factory reset,
reinstall-with-restore) the DB file comes back **without its key** → SQLCipher cannot
open it. `DatabaseKeyManager` has no recovery path for this (no key-failure handling
found) — the app will crash on launch or, if a destructive fallback is ever added,
silently wipe. Either way the user's restored configs are unusable.

## 3. Remediation plan

### A. Stop the bleeding — tooling/process guards (no app changes)

- [ ] **A1. PreToolUse hook** in `.claude/settings.json` that hard-blocks Bash commands
      matching `adb .*(uninstall|pm uninstall|pm clear)` and `gradlew .*uninstall`.
      Hooks bind all agents mechanically — prompt-level instructions have failed twice.
      *(Requires user approval — settings change.)*
- [ ] **A2. Device targeting rule:** never run bare `./gradlew installDebug` with
      multiple devices attached — `ANDROID_SERIAL=<serial>` is the only supported
      mechanism (`-PdeviceSerial` does not exist). Already captured in auto-memory;
      add to `android/CLAUDE.md` Build Commands section.
- [ ] **A3. Instrumented tests only on the designated wipe-safe device** (Pixel 10a
      58300DLCR0000L) — `connectedAndroidTest` uninstalls by design. Already in memory;
      add to `android/CLAUDE.md` Testing section.

### B. Protect end users — app hardening

- [ ] **B1. Remove `fallbackToDestructiveMigration`.** Enable Room schema export
      (`room.schemaLocation` KSP arg, commit `schemas/`), write explicit `Migration`s
      going forward, and replace the fallback with a fail-loud open error so a missing
      migration can never silently destroy data. Add `MigrationTest` using
      `MigrationTestHelper` + the exported schemas to CI.
- [ ] **B2. Backup correctness.** Either exclude the SQLCipher DB + key-dependent files
      from Auto Backup (`android:fullBackupContent` / `dataExtractionRules` for API 31+)
      so restores start clean instead of restoring an unopenable DB, **or** (larger)
      re-key the DB with a restorable secret. Recommended: exclusion rules now,
      restorable-key design later if cross-device restore becomes a product goal.
- [ ] **B3. Key-failure UX.** `DatabaseKeyManager` currently has no handling for an
      invalidated/missing Keystore key (possible after OS security events). Decide and
      implement: detect SQLCipher open failure → surface a clear "stored configurations
      could not be decrypted" screen with a reset option — never crash-loop, never
      silent-wipe.
- [ ] **B4. Safety net (optional, product call):** one-tap "Export all configs"
      (QR/file) and/or periodic auto-export to app-external storage, so even a
      worst-case wipe is recoverable. The QR export path already exists per-config.

### C. Verification

- [ ] C1. Migration test: open a v(N-1)-schema DB fixture with the new version — data
      survives; missing-migration scenario fails the build, not the user.
- [ ] C2. Backup-restore simulation: `adb backup`/`bmgr` (or exclusion-rule assertion
      test) demonstrating the DB is excluded / restore-safe.
- [ ] C3. Re-run the full instrumented suite on the wipe-safe device only.

## 4. Priority order

1. A1 hook (minutes, removes the recurring dev-loss vector)
2. B1 destructive-migration removal (the production landmine)
3. B2 backup exclusion rules
4. B3 key-failure UX · A2/A3 doc updates · B4/C as follow-ups
