# Plan: Native Platform Settings / Preferences

## Summary

Move the "Collect Metrics" toggle out of the in-app sidebar navigation and into the
native settings location for each Apple platform:

| Platform | Mechanism | User entry point |
|----------|-----------|-----------------|
| **macOS** | SwiftUI `Settings` scene | App menu → "Settings…" (⌘,) — same as Xcode |
| **iOS / iPadOS** | `Settings.bundle` + `Root.plist` | iOS Settings app → Ditto Edge Studio |

Storage switches from the SQLCipher encrypted database (designed for per-database data)
to `UserDefaults.standard` via `@AppStorage` — the Apple-idiomatic, system-wide
preference store for app-level settings.

---

## Research Basis (Apple Documentation)

### macOS — `Settings` Scene
Introduced in macOS 11. When a `Settings { }` scene is declared alongside `WindowGroup`
in the `App` body, SwiftUI automatically:
- Inserts **"Settings…"** into the app menu
- Wires the **⌘,** keyboard shortcut
- Manages the window lifecycle

```swift
@main struct EdgeStudioApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
        #if os(macOS)
        Settings { AppPreferencesView() }
        #endif
    }
}
```

Values are persisted via `@AppStorage` / `UserDefaults.standard`. No SQLite or custom
storage needed.

### iOS / iPadOS — `Settings.bundle`
A special resource bundle. When present in the app target, iOS displays a dedicated
section for the app under **Settings → [App Name]**. The user flips toggles there; the
values land automatically in `UserDefaults.standard` under the keys declared in
`Root.plist`.

Reading in app code is identical to macOS — `@AppStorage("metricsEnabled")` or
`UserDefaults.standard.bool(forKey: "metricsEnabled")`.

**Critical detail:** The default value in `Root.plist` is only used by the Settings UI
for display. Until the user actually opens Settings for your app and changes a value,
`UserDefaults` has no stored entry. Code must call `UserDefaults.standard.register(defaults:)`
at startup to ensure the correct default is returned before the user has ever visited
the Settings page.

### Why Not `Settings.bundle` on macOS?
Apple explicitly excludes `Settings.bundle` from macOS — it is an iOS-only mechanism.
The `Settings` scene is the macOS equivalent.

### Why `@AppStorage` Instead of SQLCipher for This Setting?
- `metricsEnabled` is **not database-specific data** — it is a global app preference,
  the same on all databases.
- SQLCipher is designed for encrypted, per-database content (subscriptions, history,
  observables). Storing a global boolean flag there adds schema complexity for no
  security benefit.
- `UserDefaults.standard` is the Apple-sanctioned store for app preferences on all
  Apple platforms and is what `@AppStorage` and `Settings.bundle` write to.
- No iCloud sync needed: the preference is per-device, which matches typical developer
  tool expectations.

---

## Architecture Decisions

- **Storage**: `UserDefaults.standard`, key `"metricsEnabled"`, default `true`
- **macOS UI**: `Settings { AppPreferencesView() }` scene — single "General" tab
- **iOS/iPadOS UI**: `Settings.bundle/Root.plist` — one group with one toggle
- **No SettingsRepository**: Delete it entirely; `UserDefaults` needs no repository
  abstraction for a single boolean
- **No SQLCipher schema change**: Revert schema back to v2; `appSettings` table removed
- **`AppState.metricsEnabled` removed**: Views that need the value read `@AppStorage`
  directly; `QueryService` reads `UserDefaults` directly
- **Sidebar still dynamic**: `MainStudioView` holds
  `@AppStorage("metricsEnabled") private var metricsEnabled = true`;
  SwiftUI re-renders automatically when the value changes (macOS Settings window changes
  reflect immediately; iOS Settings app changes reflect when the user returns to the app
  via `scenePhase` active transition)

---

## Files to Revert / Delete

### 1. `Data/SQLCipherService.swift` — Revert to schema v2
- `currentSchemaVersion` → `2`
- Remove `appSettings` table from `createSchema()`
- Remove seed `INSERT OR IGNORE` for `metricsEnabled`
- Remove `if oldVersion < 3` block from `migrateSchema()`
- Remove `migrateToVersion3()` private method
- Remove `// MARK: - App Settings Operations` section (both `getAppSetting` and
  `setAppSetting` methods)

### 2. `Data/Repositories/SettingsRepository.swift` — DELETE entirely
No longer needed. `UserDefaults` has no repository pattern.

