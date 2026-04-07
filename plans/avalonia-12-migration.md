# Avalonia 12 Migration Plan — Edge Studio (.NET)

**Created:** 2026-04-07
**Status:** Research Complete — Awaiting Approval

---

## 1. Current State

| Package | Version | Avalonia 12 Status |
|---------|---------|-------------------|
| **Avalonia (core)** | 11.3.13 | 12.0 released — ready to upgrade |
| **SukiUI** | 6.0.3 | **BLOCKED** — maintainer acknowledges breakage, no v12 branch. `PseudolassesExtensions` renamed to `PseudoClassesExtensions` in v12 breaks GlassCard at minimum. |
| **AvaloniaEdit / TextMate** | 11.4.1 | **BLOCKED** — open issue #557 (IScrollable, IDataObject, Clipboard API removals). No v12 branch exists. |
| **Avalonia.Svg.Skia** | 11.3.0 | **Likely OK** — issue #463 closed. Wieslawsoltes tracks Avalonia releases closely. Check NuGet for a 12.x release. |
| **Material.Icons.Avalonia** | 3.0.0 | **Unknown** — no issues filed. Simple package, likely quick to update. |
| **Consolonia** | 11.3.9-beta | **Unknown** — no issues filed. Niche package. |
| **Avalonia.Diagnostics** | 11.3.13 | **Removed in v12** — replace with `AvaloniaUI.DiagnosticsSupport` (already in project as 2.1.1) |

### Blockers Summary

The two hard blockers are **SukiUI** and **AvaloniaEdit**. Everything else either has a clear path or is version-agnostic.

---

## 2. SukiUI Usage Audit

SukiUI is deeply integrated across **47+ locations** in the codebase. Here's what we actually use:

### 2a. SukiWindow (15 windows)

Every window in the app inherits from `SukiWindow` instead of Avalonia's `Window`. This provides:
- Custom window chrome / title bar with themed close/minimize/maximize buttons
- `RightWindowTitleBarControls` for custom toolbar buttons
- `BackgroundStyle` property (Gradient vs Flat)
- Themed window appearance consistent with SukiTheme

**Windows using SukiWindow:**
MainWindow, DatabaseFormWindow, IndexFormWindow, ObserverFormWindow, SubscriptionFormWindow, QrCodeDisplayWindow, QrCodeImportWindow, PreferencesWindow, TransportSettingsWindow, AttachmentPickerWindow, DeleteAttachmentWindow, ImportDataWindow, UserGuideWindow, QuickstartBrowserWindow, QuickstartProgressWindow

### 2b. GlassCard (7 locations)

Semi-transparent card component used for:
- Database cards in listing view (interactive, tappable)
- Subscription/Observer list items
- Empty state overlays (no results, no indexes)
- History/Favorites tool views

### 2c. SukiTheme (application-wide)

- `<suki:SukiTheme />` in App.axaml
- `SukiTheme.GetInstance()` for runtime theme switching
- Controls light/dark mode across entire app
- Resource brushes: `SukiLowText`, etc.

### 2d. Toast Notification System

- `ISukiToastManager` / `SukiToastService` — fluent API for toast notifications
- `<suki:SukiToastHost>` in MainWindow.axaml
- Used throughout app for success/error/info messages

### 2e. Dialog System

- `ISukiDialogManager` / `SukiDialogService` — modal dialog builder
- `<suki:SukiDialogHost>` in MainWindow.axaml
- Builder pattern: `.CreateDialog().SetType().SetTitle().SetContent().AddActionButton().TryShow()`

### 2f. Styling Extensions

- `WrapPanelExtensions.AnimatedScroll` — animated scrolling in WrapPanels
- `BiggestItemListBoxConverter` — used in completion window styles
- Custom GlassCard styles (HeaderCard class)

---

## 3. SukiUI Replacement Strategy

Each SukiUI feature can be replaced with custom implementations. SukiUI is MIT-licensed, so we can reference its source code.

### 3a. Replace SukiWindow → Custom StudioWindow

**Effort: Medium | Priority: High (blocks everything)**

What SukiWindow provides:
- Themed window chrome with custom title bar buttons
- Background gradient/flat styles
- `RightWindowTitleBarControls` content area

