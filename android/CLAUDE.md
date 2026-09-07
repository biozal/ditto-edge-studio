# CLAUDE.md — Android

> Shared Android agent rules live in [`AGENTS.md`](AGENTS.md). This file retains
> supplementary project detail for Claude Code.

This file provides guidance to Claude Code when working with the Android project in this directory.

## Project Overview

Edge Studio for Android is a Jetpack Compose application for querying and managing Ditto databases on Android devices. It is the Android companion to the macOS/iPadOS SwiftUI app in the `SwiftUI/` directory of this repository.

- **Package:** `com.costoda.dittoedgestudio`
- **Module:** `app` (single-module project)
- **Min SDK:** 28 (Android 9 Pie)
- **Target SDK:** 36 / **Compile SDK:** 37
- **Language:** Kotlin 2.3.21 (AGP built-in Kotlin)
- **UI framework:** Jetpack Compose (Material3)

## Repository Conventions

### Documentation
All documentation for the Android project lives in:
```
docs/android/
```
(relative to the repository root — one level up from this directory)

Never create `.md` documentation files inside the `android/` folder itself. Place all guides, architecture docs, and notes in `docs/android/`.

### Plans
All implementation plans for Android features and bug fixes live in:
```
plans/android/
```
(relative to the repository root)

When asked to create a plan, write it as a `.md` file in `plans/android/` named after the feature or fix (e.g., `plans/android/ditto-sdk-integration.md`).

### Screenshots
Screenshots and design mockups are stored in:
```
screens/android/
```
(relative to the repository root)

When the user references a screenshot by filename, always look for it in `screens/android/`. If told "there is a screenshot named X", read `screens/android/X`.

## Build Commands

```bash
# Debug build
./gradlew assembleDebug

# Release build
./gradlew assembleRelease

# Run unit tests
./gradlew test

# Run instrumented tests (requires connected device/emulator)
./gradlew connectedAndroidTest

# Full check (lint + unit tests)
./gradlew check

# Clean
./gradlew clean
```

**Working directory:** Always run Gradle commands from `android/` (this directory), not the repo root.

**Device targeting (CRITICAL):** with multiple devices attached, ALWAYS prefix Gradle install/test commands with `ANDROID_SERIAL=<serial>` — it is the only supported mechanism (`-PdeviceSerial` does not exist and silently targets every device). Never run `adb uninstall` / `pm clear` / `pm uninstall` against a device holding a real configuration — uninstalling destroys app-private data (saved database configs). `connectedAndroidTest` removes and reinstalls the app **by design**; run it only on the designated wipe-safe test device. A PreToolUse hook in `.claude/settings.json` enforces these rules in Claude Code sessions (it also matches these literal patterns in prose typed through Bash — use the Edit tool for documentation).

## Android Studio

- **Run configuration:** `app` (stored in `.idea/runConfigurations/app.xml`)
- **Gradle sync:** Run **File → Sync Project with Gradle Files** after any `build.gradle.kts` or `libs.versions.toml` change
- **SDK location:** `/Users/labeaaa/Library/Android/sdk` (set in `local.properties`, do not commit changes to that file)

## Architecture

Full architecture guide: **[`docs/android/ARCHITECTURE.md`](../docs/android/ARCHITECTURE.md)**

The project follows **Clean Architecture + MVVM** with Room + SQLCipher (AES-256), Koin DI, and Kotlin Coroutines/Flow:

```
UI Layer (Compose)
  └── ViewModels (viewModelScope + StateFlow)
        └── Repository interfaces (domain layer boundary)
              └── Repository Impls (Dispatchers.IO)
                    └── Room DAOs (Flow<List<T>>)
                          └── AppDatabase (Room + SQLCipher)
                                └── DatabaseKeyManager (Android Keystore)
```

### File Structure

