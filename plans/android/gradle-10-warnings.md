# Android — Gradle 10 Deprecation Warnings

**Status:** Implemented 2026-03-08 — all fixable warnings resolved
**Filed:** 2026-03-08

---

## Executive Summary

The AGP upgrade from 8.9.0 → 8.12.0 surfaced three previously hidden Kotlin compiler warnings that have now been fixed. Two AGP-internal Gradle 10 warnings remain — they exist in AGP's own JAR (`AndroidLintInputs.kt` and `Aapt2FromMaven.kt`) and cannot be addressed from the project side. They will resolve when Google publishes an AGP version with the fix.

---

## Warning Inventory

Running `./gradlew assembleDebug --warning-mode all --stacktrace` reveals exactly 2 unique warnings. Both appear during the `> Configure project :app` phase on every build (main and test).

### Warning 1 — Lint dependency declared with map notation

```
Declaring dependencies using multi-string notation has been deprecated.
This will fail with an error in Gradle 10.
Please use single-string notation instead: "com.android.tools.lint:lint-gradle:31.9.0".
```

**Stack trace origin:**

```
com.android.build.gradle.internal.lint.LintFromMaven$Companion.from(AndroidLintInputs.kt:2850)
  ← AndroidPluginBaseServices.basePluginApply
```

**Root cause:** AGP 8.9.0's `LintFromMaven` class declares the `lint-gradle` classpath dependency using Gradle's deprecated map notation (`group: "...", name: "...", version: "..."`). This is entirely inside the AGP library JAR — the project has no involvement.

---

### Warning 2 — AAPT2 dependency declared with map notation

```
Declaring dependencies using multi-string notation has been deprecated.
This will fail with an error in Gradle 10.
Please use single-string notation instead: "com.android.tools.build:aapt2:8.9.0-12782657:osx".
```

**Stack trace origin:**

```
com.android.build.gradle.internal.res.Aapt2FromMaven$Companion.create(Aapt2FromMaven.kt:136)
  ← AndroidPluginBaseServices.basePluginApply
```

**Root cause:** AGP 8.9.0's `Aapt2FromMaven` class declares the `aapt2` binary dependency the same way. Again, entirely internal to AGP.

---

## Why the Project Cannot Suppress These

The warnings originate inside `com.android.build.gradle.internal.*` — compiled AGP classes. There is no Gradle configuration or workaround available to the consuming project that would silence them without upgrading.

---

## Current Versions

| Component | Current | Target |
|-----------|---------|--------|
| AGP | `8.9.0` | `8.12.0` |
| Kotlin | `2.1.20` | no change |
| KSP | `2.1.20-1.0.32` | verify compatibility |
| Gradle wrapper | `9.3.1` | no change (compatible) |

**AGP 8.12.0** is already present in the local Gradle cache (`~/.gradle/caches`), so no download is required on the next build.

---

## What Was Fixed (Implemented 2026-03-08)

### AGP bump — `gradle/libs.versions.toml`
```toml
agp = "8.9.0"  →  agp = "8.12.0"
```

The upgrade surfaced three Kotlin compiler warnings that had been hidden under 8.9.0:

### `kotlinOptions` → `compilerOptions` — `app/build.gradle.kts`
`kotlinOptions { jvmTarget = "17" }` is deprecated in KGP 2.x. Migrated to:
```kotlin
import org.jetbrains.kotlin.gradle.dsl.JvmTarget
// ...
compilerOptions {
    jvmTarget = JvmTarget.JVM_17
}
```

### `calculateSignalLevel` — `NetworkDiagnosticsRepositoryImpl.kt:157`
`WifiManager.calculateSignalLevel(int, int)` deprecated at API 30. Version-branched to the new single-argument form on R+ with a suppress for the legacy path:
```kotlin
val signalLevel = rssi?.let {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
        wifiManager.calculateSignalLevel(it)
    } else {
        @Suppress("DEPRECATION")
        WifiManager.calculateSignalLevel(it, 5)
    }
}
```

### `allNetworks` — `NetworkDiagnosticsRepositoryImpl.kt:125,140,210`
`ConnectivityManager.allNetworks` deprecated at API 31. The proper replacement (`registerNetworkCallback`) is async and inappropriate for synchronous point-in-time diagnostics. Suppressed with `@Suppress("DEPRECATION")` at each call site.

---

## Remaining Warnings (Cannot Fix From Project)

Two warnings persist after all project-level fixes. Both appear during `> Configure project :app` and are sometimes displayed with an `AndroidManifest.xml Warning:` prefix in build output — despite having nothing to do with the manifest. The stacktrace confirms they originate inside the AGP JAR:

| Warning | AGP source file |
|---------|----------------|
| `com.android.tools.lint:lint-gradle:31.12.0` declared with map notation | `LintFromMaven.kt:2850` |
| `com.android.tools.build:aapt2:8.12.0-…:osx` declared with map notation | `Aapt2FromMaven.kt:136` |

These are unfixed internal bugs present in AGP 8.9.0 through 8.12.0. No project-side change can silence them. Monitor AGP release notes for a fix; bump `agp` in `libs.versions.toml` when available.

---

## Risk Assessment

| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| AGP 8.12.0 compilation error | Low — only a patch bump from 8.9.0 | Run `assembleDebug` first; check AGP release notes |
| KSP incompatibility | Very low — 2.1.20-1.0.32 tested on AGP 8.x | KSP error messages are explicit; bump KSP patch if needed |
| Room code-gen regression | Very low | All Room unit/instrumented tests run as part of verification |
| Gradle wrapper needs update | None — 9.3.1 is compatible with AGP 8.12.0 | No wrapper change required |

---

## References

- [Gradle 9 Upgrade Guide — multi-string notation](https://docs.gradle.org/9.3.1/userguide/upgrading_version_9.html#dependency_multi_string_notation)
- [AGP 8.12.0 release notes](https://developer.android.com/build/releases/gradle-plugin#8-12-0)
- [KSP releases](https://github.com/google/ksp/releases)
