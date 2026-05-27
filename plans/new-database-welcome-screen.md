# New-Database Open Experience: Welcome Screen + Empty-State Polish

**Status:** Plan
**Date:** 2026-05-26
**Owner:** Aaron LaBeau
**Reference screenshot:** `screens/swift-new-database-open.png`
**Reference impl:** `~/Developer/ditto-vsc-es` (VSCode extension) —
`src/panels/WelcomePanel.ts` + `webview-ui/welcome/welcome-element.ts`

## What we're solving

When a user opens Edge Studio for the first time on a brand-new database
configuration, the experience falls short in four discrete ways. Each
gets a targeted fix below.

1. **Empty-state messages dominate the sidebar.** `ContentUnavailableView`
   renders a `.title`-sized headline that wraps to *"No\nSubscrip-\ntions"*
   (and similarly for Collections and Observers) inside a ~200pt sidebar
   column. The screen feels broken before the user has typed anything.
2. **Empty-state action buttons have unreadable text/icons.** The
   "Add Subscription / Run a Query / Add Observer" buttons use
   `.buttonStyle(.borderedProminent) + .tint(.dittoYellow) +
   .foregroundStyle(Color.black)` — but the foreground style does not
   propagate to the SF Symbol icon inside the `Label`, leaving a
   yellow-on-yellow blob.
3. **The sidebar picker opens on Query** because
   `selectedSidebarDestination` is restored from global `UserDefaults`,
   carrying over the previous database's last-viewed tab. For a brand-new
   database with no subscriptions, Query is a dead end — there are no
   collections to read.
4. **There is no onboarding.** The VSCode version of Edge Studio ships
   a `WelcomePanel` that explains Ditto, the extension's capabilities,
   and the three-step path from "fresh install" to "synced database".
   The SwiftUI version has nothing equivalent.

## Scope guardrails

- macOS *and* iPadOS — every change must build for both per CLAUDE.md.
- No new third-party packages.
- No DQL or sync changes — purely UI / view-model / preferences.
- Preserve existing accessibility identifiers (`EmptySubscriptionsAddButton`,
  `EmptyCollectionsQueryButton`, `EmptyObserversAddButton`) so UI tests
  still pass.

---

## 1. Compact sidebar empty states

**Files:** `SwiftUI/EdgeStudio/Views/StudioView/SidebarViews.swift:68-84`,
`:110-128`, `:155-173`

**Problem.** `ContentUnavailableView` is built for full-pane empty
states. Its title uses `.title2` weight semibold and its icon is ~40pt.
In the sidebar this overflows.

**Fix.** Introduce a small reusable view that fits the sidebar idiom:

```swift
/// Compact sidebar empty-state row. Replaces ContentUnavailableView,
/// whose default sizing is built for full-pane usage and overflows
/// in the ~200pt sidebar column.
private struct SidebarEmptyStateRow<Actions: View>: View {
    let icon: String        // SF Symbol
    let title: String
    let description: String
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            actions()
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}
```

Replace each `ContentUnavailableView { … } description: { … } actions: { … }`
block with `SidebarEmptyStateRow(icon: …, title: …, description: …) { … }`,
keeping the same icon strings, copy, button bodies, and accessibility
identifiers.

**Sizing intent.** Title goes from ~22pt down to ~13pt (`.subheadline`).
Icon goes from ~40pt down to 22pt. Description stays `.caption`. Total
section height drops from ~120pt to ~80pt, comfortably fitting three
sections + a partial fourth in a single sidebar viewport.

---

## 2. Fix empty-state button colors

**Files:** Same three call sites in `SidebarViews.swift`.

**Problem.** `.borderedProminent` derives its label color from the
button's `tint` (yellow → near-white default label). `.foregroundStyle`
only affects parts of the `Label` SwiftUI doesn't itself colorize — the
SF Symbol resists it.

**Fix.** Stop fighting `.borderedProminent` and roll a custom yellow
button. The result has guaranteed black text + black icon:

```swift
private struct DittoYellowButton: View {
    let title: String
    let systemIcon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemIcon)
                    .font(.caption.weight(.semibold))
                Text(title)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(Color.black)        // applies to BOTH children
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.dittoYellow)
            )
        }
        .buttonStyle(.plain)                     // opt out of platform tinting
    }
}
```

Each call site shrinks from ~6 lines of `.buttonStyle / .tint /
.foregroundStyle` chaining to a single
`DittoYellowButton(title: "Add Subscription", systemIcon: "plus",
action: { presentNewSubscriptionEditor() })` line, preserving the existing
`.accessibilityIdentifier(…)` modifier afterward.

---

## 3. Default new databases to Subscriptions

**Files:** `SwiftUI/EdgeStudio/Views/StudioView/ViewModels/MainStudioViewModel.swift:134-137`

