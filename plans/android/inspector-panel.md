# Android Inspector Panel — Plan

## Overview

The Android app currently shows "Inspector — Coming Soon" in both its tablet side panel and phone bottom sheet. This plan replaces that placeholder with a fully functional, context-aware inspector that matches the SwiftUI version's Inspector panel.

**Reference implementation:** `SwiftUI/EdgeStudio/Views/StudioView/InspectorViews.swift`

The core characteristic of the Inspector is that its content changes completely based on which sidebar nav item (`StudioNavItem`) is currently selected. Each nav item gets a purpose-built inspector with different tabs.

---

## Scope

**In scope (this plan):**
- Context-aware inspector dispatching by `selectedNavItem`
- Help tab (markdown viewer) for every nav item
- Markdown rendering via Markwon (wrapped in `AndroidView`)
- Assets wired from `assets/help/` — populated by the centralized docs build pipeline (see `plans/android/centralized-help-docs-pipeline.md`)

**Deferred (depends on Query tab feature):**
- QUERY inspector: History and Favorites tabs
- These tabs depend on `HistoryRepository` and `FavoritesRepository` being wired into `MainStudioViewModel`, which is not worthwhile until the Query editor is built

---

## Inspector Content by Nav Item

| `StudioNavItem` | Inspector Tabs | Help File |
|---|---|---|
| `SUBSCRIPTIONS` | Help | `subscription.md` |
| `QUERY` | Help (History + Favorites deferred) | `query.md` |
| `OBSERVERS` | Help | `observe.md` |
| `LOGGING` | Help | `logging.md` |
| `APP_METRICS` | Help | `appmetrics.md` |
| `QUERY_METRICS` | Help | `querymetrics.md` |

When the Query tab is fully implemented, the QUERY inspector will gain two additional tabs: **History** and **Favorites**, matching the SwiftUI inspector exactly.

---

## Architecture

```
selectedNavItem
    ↓
InspectorContentView (context-aware dispatcher)
    └── HelpInspectorContent (for each nav item)
            └── HelpContentView
                    └── Markwon → AndroidView(TextView)
                            ↑
                    assets/help/{filename}.md
```

---

## Markdown Rendering — Markwon

**Library:** `io.noties.markwon:markwon-core` + plugins
**Why Markwon:** Most mature Android markdown library (5M+ downloads), excellent table support, clean link handling, reliable code block rendering.

### Dependency additions

**`gradle/libs.versions.toml`:**
```toml
[versions]
markwon = "4.6.2"

[libraries]
markwon-core    = { group = "io.noties.markwon", name = "core",       version.ref = "markwon" }
markwon-html    = { group = "io.noties.markwon", name = "html",       version.ref = "markwon" }
markwon-tables  = { group = "io.noties.markwon", name = "ext-tables", version.ref = "markwon" }
markwon-linkify = { group = "io.noties.markwon", name = "linkify",    version.ref = "markwon" }
```

**`app/build.gradle.kts`:**
```kotlin
implementation(libs.markwon.core)
implementation(libs.markwon.html)
implementation(libs.markwon.tables)
implementation(libs.markwon.linkify)
```

### Asset loading

Help files live in `assets/help/` (copied there by the centralized docs pipeline). Loading pattern:
```kotlin
fun loadHelpAsset(context: Context, fileName: String): String {
    return try {
        context.assets.open("help/$fileName").bufferedReader().readText()
    } catch (e: Exception) {
        "# Help\n\nDocumentation not found."
    }
}
```

---

## New Files

| File | Purpose |
|------|---------|
| `ui/mainstudio/inspector/InspectorContentView.kt` | Context-aware dispatcher — switches on `selectedNavItem` to show the right inspector |
| `ui/mainstudio/inspector/HelpContentView.kt` | Markwon-powered markdown renderer composable |

---

## Modified Files

| File | Change |
|------|--------|
| `app/build.gradle.kts` | Add Markwon dependencies |
| `gradle/libs.versions.toml` | Add `markwon` version + 4 library entries |
| `ui/mainstudio/MainStudioScreen.kt` | Replace "Coming Soon" in `InspectorPanel` and `InspectorContent` with `InspectorContentView` |

---

## Implementation Detail

### `HelpContentView.kt`

```kotlin
@Composable
fun HelpContentView(
    assetFileName: String,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val markdown = remember(assetFileName) { loadHelpAsset(context, assetFileName) }

    val markwon = remember(context) {
        Markwon.builder(context)
            .usePlugin(HtmlPlugin.create())
            .usePlugin(TablePlugin.create(context))
            .usePlugin(LinkifyPlugin.create())
            .build()
    }

    AndroidView(
        modifier = modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
        factory = { ctx ->
            TextView(ctx).apply {
                movementMethod = LinkMovementMethod.getInstance()
                setTextIsSelectable(true)
            }
        },
        update = { tv ->
            markwon.setMarkdown(tv, markdown)
        }
    )
}

private fun loadHelpAsset(context: Context, fileName: String): String {
    return try {
        context.assets.open("help/$fileName").bufferedReader().readText()
    } catch (e: Exception) {
        "# Help\n\nDocumentation not found."
    }
}
```