### 3. `AppState.swift` — Remove `metricsEnabled` and SettingsRepository loading
- Remove `@Published var metricsEnabled: Bool = true`
- Remove `try await SettingsRepository.shared.loadSettings()` call
- Remove `let enabled = await SettingsRepository.shared.isMetricsEnabled` line
- Remove `await MainActor.run { self.metricsEnabled = enabled }` line

### 4. `Views/StudioView/MetricsViews.swift` — Remove Settings routing helpers
- Remove `settingsSidebarView()` function
- Remove `settingsDetailView()` function
- Remove `// MARK: - Settings` comment block

### 5. `Views/Settings/SettingsView.swift` — DELETE
Replaced by `AppPreferencesView.swift` (macOS) and `Settings.bundle` (iOS/iPadOS).

---

## Files to Modify

### 6. `Data/QueryService.swift` — Read from `UserDefaults` directly
Replace `await SettingsRepository.shared.isMetricsEnabled` with a synchronous
`UserDefaults` read (no `await` needed):

```swift
// Record metrics only when collection is enabled
let isMetricsEnabled = UserDefaults.standard.bool(forKey: "metricsEnabled")
if isMetricsEnabled {
    queryCounter.increment()
    queryTimer.recordMilliseconds(elapsedMs)
}

// Capture EXPLAIN + per-query metrics only when collection is enabled
if isMetricsEnabled {
    let resultCount = results.items.count + results.mutatedDocumentIDs().count
    let explainOutput = await runExplain(ditto: ditto, query: query)
    await QueryMetricsRepository.shared.capture(
        dql: query,
        executionTimeMs: elapsedMs,
        resultCount: resultCount,
        explainOutput: explainOutput
    )
}
```

Note: `UserDefaults.bool(forKey:)` returns `false` if the key is absent. Correct
default (`true`) is guaranteed by `registerDefaults()` called at app startup (see §8).

### 7. `Views/MainStudioView.swift` — Drive sidebar from `@AppStorage`, remove Settings item

**Remove from the View struct body:**
- The `.task { viewModel.sidebarMenuItems = … }` block we added
- The `.onChange(of: appState.metricsEnabled)` block we added

**Add to the View struct** (alongside other `@State` / `@AppStorage` properties):
```swift
@AppStorage("metricsEnabled") private var metricsEnabled = true
```

**Keep** `.task` and `.onChange` but use `metricsEnabled` (the local `@AppStorage`
property) as the source:
```swift
.task {
    viewModel.sidebarMenuItems = MainStudioView.ViewModel.buildSidebarItems(
        metricsEnabled: metricsEnabled
    )
}
.onChange(of: metricsEnabled) { _, enabled in
    viewModel.sidebarMenuItems = MainStudioView.ViewModel.buildSidebarItems(
        metricsEnabled: enabled
    )
    if !enabled, viewModel.selectedSidebarMenuItem.name == "Metrics" {
        viewModel.selectedSidebarMenuItem = viewModel.sidebarMenuItems[0]
    }
}
```

**Remove from both switch statements** the `case "Settings":` branches.

**`ViewModel.buildSidebarItems(metricsEnabled:)`** — keep as-is but remove the
`Settings` item (it is now in the native OS location):
```swift
static func buildSidebarItems(metricsEnabled: Bool) -> [MenuItem] {
    var items: [MenuItem] = [
        MenuItem(id: 1, name: "Subscriptions", systemIcon: "arrow.trianglehead.2.clockwise.rotate.90"),
        MenuItem(id: 2, name: "Collections",   systemIcon: "macpro.gen2"),
        MenuItem(id: 3, name: "Observer",      systemIcon: "eye"),
    ]
    if metricsEnabled {
        items.append(MenuItem(id: 4, name: "Metrics", systemIcon: "chart.line.uptrend.xyaxis"))
    }
    return items
}
```

**Update `ViewModel.init()`** to call:
```swift
sidebarMenuItems = Self.buildSidebarItems(
    metricsEnabled: UserDefaults.standard.bool(forKey: "metricsEnabled")
)
```
(The `.task` in the view body will immediately correct this to the registered default
on first render.)

### 8. `Ditto_Edge_StudioApp.swift` — Add Settings scene + register defaults

**In `init()`**, add a call to register the default value before any view renders:
```swift
init() {
    // Register UserDefaults defaults so values are correct before first access
    UserDefaults.standard.register(defaults: ["metricsEnabled": true])

    #if os(macOS)
    FontAwesomeRegistration.registerFonts()
    #endif
}
```