**Problem.** The current restore is "whatever you last had, globally":

```swift
let storedDestination = UserDefaults.standard
    .string(forKey: Self.sidebarDestinationKey)
    .flatMap(SidebarDestination.init(rawValue:))
selectedSidebarDestination = storedDestination ?? .subscriptions
```

A user who closes their old database on Query and then opens a new one
gets dropped into Query with no collections to query.

**Fix.** Override the restore when the active database has no subscriptions
*and* no query history — that's the same "new user" signal we'll use for
the welcome auto-open. We can't synchronously know subscription/history
counts in `init` (they're loaded later via async repos), so:

- Keep the persisted restore for the initial render (no jarring re-mount).
- After `performLoad` finishes, if the loaded subscriptions and query
  history are both empty AND the restored destination is anything except
  `.subscriptions`, force-switch to `.subscriptions`. Don't write back to
  UserDefaults — the user's last *intentional* choice from their other
  databases is preserved.

Concrete shape, slotted into the existing `performLoad` after both repos
have populated:

```swift
// If this database is fresh (no subs, no history), force the sidebar
// to Subscriptions — Query/Observers are dead-ends with no data.
// Don't persist; preserve the user's last intentional choice for
// other databases. Matches the welcome-screen auto-open heuristic.
if subObsVM.subscriptions.isEmpty
   && queryVM.recentHistory.isEmpty
   && selectedSidebarDestination != .subscriptions {
    selectedSidebarDestination = .subscriptions
}
```

The `didSet` writes-back to UserDefaults — we can't avoid that without
restructuring. Two options:

1. **Cheap.** Read the value back before mutation and only write if the
   user-driven `didSet` was followed by a change — i.e. accept a single
   redundant write per new-database open. Effectively a no-op except in
   testing.
2. **Clean.** Refactor `selectedSidebarDestination` to a stored property
   without `didSet`, and route writes through a `setSidebarDestination(_:)`
   method that the picker uses; the auto-correction calls a private
   `silentSetSidebarDestination(_:)` that skips persistence.

Recommend option 2 — the silent setter is also useful for other UI
flows (close → reopen) where we don't want to persist the auto-restore.

---

## 4. Welcome screen

This is the largest piece. Mirrors VSCode's `WelcomePanel.ts` /
`welcome-element.ts`.

### 4a. Window scaffold

**File (new):** `SwiftUI/EdgeStudio/Views/Welcome/WelcomeWindow.swift`
**File (new):** `SwiftUI/EdgeStudio/Views/Welcome/WelcomeView.swift`

`WelcomeWindow` is the SwiftUI window wrapper; `WelcomeView` is its
content (so we can reuse the view inside a sheet on iPadOS, where
multi-window is awkward).

Window setup in `Ditto_Edge_StudioApp.swift` next to the existing
`help-window` group:

```swift
WindowGroup(id: "welcome-window") {
    WelcomeWindow()
}
.windowStyle(.hiddenTitleBar)
.windowResizability(.contentSize)
.defaultSize(width: 880, height: 720)
```

Plus a `WindowController.openWelcomeWindow()` helper and a notification
plumb identical to the existing `OpenHelpWindow` pattern at
`Ditto_Edge_StudioApp.swift:11-12`.

### 4b. Content

Translates the VSCode welcome-element 1:1 into SwiftUI. Sections in
order, each a `VStack` aligned leading:

1. **Hero** — large bolt-glyph (or app icon) + title "Welcome to Ditto
   Edge Studio" + subtitle that swaps between two strings based on
   `hasExistingDatabases`. Same Bool gate the VSCode version uses.
2. **What is Ditto?** — paragraph + `.quote` block (a `VStack` with a
   leading 3pt accent bar, ditto-yellow tint). Footer link "About Ditto"
   opens `https://docs.ditto.live/home/about-ditto` via `NSWorkspace`.
3. **What this extension does** — title + lead paragraph + 8-card
   feature grid (`LazyVGrid` 2 columns, wraps to 1 column under
   ~720pt width). Cards are titled rounded rectangles with body copy.
   Card content matches the `FEATURES` array verbatim from
   `welcome-element.ts:23-69` — *port the strings exactly*; don't
   rewrite.
4. **Get started in three steps** — title swaps based on
   `hasExistingDatabases` ("Get started in three steps" vs "Adding
   another connection"). Numbered three-row list, each row has a
   circular step number, step title, body, and an external link.
5. **Try a Quickstart** — title + quote block + two buttons:
   "Get Quickstarts" (primary, triggers existing
   `viewModel.startQuickstartDownload()` flow) and a link to the
   GitHub repo.
6. **Learn more** — footer strip with three links: Ditto docs, DQL
   reference, Mesh Presence guide.

All `NSWorkspace.shared.open(url)` calls go through a tiny helper to
avoid the `URL(string: …)` boilerplate.

**Note on style.** The VSCode version uses CSS variables for theme
colors. Translate as follows:

| VSCode token | SwiftUI |
|---|---|
| `--vscode-foreground` | `.primary` |
| `--vscode-descriptionForeground` | `.secondary` |
| `--vscode-button-background` | `Color.dittoYellow` |
| `--vscode-button-foreground` | `Color.black` (on yellow) |
| `--vscode-panel-border` | `Color.secondary.opacity(0.2)` |
| `--vscode-textCodeBlock-background` | `Color.secondary.opacity(0.08)` |

### 4c. "Show on next open" checkbox + preference

Bottom of the welcome view, before the Learn More footer:

```swift
Toggle("Show this screen when opening a new database",
       isOn: $showWelcomeOnNewDatabase)
    .font(.caption)
```

Backed by `@AppStorage("showWelcomeOnNewDatabase")` with a default of
`true`. Stored in standard `UserDefaults` — no Keychain or SQLCipher
needed; it's a UI pref.

A "Close" button in section 4 (matching VSCode's "Maybe later") simply
dismisses the window.

### 4d. Auto-open trigger

In `MainStudioViewModel.performLoad`, after subs + history loads, check:

```swift
let isFreshDb = subObsVM.subscriptions.isEmpty
             && queryVM.recentHistory.isEmpty
let userOptedIn = UserDefaults.standard
    .object(forKey: "showWelcomeOnNewDatabase") as? Bool ?? true

if isFreshDb && userOptedIn {
    // Defer to next runloop so the studio view has mounted first;
    // opening the window while ContentView is still transitioning
    // can produce a focus-stealing flash.
    Task { @MainActor in
        WindowController.openWelcomeWindow()
    }
}
```

The auto-open is per database-open, not per launch. If the user closes
welcome, runs a query, and reopens the same database, no welcome —
because `queryVM.recentHistory` is no longer empty.

### 4e. Help menu integration

`Ditto_Edge_StudioApp.swift:178-205` — add a "Welcome" button right
under "User Guide":

```swift
CommandGroup(replacing: .help) {
    Button("Welcome") {
        WindowController.openWelcomeWindow()
    }
    Button("User Guide") { … }   // existing
    // …rest of the help menu unchanged
}
```

Order intent: Welcome first because it's the friendly-onboarding entry;
User Guide second for users who already know what they're doing.

### 4f. iPadOS

Multi-window on iPadOS via `WindowGroup` is supported on iPadOS 16+ but
the UX is awkward — users have to drag to split-screen to see both
welcome and studio. Simpler: on iPadOS, present `WelcomeView` as a
`.sheet` over `MainStudioView` instead of a separate window.

Implementation: `WindowController.openWelcomeWindow()` becomes
`Welcome.present()`, which on macOS routes to the WindowGroup and on
iOS posts a notification that `MainStudioView` listens to and sets a
`@State var isShowingWelcome = true` driving a `.sheet`.

---

## Verification

After all four changes land:

- [ ] Sidebar empty states fit one viewport on a 200pt sidebar without
      hyphenated wrapping. Take a screenshot, compare to baseline.
- [ ] Empty-state buttons render with black icon + black text on a
      `.dittoYellow` background. Verify in both light and dark mode.
- [ ] Open a fresh database (no subs, no history). Sidebar lands on
      Subscriptions regardless of which tab was last open on a
      different database. Once the user navigates to Query, that
      *does* persist for the next session.
- [ ] Open a fresh database — welcome window opens automatically.
- [ ] Help menu → Welcome reopens the window even after dismissal.
- [ ] Check "Show this screen when opening a new database" → uncheck,
      close, reopen another fresh database — welcome does NOT open.
      Help → Welcome still opens it on demand.
- [ ] Build clean on macOS (`platform=macOS,arch=arm64`).
- [ ] Build clean on iPadOS Simulator
      (`platform=iOS Simulator,name=iPad Pro 13-inch (M5)`).
- [ ] UI test suite still green — accessibility identifiers preserved.

## Out of scope

- Localization (string catalog) — current app strings are hard-coded
  English. Welcome content matches that convention.
- Animated tour / interactive walkthrough — defer until v1.1.
- Embedded video — VSCode version has none either; static content is
  fine for first cut.
- "What's new in this version" panel — separate feature.

## Order of operations

I'd land these in this order so each step has user-visible payoff and
the diff stays reviewable:

1. **Section 1** (compact empty states) — single file, smallest blast
   radius. Fixes the most visually broken thing first.
2. **Section 2** (yellow button) — same file as #1, natural follow-on.
3. **Section 3** (default to Subscriptions) — single view-model change.
4. **Section 4** (welcome screen) — new files, new menu item, biggest
   diff. Land last so any review concerns on the other three are
   already resolved.