Replacement approach:
- Avalonia 12 introduces `WindowDrawnDecorations` which gives us custom window chrome natively
- Create `StudioWindow : Window` base class that:
  - Uses `WindowDrawnDecorations` for custom chrome
  - Adds `BackgroundStyle` property (gradient via `OpacityMask` + `LinearGradientBrush`)
  - Supports `RightTitleBarContent` attached property for toolbar items
- **Reference:** SukiUI source `SukiWindow.cs` for animation/gradient logic

### 3b. Replace GlassCard → Custom GlassCard Control

**Effort: Low-Medium | Priority: High**

What GlassCard provides:
- Semi-transparent background with blur effect
- Corner radius
- `IsInteractive` property (hover/press visual feedback)
- Pointer event handling

Replacement approach:
- Create `GlassCard : ContentControl` with:
  - `ExperimentalAcrylicBorder` or `Border` with opacity for glass effect
  - `IsInteractive` property that adds hover/pressed pseudo-class styles
  - `CornerRadius`, `Padding` as styled properties
- Avalonia already has `ExperimentalAcrylicBorder` — main work is just the interaction states
- **Reference:** SukiUI source `GlassCard.cs` (~200 lines)

### 3c. Replace SukiTheme → Custom Theme System

**Effort: Medium | Priority: High**

What SukiTheme provides:
- Light/dark mode switching at runtime
- Custom color palette (accent colors)
- Resource brush definitions (`SukiLowText`, etc.)

Replacement approach:
- Use Avalonia 12's built-in `FluentTheme` or `SimpleTheme` as base
- Create `StudioTheme : Styles` that:
  - Defines custom resource brushes matching current SukiUI brush names
  - Implements `IResourceProvider` for runtime theme variant switching
  - Exposes `RequestedThemeVariant` for light/dark toggle
- Avalonia 12 has improved theming support — this is simpler than in v11
- Map existing `SukiLowText` → custom `StudioLowText` (or keep same names)

### 3d. Replace Toast System → Custom Toast Overlay

**Effort: Medium | Priority: Medium**

What SukiUI toasts provide:
- Overlay toast notifications with auto-dismiss
- Fluent builder API (`.WithTitle().WithContent().Queue()`)
- Animation (slide in/fade out)

