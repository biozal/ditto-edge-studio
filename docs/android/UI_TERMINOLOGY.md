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

### Android (tablet) — four-region layout

```
┌────────────────────────────────────────────────────────────────────────┐
│       │ StudioTopBar     (data-panel toggle · sync · inspector toggle) │
│  ┌──┐ ├─────────────┬───────────────────────────────┬──────────────────┤
│  │▣ │ │             │                               │                  │
│  │  │ │ DATA PANEL  │         CONTENT PANE          │    INSPECTOR     │
│  │◇ │ │   200dp     │          weight(1f)           │      300dp       │
│  │  │ │ (toggleable,│                               │  (toggleable,    │
│  │○ │ │  slides in  │   Query  → editor + results   │   slides in      │
│  │  │ │  from start)│   Observer → events + detail  │   from end)      │
│  │⚙ │ │             │   Sync   → peers/presence     │                  │
│  └──┘ │  menu/info  │                               │   History        │
│       │  for the    │   ┌─────────────────────┐     │   Favorites      │
│  RAIL │  selected   │   │ QueryBottomBar / FAB │    │                  │
│       │  Rail item  │   └─────────────────────┘     │                  │
└───────┴─────────────┴───────────────────────────────┴──────────────────┘
```

### Android (phone) — Rail + Data Panel collapse into the Nav Drawer

```
┌──────────────────────────┐      ┌──────────────────────────┐
│ ☰  StudioTopBar          │      │▓▓▓▓▓▓▓▓▓▓▓│              │
├──────────────────────────┤      │▓ NAV     ▓│              │
│                          │  ☰ → │▓ DRAWER  ▓│  (content    │
│       CONTENT PANE       │      │▓         ▓│   dimmed)    │
│      (full width)        │      │▓ Rail +  ▓│              │
│                          │      │▓ Data    ▓│              │
│                          │      │▓ Panel   ▓│              │
│                          │      │▓ merged  ▓│              │
└──────────────────────────┘      └───────────┴──────────────┘
```

---

## Term Mapping Table

| iOS (SwiftUI) | Android (Edge Studio) | Android code | Material Design term |
|---|---|---|---|
| Sidebar — segmented picker | **Rail** | `NavigationRail` | Navigation Rail |
| Sidebar — content list | **Data Panel** | `DataPanel` (200dp) | List pane (list-detail layout) |
| MainView | **Content Pane** | content `Column`, `weight(1f)` | Detail pane / content pane |
| Inspector | **Inspector** | `InspectorPanel` (300dp) | Side sheet / supporting pane |
| — (iPadOS uses sidebar) | **Nav Drawer** (phone only) | `ModalNavigationDrawer` | Modal navigation drawer |
| Toolbar | **Top Bar** | `StudioTopBar` | Top app bar |
| Status Bar (bottom) | **Bottom Bar** | `StudioBottomBar` / `QueryBottomBar` | Bottom app bar |

---

## Behavior Differences Worth Remembering

| Behavior | iOS | Android |
|---|---|---|
| Sidebar/Data Panel visibility | Always visible | Toggleable — slides in/out from the start edge |
| Inspector visibility | Toggle via toolbar button | Toggle via top-bar button — slides in/out from the end edge |
| Navigation switcher | Segmented picker (48pt SF Symbols) | Rail items (Material icons, `SulfurYellow` indicator) |
| Phone adaptation | n/a (iPadOS/macOS only) | Rail + Data Panel merge into the modal Nav Drawer |
| Status/utility bar | Persistent bottom status bar | Expandable `StudioBottomBar` (FAB collapses/expands it) |

---

*Source of truth for the Android layout: `android/app/src/main/java/com/costoda/dittoedgestudio/ui/mainstudio/MainStudioScreen.kt`*
*Source of truth for the iOS layout: `SwiftUI/EdgeStudio/Views/MainStudioView.swift`*
