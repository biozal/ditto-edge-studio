# UI Terminology Cheat Sheet — SwiftUI vs Android

Canonical names for the screen regions in both Edge Studio implementations.
When a plan, task, or conversation uses one of these terms, it refers to exactly
the region shown below.

For the Android Rail items themselves (Presence, Query Workbench, Observation,
Log Analyzer, App Metrics, Query Metrics, Database Metrics) and what each puts
in these regions, see [`RAIL_FEATURES.md`](RAIL_FEATURES.md).

![UI Layout Terminology — SwiftUI vs Android](images/ui-terminology.png)

*(Source: [`images/ui-terminology.svg`](images/ui-terminology.svg) — regenerate the PNG with `rsvg-convert -w 3840 --keep-aspect-ratio ui-terminology.svg -o ui-terminology.png`)*

---

## Side-by-Side Layout Comparison

### SwiftUI (macOS / iPadOS) — three-column layout

```
┌────────────────────────────────────────────────────────────────────────┐
│  Toolbar                  (sync toggle · close · inspector toggle)     │
├──────────────┬──────────────────────────────────────┬──────────────────┤
│              │                                      │                  │
│   SIDEBAR    │              MAINVIEW                │    INSPECTOR     │
│  200–300px   │           (detail area)              │    250–500px     │
│              │                                      │                  │
│  ┌────────┐  │   Collections → QueryEditor +        │  ┌────────────┐  │
│  │segmented│ │                 QueryResults         │  │ segmented  │  │
│  │ picker  │ │   Observer    → events + detail      │  │  picker    │  │
│  └────────┘  │   Subscriptions → sync tabs          │  └────────────┘  │
│              │                                      │                  │
│  Subscript.  │                                      │   History        │
│  Collections │                                      │   Favorites      │
│  Observer    │                                      │                  │
├──────────────┴──────────────────────────────────────┴──────────────────┤
│  Status Bar              (sync status · peer count)                    │
└────────────────────────────────────────────────────────────────────────┘
```

### Android (≥840dp) — scene-driven list-detail layout

```
┌────────────────────────────────────────────────────────────────────────┐
│       │  TopAppBar          (sync · close · inspector toggle)          │
│  ┌──┐ ├──────────────────┬──────────────────────────┬──────────────────┤
│  │▣ │ │                  │                          │                  │
│  │  │ │   DATA PANEL     │      CONTENT PANE        │    INSPECTOR     │
│  │◇ │ │  (list pane)     │     (detail pane)        │  300–400dp       │
│  │  │ │  scene-managed   │                          │  (default-       │
│  │○ │ │  width; capped   │  Query  → editor+results │   visible at     │
│  │  │ │  320dp at ≥1200  │  Obs.   → events+detail  │   ≥1200dp)       │
│  │⚙ │ │                  │  Pres.  → peers/tabs     │                  │
│  └──┘ │  feature menu /  │                          │  Query: History  │
│       │  list for the    │  ┌───────────────────┐   │  Favorites       │
│  RAIL │  selected item   │  │ QueryWorkbenchBar  │   │  JSON / Metrics  │
│       │  (default at     │  └───────────────────┘   │  Others: help    │
│       │   ≥840dp)        │                          │                  │
└───────┴──────────────────┴──────────────────────────┴──────────────────┘
```

### Android (<600dp) — Rail collapses into the Nav Drawer

```
┌──────────────────────────┐      ┌──────────────────────────┐
│ ☰  TopAppBar             │      │▓▓▓▓▓▓▓▓▓▓▓│              │
├──────────────────────────┤      │▓ NAV     ▓│              │
│                          │  ☰ → │▓ DRAWER  ▓│  (content    │
│  LIST PANE (Data Panel)  │      │▓         ▓│   dimmed)    │
│  or DETAIL (Content Pane)│      │▓  Rail   ▓│              │
│  (single pane at a time; │      │▓  items  ▓│              │
│   drill-in via back stack│      │▓  only   ▓│              │
│   from list to detail)   │      │▓         ▓│              │
└──────────────────────────┘      └───────────┴──────────────┘
```

---

## Term Mapping Table

| iOS (SwiftUI) | Android (Edge Studio) | Android code | Material Design term |
|---|---|---|---|
| Sidebar — segmented picker | **Rail** | `NavigationRail` in `StudioScaffold` (≥600dp) | Navigation Rail |
| Sidebar — content list | **Data Panel** | `ListDetailSceneStrategy.listPane` in `AppNavGraph`; scene-managed width (preferred 320dp at ≥1200dp); default-visible at ≥840dp | List pane (list-detail layout) |
| MainView | **Content Pane** | `ListDetailSceneStrategy.detailPane` (or `detailPlaceholder`) | Detail pane / content pane |
| Inspector | **Inspector** | Inspector column in `StudioScaffold`; 300dp (<1200dp) / 360dp (≥1200dp) / 400dp (≥1600dp); `ModalBottomSheet` at compact (<600dp) | Side sheet / supporting pane |
| — (iPadOS uses sidebar) | **Nav Drawer** (compact only) | `ModalNavigationDrawer` in `StudioScaffold` (<600dp) | Modal navigation drawer |
| Toolbar | **Top Bar** | `TopAppBar` in `StudioScaffold` | Top app bar |
| Status Bar (bottom) | **Bottom Bar** | Floating `QueryWorkbenchBottomBar` (Query section only) | Bottom app bar |

---

## Behavior Differences Worth Remembering

| Behavior | iOS | Android |
|---|---|---|
| Data Panel visibility | Always visible | Default-visible at ≥840dp (Expanded); scene controls width; can be toggled on narrower windows |
| Inspector visibility | Toggle via toolbar button | Default-visible at ≥1200dp (Large); toggle via top-bar button; `ModalBottomSheet` at compact |
| Navigation switcher | Segmented picker (48pt SF Symbols) | Rail items (Material icons, `SulfurYellow` indicator); visible at ≥600dp (Medium+) |
| Phone / compact adaptation | n/a (iPadOS/macOS only) | Rail collapses into the modal Nav Drawer at <600dp; Data Panel becomes list-pane of scene |
| Status/utility bar | Persistent bottom status bar | Floating `QueryWorkbenchBottomBar` in Query section (run, pagination, peers, overflow) |

---

*Source of truth for the Android layout: `android/app/src/main/java/com/costoda/dittoedgestudio/ui/mainstudio/StudioScaffold.kt` + `android/app/src/main/java/com/costoda/dittoedgestudio/ui/navigation/AppNavGraph.kt`*
*Source of truth for the iOS layout: `SwiftUI/EdgeStudio/Views/MainStudioView.swift`*