Replacement approach:
- Create `ToastManager` service + `ToastHost` control
- `ToastHost`: ItemsControl overlay positioned at bottom-right
- `ToastItem`: Border with title, message, dismiss button, auto-dismiss timer
- Animate with Avalonia's `Animation` API (translate + opacity)
- Keep the fluent builder API pattern (it's clean)
- ~300-400 lines total

### 3e. Replace Dialog System → Custom Dialog Overlay

**Effort: Medium | Priority: Medium**

What SukiUI dialogs provide:
- Modal overlay with backdrop
- Builder pattern for title/content/buttons
- NotificationType enum for styling (Error, Warning, Info, Success)

Replacement approach:
- Create `DialogManager` service + `DialogHost` overlay control
- `DialogHost`: Grid overlay with semi-transparent backdrop + centered content
- Builder API: `.CreateDialog().SetTitle().SetContent().AddButton().Show()`
- ~300-400 lines total

### 3f. Replace Styling Extensions

**Effort: Low | Priority: Low**

- `AnimatedScroll`: Implement as custom attached property with `ScrollViewer.Offset` animation
- `BiggestItemListBoxConverter`: Simple IValueConverter, ~30 lines
- `HeaderCard` style: Just margin/padding — trivial

---

## 4. AvaloniaEdit Migration

AvaloniaEdit has an **open issue (#557)** with no resolution. The breaking changes are significant:
- `IScrollable` interface removed
- `IDataObject` → `IAsyncDataTransfer` (clipboard rework)
- Multiple compilation failures

**Options:**

| Option | Effort | Risk |
|--------|--------|------|
| **A. Wait for upstream fix** | None | High — no timeline, could be months |
| **B. Fork and fix ourselves** | High | Medium — we'd own the fork |
| **C. Replace with custom editor** | Very High | Low — but massive effort |
| **D. Phased migration** | Medium | Low — migrate everything else first, keep AvaloniaEdit on a compatibility shim |

**Recommendation: Option D** — Migrate everything else to Avalonia 12, and either:
- Wait for AvaloniaEdit to release a v12-compatible version (likely given it's under AvaloniaUI org)
- If blocked too long, fork and apply the specific fixes needed (the breaking changes are known: IScrollable, IDataObject, Clipboard)

---

## 5. Avalonia 12 Breaking Changes Affecting Our Code

### Must Fix (will not compile without)

| Change | Impact | Fix |
|--------|--------|-----|
| `Binding` → `ReflectionBinding` | Any C# code-behind bindings | Find/replace in code-behind |
| `AttachDevTools()` → `AttachDeveloperTools()` | App startup | Single line change |
| `Avalonia.Diagnostics` removed | Package reference | Already have `AvaloniaUI.DiagnosticsSupport` |
| `PseudolassesExtensions` → `PseudoClassesExtensions` | Only in SukiUI (not our code) | Solved by removing SukiUI |
| `IDataObject` → `IAsyncDataTransfer` | Clipboard operations | Update clipboard code |
| `GotFocusEventArgs` → `FocusChangedEventArgs` | Focus event handlers | Update event signatures |
| Add `.UseHarfBuzz()` to app builder | Text rendering | One line addition |
| Compiled bindings default on | XAML bindings | Should work, but test thoroughly |

### Should Fix (obsolete warnings)

| Change | Impact | Fix |
|--------|--------|-----|
| `TextBox.Watermark` → `PlaceholderText` | TextBox placeholders | Find/replace in XAML |
| `Window.SystemDecorations` → `WindowDecorations` | Window config | Find/replace |
| `Gestures.Pinch` → `Pinch` | Gesture handlers (if any) | XAML attribute rename |

---

## 6. Proposed Migration Phases

### Phase 1: Build Custom UI Library (2-3 weeks)

Create `EdgeStudio.UI` project with SukiUI replacements:
1. `StudioWindow` base class (using Avalonia 12 `WindowDrawnDecorations`)
2. `GlassCard` control
3. `StudioTheme` with light/dark mode
4. `ToastManager` + `ToastHost`
5. `DialogManager` + `DialogHost`
6. Styling extensions (AnimatedScroll, converters)

**Can be built against Avalonia 11 first**, then upgraded to 12. This de-risks the migration.

### Phase 2: Replace SukiUI References (1 week)

1. Swap all `SukiWindow` → `StudioWindow` (15 files)
2. Swap all `<suki:GlassCard>` → `<studio:GlassCard>` (7 files)
3. Replace `SukiTheme` → `StudioTheme` in App.axaml
4. Update DI registrations for toast/dialog services
5. Remove SukiUI NuGet package
6. Verify build and test on Avalonia 11

### Phase 3: Upgrade to Avalonia 12 (1-2 weeks)

1. Update all Avalonia packages to 12.x
2. Apply breaking change fixes (binding, clipboard, focus, etc.)
3. Add `.UseHarfBuzz()` to app builder
4. Update `AttachDevTools()` → `AttachDeveloperTools()`
5. Fix any compiled binding issues
6. Update Svg.Skia and Material.Icons.Avalonia to v12-compatible versions
7. Handle AvaloniaEdit — either updated upstream version or fork

### Phase 4: Polish & Optimize (1 week)

1. Take advantage of Avalonia 12 performance improvements
2. Leverage new `WindowDrawnDecorations` for better window chrome
3. Test on Windows, macOS, Linux
4. Update Consolonia if v12-compatible (or drop if not needed)
5. Performance benchmarking

---

## 7. Consolonia Assessment

Consolonia (`11.3.9-beta`) is used for console UI. Need to determine:
- Is it actively used in production, or experimental?
- If experimental, can be dropped or deferred
- If needed, may require fork or alternative

---

## 8. Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| AvaloniaEdit never gets v12 support | Low (it's AvaloniaUI org) | High | Fork and fix the 3 known breaking APIs |
| Custom UI components don't match SukiUI quality | Medium | Medium | Reference SukiUI source; iterate on polish |
| Hidden Avalonia 12 breaking changes | Medium | Medium | Phase 1 builds against v11 first |
| Material.Icons.Avalonia incompatible | Low | Low | Icons are just fonts; easy to inline |
| Performance regressions | Low | Medium | Benchmark before/after |

---

## 9. Decision Needed

- **Approve Phase 1 start?** Building the custom UI library can begin immediately
- **AvaloniaEdit strategy?** Wait vs fork vs replace
- **Consolonia priority?** Keep, drop, or defer?
- **Timeline target?** When do you want Avalonia 12 in production?