**In `body`**, add the `Settings` scene inside the existing `#if os(macOS)` block:
```swift
#if os(macOS)
Settings {
    AppPreferencesView()
}
// ... existing HelpDocumentationWindow and FontDebugWindow scenes ...
#endif
```

---

## Files to Create

### 9. `Views/Settings/AppPreferencesView.swift` (macOS only)
Single-tab macOS preferences window for now (more tabs can be added later):

```swift
import SwiftUI

/// Content of the macOS Settings window (opened via app menu → Settings… or ⌘,).
struct AppPreferencesView: View {
    var body: some View {
        TabView {
            GeneralPreferencesTab()
                .tabItem { Label("General", systemImage: "gearshape") }
        }
        .frame(width: 460, height: 180)
    }
}

private struct GeneralPreferencesTab: View {
    @AppStorage("metricsEnabled") private var metricsEnabled = true

    var body: some View {
        Form {
            Section {
                Toggle("Collect Metrics", isOn: $metricsEnabled)
                Text("When disabled, no performance data is collected and the Metrics section is hidden from the navigation menu.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Label("Metrics", systemImage: "chart.line.uptrend.xyaxis")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
```

### 10. `Settings.bundle/Root.plist` (iOS / iPadOS only)
Create the `Settings.bundle` resource and add it to the iOS app target.
`Root.plist` content:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>PreferenceSpecifiers</key>
    <array>
        <dict>
            <key>Type</key>
            <string>PSGroupSpecifier</string>
            <key>Title</key>
            <string>Metrics</string>
            <key>FooterText</key>
            <string>When disabled, no performance data is collected and the Metrics section is hidden from the navigation menu.</string>
        </dict>
        <dict>
            <key>Type</key>
            <string>PSToggleSwitchSpecifier</string>
            <key>Title</key>
            <string>Collect Metrics</string>
            <key>Key</key>
            <string>metricsEnabled</string>
            <key>DefaultValue</key>
            <true/>
        </dict>
    </array>
    <key>StringsTable</key>
    <string>Root</string>
</dict>
</plist>
```

**Important:** The `Settings.bundle` must be added manually in Xcode:
1. In Xcode, select the `Edge Debug Helper` target
2. File → New → File from Template → Resource → Settings Bundle
3. Name it `Settings`
4. Replace the generated `Root.plist` content with the XML above
5. Verify the bundle appears in the **Copy Bundle Resources** build phase for the
   iOS/iPadOS target only (not macOS)

---

## Implementation Order

1. Revert `SQLCipherService.swift` (schema back to v2, remove appSettings section)
2. Delete `SettingsRepository.swift`
3. Revert `AppState.swift` (remove metricsEnabled + SettingsRepository loading)
4. Update `QueryService.swift` (UserDefaults direct read, remove async await)
5. Revert `MetricsViews.swift` (remove Settings helpers)
6. Update `MainStudioView.swift` (add `@AppStorage`, update buildSidebarItems, remove Settings cases)
7. Create `Views/Settings/AppPreferencesView.swift`
8. Update `Ditto_Edge_StudioApp.swift` (add Settings scene + registerDefaults)
9. Delete `Views/Settings/SettingsView.swift`
10. Create `Settings.bundle/Root.plist` (manual Xcode step, documented above)
11. Build + verify

---

## Verification Checklist

### macOS
- [ ] App menu shows **"Settings…"** with **⌘,** shortcut
- [ ] Settings window opens with "General" tab
- [ ] Toggle is ON by default (fresh install)
- [ ] Toggle OFF → Metrics item disappears from sidebar **immediately** (same session)
- [ ] Toggle OFF → quit → relaunch → Metrics item still absent
- [ ] Toggle back ON → Metrics item reappears

### iOS / iPadOS
- [ ] iOS Settings app shows **"Ditto Edge Studio"** entry
- [ ] Toggle is ON by default (first install, before user visits Settings)
- [ ] Toggle OFF in Settings app → return to app → Metrics item absent
- [ ] Toggle ON in Settings app → return to app → Metrics item present
- [ ] UserDefaults key `"metricsEnabled"` reads `true` before user has ever visited
      Settings (requires `registerDefaults` to be working)

### Both Platforms
- [ ] Executing a query while metrics OFF → no entry added to Query Metrics list
- [ ] Build: zero compiler errors, zero warnings introduced
- [ ] Existing unit tests pass