```
app/src/main/java/com/costoda/dittoedgestudio/
├── MainApplication.kt               # Koin startKoin{}
├── MainActivity.kt                  # Entry point, sets up Compose content
├── domain/
│   └── model/                       # Pure Kotlin domain models (no Android/Room imports)
├── data/
│   ├── db/
│   │   ├── AppDatabase.kt           # Room + SQLCipher
│   │   ├── DatabaseKeyManager.kt    # Keystore AES-256 key management
│   │   ├── entity/                  # Room entities
│   │   └── dao/                     # Room DAOs (Flow queries)
│   ├── repository/                  # Repository interfaces + implementations
│   ├── session/
│   │   ├── StudioSession.kt         # Koin "studio" scope per databaseId (Ditto lifecycle)
│   │   └── StudioUiState.kt         # Ephemeral cross-section UI state (queryWorkbench, etc.)
│   └── di/
│       └── DataModule.kt            # Koin module
├── ui/
│   ├── adaptive/
│   │   └── WindowSize.kt            # Single source of truth for WindowSizeClass decisions
│   ├── database/                    # DatabaseListScreen, DatabaseEditorScreen, DatabaseCard
│   ├── mainstudio/
│   │   ├── StudioScaffold.kt        # Chrome: Rail (≥600dp) / Nav Drawer + top bar + inspector
│   │   ├── *Section.kt              # Scene-driven section entry-points (one per rail item)
│   │   ├── *ListPane.kt             # List-pane composables (SubscriptionsListPane, etc.)
│   │   ├── *Screen.kt               # Leaf screens (ConnectedPeersScreen, LoggingScreen, etc.)
│   │   ├── inspector/               # Inspector composables (QueryInspectorView, HelpContentView)
│   │   └── metrics/                 # AppMetricsScreen, DiskUsageScreen, QueryMetrics*Pane
│   ├── navigation/
│   │   ├── AppNavGraph.kt           # NavDisplay + ListDetailSceneStrategy + entryProvider
│   │   ├── NavKeys.kt               # All NavKey types (DatabaseListKey, StudioSectionKey, etc.)
│   │   └── StudioScopeManager.kt    # Koin studio-scope lifecycle manager
│   ├── qrcode/                      # QR scanner + display
│   └── theme/
│       ├── Color.kt                 # Brand color definitions (RAL palette)
│       ├── Theme.kt                 # Light/Dark MaterialTheme setup
│       └── Type.kt                  # Typography
└── viewmodel/
    ├── MainStudioViewModel.kt       # Shared studio VM; owns StudioNavItem enum
    ├── AppMetricsViewModel.kt
    ├── DiskUsageViewModel.kt
    └── QueryEditorViewModel.kt
```

### Layer Responsibilities

| Layer | Files | Responsibility |
|-------|-------|---------------|
| **UI** | `ui/**/*.kt` | Composables, previews, no business logic |
| **ViewModel** | `viewmodel/*.kt` | UI state (`StateFlow`/`Flow`), user event handlers |
| **Repository** | `data/repository/*.kt` | Data access abstraction (interfaces + impls) |
| **Database** | `data/db/**` | Room entities, DAOs, AppDatabase, key management |
| **Domain** | `domain/model/*.kt` | Pure Kotlin models, no Android/Room imports |

**Rules:**
- Composables must not hold business logic — delegate to ViewModel
- ViewModels must not reference Android `Context` directly — use `Application`-scoped helpers if needed
- Repository interfaces define the contract; implementations live alongside them
- Use `StateFlow` for UI state, `Flow` for streams
- All DAO calls wrapped in `withContext(Dispatchers.IO)` in repository impls

## UI Layout Terminology

The studio is implemented in `ui/mainstudio/StudioScaffold.kt` (chrome) hosting a Navigation 3 `NavDisplay` in `ui/navigation/AppNavGraph.kt` with Material 3 Adaptive `ListDetailSceneStrategy` scenes. These are the **canonical terms** for each region — when a task references one of these terms, it means exactly this region:

| Term | Code | Description | iOS (SwiftUI app) equivalent |
|------|------|-------------|------------------------------|
| **Rail** | `NavigationRail` in `StudioScaffold` | Vertical strip of navigation icons (`StudioNavItem` entries); visible as a column at ≥840dp; folded into the Nav Drawer below 840dp; selection = the current `StudioSectionKey` on the Nav3 back stack (replace-top on switch; back exits the studio) | Sidebar segmented picker |
| **Data Panel** | `ListDetailSceneStrategy.listPane` (scene-managed width; preferred 320dp at ≥1200dp) | Feature/info menu for the selected Rail item; visible side-by-side at ≥840dp; below 840dp lives inside the Nav Drawer alongside the rail items | Sidebar content list |
| **Content Pane** | `ListDetailSceneStrategy.detailPane` (or `detailPlaceholder`) | Main working area (query editor, results, observers, etc.). **Default view at every width** (full-width below 840dp) | MainView / detail area |
| **Inspector** | Inspector column in `StudioScaffold`; width: 300dp (<1200dp), 360dp (≥1200dp), 400dp (≥1600dp); default-visible at ≥1200dp (Large+); `ModalBottomSheet` below 840dp | Trailing slide-out panel; toggleable | Inspector |
| **Nav Drawer** | `ModalNavigationDrawer` in `StudioScaffold` | Below 840dp: holds Rail items + the section's Data Panel (rail items at top, divider, Data Panel below); selecting any item closes the drawer | — |

