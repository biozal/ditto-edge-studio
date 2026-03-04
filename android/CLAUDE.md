# CLAUDE.md — Android

This file provides guidance to Claude Code when working with the Android project in this directory.

## Project Overview

Edge Studio for Android is a Jetpack Compose application for querying and managing Ditto databases on Android devices. It is the Android companion to the macOS/iPadOS SwiftUI app in the `SwiftUI/` directory of this repository.

- **Package:** `com.costoda.dittoedgestudio`
- **Module:** `app` (single-module project)
- **Min SDK:** 28 (Android 9 Pie)
- **Target/Compile SDK:** 36
- **Language:** Kotlin 2.1.20
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
│   └── model/
│       ├── AuthMode.kt              # enum: SERVER, SMALL_PEERS_ONLY
│       ├── DittoDatabase.kt         # Database configuration model
│       ├── DittoSubscription.kt
│       ├── DittoObservable.kt
│       └── DittoQueryHistory.kt
├── data/
│   ├── db/
│   │   ├── AppDatabase.kt           # Room + SQLCipher
│   │   ├── DatabaseKeyManager.kt    # Keystore AES-256 key management
│   │   ├── entity/                  # Room entities (5 tables)
│   │   └── dao/                     # Room DAOs (5 DAOs, each with Flow queries)
│   ├── repository/                  # 5 interfaces + 5 implementations
│   └── di/
│       └── DataModule.kt            # Koin module
├── ui/
│   ├── home/
│   │   └── HomeScreen.kt            # Home screen Composable
│   └── theme/
│       ├── Color.kt                 # Brand color definitions (RAL palette)
│       ├── Theme.kt                 # Light/Dark MaterialTheme setup
│       └── Type.kt                  # Typography
└── viewmodel/
    └── HomeViewModel.kt             # Home screen ViewModel
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

## Dependency Catalog

All versions and dependencies are declared in `gradle/libs.versions.toml`. Never hardcode version strings in `build.gradle.kts` files — always add entries to the TOML catalog first.

**Current key versions:**

| Dependency | Version |
|-----------|---------|
| Android Gradle Plugin | 8.9.0 |
| Kotlin | 2.1.20 |
| KSP | 2.1.20-1.0.32 |
| Compose BOM | 2025.12.00 |
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
- `configChanges="orientation|screenSize"` — activity handles rotation without recreation

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
- `android.suppressUnsupportedCompileSdk=36` — suppress SDK 36 preview warnings
- `kotlin.code.style=official`