> **Note:** `verticalScroll` on an `AndroidView` containing a `TextView` can conflict. Use `NestedScrollView` wrapping the AndroidView via the factory approach, or disable the outer `verticalScroll` and rely on Markwon's built-in `ScrollingMovementMethod`. The plan uses the outer scroll approach (simpler) — if conflicts occur, switch to `AndroidView { NestedScrollView }`.

**Alternative if scroll conflicts arise:**
```kotlin
AndroidView(
    modifier = modifier.fillMaxSize(),
    factory = { ctx ->
        android.widget.ScrollView(ctx).apply {
            addView(TextView(ctx).apply {
                movementMethod = LinkMovementMethod.getInstance()
                setTextIsSelectable(true)
                setPadding(16.dpToPx(ctx), 16.dpToPx(ctx), 16.dpToPx(ctx), 16.dpToPx(ctx))
            })
        }
    },
    update = { sv ->
        val tv = (sv as android.widget.ScrollView).getChildAt(0) as TextView
        markwon.setMarkdown(tv, markdown)
    }
)
```

---

### `InspectorContentView.kt`

```kotlin
@Composable
fun InspectorContentView(
    selectedNavItem: StudioNavItem,
    modifier: Modifier = Modifier,
) {
    val helpFile = when (selectedNavItem) {
        StudioNavItem.SUBSCRIPTIONS  -> "subscription.md"
        StudioNavItem.QUERY          -> "query.md"
        StudioNavItem.OBSERVERS      -> "observe.md"
        StudioNavItem.LOGGING        -> "logging.md"
        StudioNavItem.APP_METRICS    -> "appmetrics.md"
        StudioNavItem.QUERY_METRICS  -> "querymetrics.md"
    }

    Column(modifier = modifier.fillMaxSize()) {
        // Tab row — single Help tab for now; expand when History/Favorites added
        Surface(
            color = MaterialTheme.colorScheme.surfaceContainerLow,
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Icon(
                    imageVector = Icons.Outlined.HelpOutline,
                    contentDescription = null,
                    modifier = Modifier.size(16.dp),
                    tint = MaterialTheme.colorScheme.primary,
                )
                Text(
                    text = "Help",
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.primary,
                )
            }
        }

        HorizontalDivider()

        HelpContentView(
            assetFileName = helpFile,
            modifier = Modifier.weight(1f),
        )
    }
}
```

---

### `MainStudioScreen.kt` changes

**Replace `InspectorPanel` (tablet):**
```kotlin
@Composable
private fun InspectorPanel(viewModel: MainStudioViewModel, modifier: Modifier = Modifier) {
    Row(modifier = modifier) {
        VerticalDivider()
        InspectorContentView(
            selectedNavItem = viewModel.selectedNavItem,
            modifier = Modifier.weight(1f),
        )
    }
}
```

**Replace `InspectorContent` (phone bottom sheet):**
```kotlin
@Composable
private fun InspectorContent(selectedNavItem: StudioNavItem) {
    InspectorContentView(
        selectedNavItem = selectedNavItem,
        modifier = Modifier
            .fillMaxWidth()
            .fillMaxHeight(0.8f),
    )
}
```

Pass `viewModel.selectedNavItem` to `InspectorContent` call site in `PhoneLayout`.

---

## Future Extension — QUERY History & Favorites Tabs

When the Query tab is built, the QUERY inspector expands to 3 tabs:

```
[History] [Favorites] [Help]
```

**What's needed at that time:**
- Inject `HistoryRepository` and `FavoritesRepository` into `MainStudioViewModel` (they're already in Koin but not in the ViewModel)
- Expose `queryHistory: StateFlow<List<DittoQueryHistory>>` and `favorites: StateFlow<List<DittoFavorite>>`
- Add `InspectorHistoryContent.kt` — list of history entries, tap to load into editor
- Add `InspectorFavoritesContent.kt` — list of saved queries, tap to load into editor

The `InspectorContentView` switch case for `StudioNavItem.QUERY` grows from a single Help tab to a tabbed layout.

---

## Implementation Order

1. `gradle/libs.versions.toml` — add Markwon version + library entries
2. `app/build.gradle.kts` — add Markwon dependencies
3. `ui/mainstudio/inspector/HelpContentView.kt` — markdown viewer
4. `ui/mainstudio/inspector/InspectorContentView.kt` — context-aware dispatcher
5. `ui/mainstudio/MainStudioScreen.kt` — wire into `InspectorPanel` and `InspectorContent`
6. **Prerequisite:** centralized docs build pipeline must be complete so `assets/help/*.md` files exist

---

## Prerequisites

**The centralized docs pipeline (see `plans/android/centralized-help-docs-pipeline.md`) must be implemented first** so that `assets/help/*.md` files are present at build time.

The Gradle copy task from that plan creates `assets/help/` by copying from `docs/help/` at the repo root before every build. Without that, the `HelpContentView` falls back to "Documentation not found."

---

## Verification

1. `./gradlew assembleDebug` — clean build with Markwon
2. Open MainStudio → tap Inspector toggle → inspector opens
3. **Tablet:** inspector panel shows on the right, no "Coming Soon"
4. **Phone:** bottom sheet opens with help content
5. Switch between nav items → inspector content changes to the correct help file
6. Tap a link in the help content → opens in system browser
7. Scroll through long content (appmetrics.md, logging.md) — scrolls smoothly
8. Tables render correctly (subscription.md Peers List table)
9. Code blocks render in monospace font (query.md DQL examples)