Material/Android mapping for reference: Rail = Navigation Rail, Data Panel = list pane (of a list-detail layout), Content Pane = detail pane, Inspector = side sheet / supporting pane.

Adaptivity source of truth: `ui/adaptive/WindowSize.kt` (uses `currentWindowAdaptiveInfoV2`, Large/XL enabled). The Gradle `check` task `forbidNonAdaptiveSizeApis` forbids `screenWidthDp` outside `ui/adaptive/`.

## Dependency Catalog

All versions and dependencies are declared in `gradle/libs.versions.toml`. Never hardcode version strings in `build.gradle.kts` files — always add entries to the TOML catalog first.

**Current key versions:**

| Dependency | Version |
|-----------|---------|
| Android Gradle Plugin | 9.2.1 (built-in Kotlin — no kotlin-android plugin) |
| Kotlin | 2.3.21 |
| KSP | 2.3.9 |
| Compose BOM | 2026.05.01 |
| Core KTX | 1.16.0 |
| Activity Compose | 1.10.1 |
| Lifecycle / ViewModel | 2.9.0 |
| Material Icons Core | BOM-managed |
| Material Icons Extended | BOM-managed |
| SQLCipher for Android | 4.13.0 |
| androidx.sqlite | 2.2.0 |
| Room (runtime, ktx, compiler, testing) | 2.7.0 |
| Koin BOM | 4.1.1 |
| koin-core, koin-android, koin-androidx-compose | BOM-managed |
| kotlinx-coroutines-android | 1.10.2 |
| kotlinx-coroutines-test | 1.10.2 |
| MockK | 1.13.14 |

### Using Material Icons

Both `material-icons-core` (baseline set) and `material-icons-extended` (full 2000+ icon set) are included and versioned via the Compose BOM.

```kotlin
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton

IconButton(onClick = { /* ... */ }) {
    Icon(
        imageVector = Icons.Filled.Add,
        contentDescription = "Add"
    )
}
```

**Icon style packages:**
- `Icons.Filled.*` — solid filled (default)
- `Icons.Outlined.*` — outlined stroke
- `Icons.Rounded.*` — rounded corners
- `Icons.Sharp.*` — sharp corners
- `Icons.TwoTone.*` — two-tone

Browse all available icons at [fonts.google.com/icons](https://fonts.google.com/icons).

## Theme & Brand Colors

The app uses a custom RAL color palette defined in `ui/theme/Color.kt`:

| Name | Hex | RAL | Usage |
|------|-----|-----|-------|
| `JetBlack` | `#0A0A0A` | 9005 | Dark background |
| `TrafficBlack` | `#2A292A` | 9017 | Dark card/surface |
| `PearlLightGrey` | `#9D9D9F` | 9022 | Dividers, secondary text |
| `PapyrusWhite` | `#D0CFC8` | 9018 | Light background |
| `TrafficWhite` | `#F1F0EA` | 9016 | Light card/surface |
| `SulfurYellow` | `#F0D830` | 1016 | Primary accent |

Always use these named tokens — never hardcode hex values in UI code.

## Drag-to-reorder (Pinned metrics)

Before touching drag-to-reorder in the Pinned accordion on the System Metrics
screen, read [`../docs/PINNED_REORDER.md`](../docs/PINNED_REORDER.md) in full.
The algorithm is shared with SwiftUI, function for function
(`SystemMetricsPinOrdering.dropIndex` / `.gapOffset`), and the two must stay in
step.

Key rule: **never reorder the list while a drag is in flight.** It moves the
dragged row's composable to a new slot and tears down the `pointerInput` that
owns the gesture — the defect fixed in `0bda9c3`. The list stays still; only the
offsets change, and the order is committed once on release.

## Testing

- **Unit tests:** `app/src/test/` — JUnit4, run with `./gradlew test`
- **Instrumented tests:** `app/src/androidTest/` — Espresso + Compose Test, run with `./gradlew connectedAndroidTest`
- Test files mirror the main source package structure
- All new code requires corresponding unit tests

## Code Style

- Follow [Android Kotlin style guide](https://developer.android.com/kotlin/style-guide)
- 4-space indentation
- `@Composable` functions: PascalCase, no verb prefix (e.g., `HomeScreen`, not `ShowHomeScreen`)
- Private preview composables: suffix with `Preview` and annotate with `@Preview`
- ViewModels: suffix with `ViewModel`
- Repository interfaces: suffix with `Repository`; implementations suffix with `RepositoryImpl`
- Do not use `print()` or `println()` — use `android.util.Log` or a proper logging abstraction

## AndroidManifest Notes

- Single activity: `MainActivity` (launcher)
- `windowSoftInputMode="adjustResize"` — keyboard pushes content up
- `resizeableActivity="true"` — required for Android 16 desktop windowing / connected displays
- `configChanges="orientation|screenSize|smallestScreenSize|screenLayout|density"` — activity handles rotation and window-resize/density changes (monitor plug/unplug) without recreation

## QR Code Import & Export

The app supports cross-platform QR code sharing of database configs, compatible with the iOS/macOS Edge Studio app.

### Wire Format

| Version | Format |
|---------|--------|
| v2 (current) | `EDS2:` + Base64(zlib-compress(JSON)) |
| v1 (legacy, parse-only) | raw JSON of database config (no prefix) |

- **zlib:** `Deflater(DEFAULT_COMPRESSION, nowrap=false)` / `Inflater(nowrap=false)` — RFC 1950 standard format, matches Apple's `.zlib` compression
- **Max payload:** 2200 characters. Favorites are dropped if payload would exceed this limit with them included.
- **`_id` field on import:** Ignored — Room generates a new auto-increment `Long` id for each imported config
- **Duplicate handling:** `OnConflictStrategy.REPLACE` in the DAO; scanning the same QR twice upserts silently

### Key Files

| File | Purpose |
|------|---------|
| `domain/model/QrCodePayload.kt` | `@Serializable` data classes matching EDS2 JSON format |
| `util/QrCodeDecoder.kt` | Decodes EDS2/v1 QR string → `QrImportResult` |
| `util/QrCodeEncoder.kt` | Encodes `DittoDatabase` + favorites → EDS2 QR `Bitmap` |
| `util/QrImportResult.kt` | Result type: `database + favorites` |
| `ui/qrcode/QrScannerScreen.kt` | Full-screen CameraX + ML Kit live scanner |
| `ui/qrcode/QrScannerViewModel.kt` | State: Idle → Scanning → Processing → Success/Error |
| `ui/qrcode/QrDisplayDialog.kt` | `ModalBottomSheet` showing the generated QR image |
| `ui/qrcode/QrDisplayViewModel.kt` | Fetches favorites + generates QR bitmap asynchronously |

### Libraries

- **CameraX** (`androidx.camera:*` 1.4.2) — lifecycle-aware camera preview
- **ML Kit Barcode** (`com.google.mlkit:barcode-scanning` 17.3.0) — QR code detection
- **ZXing Core** (`com.google.zxing:core` 3.5.3) — QR code generation (no camera dependency)
- **kotlinx.serialization** (`org.jetbrains.kotlinx:kotlinx-serialization-json` 1.8.0) — JSON encoding/decoding

### Permissions

`CAMERA` permission is required for the scanner screen. The permission is requested at runtime via `ActivityResultContracts.RequestPermission()` when the scanner screen is opened. `uses-feature android.hardware.camera` is declared as `required="false"` so the app can install on devices without a camera (scanner screen handles the absent permission gracefully).

### Navigation

`Screen.QrScanner` is a top-level route in `AppNavGraph`. The `DatabaseListScreen`:
- **Phone:** Top-bar `QrCodeScanner` icon button → navigates to `QrScanner` screen
- **Tablet:** "Import QR Code" `OutlinedButton` in left panel → navigates to `QrScanner` screen

The **QR display** (export) is triggered from the `DatabaseCard` context menu → "QR Code" → shows `QrDisplayDialog` (a `ModalBottomSheet`) from within `DatabaseListScreen` state, without navigation.

## Gradle Properties

Set in `gradle.properties`:
- `org.gradle.jvmargs=-Xmx2048m` — increase if large builds OOM
- `android.suppressUnsupportedCompileSdk=37` — suppress SDK 37 warnings until AGP officially supports it
- `kotlin.code.style=official`
