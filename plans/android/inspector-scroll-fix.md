# Inspector Help View — Scrolling Fix Plan

## Problem Statement

The Inspector panel's help content (`HelpContentView`) barely scrolls. Users cannot read
through help documentation because touch gestures produce no meaningful scroll movement.

---

## Root Cause Analysis

There are **two compounding causes**, both in `HelpContentView.kt`:

### Cause 1: No scroll container — content is clipped

`AndroidView` is given `.fillMaxSize()` and sits inside a `Column` slot with `.weight(1f)`.
Compose measures the `AndroidView` at bounded height (whatever space remains in the Column
after the header). The `TextView` inside measures at *that same bounded height* — it does not
expand to its natural content height.

Result: text that extends beyond the visible area is **clipped silently**. There is nothing to
scroll to because, from the View system's perspective, the `TextView` is already fully
displayed at its measured size.

### Cause 2: `LinkMovementMethod` absorbs touch events with nowhere to send them

`LinkMovementMethod` intercepts every touch event on the `TextView` so it can detect link
taps. Its `onTouchEvent()` processes the event and typically returns `true` (consumed). Since
there is no parent `ScrollView` to delegate non-link gestures to, scroll gestures are swallowed
and produce no movement.

This is the documented behaviour of `LinkMovementMethod` — it is designed for a `TextView` that
already lives inside a `ScrollView`, not for standalone rendering.

### Why it "barely" scrolls rather than not scrolling at all

Compose's `AndroidView` does emit minimal pointer events to the View in some edge cases, so the
user might see a tiny scroll flicker before the event is consumed. This is not a partial fix —
it is a symptom of the event being grabbed and dropped.

---

## Fix: Wrap `TextView` in `NestedScrollView`

The canonical solution for a Markwon/Markdown `TextView` inside Jetpack Compose is to use
`NestedScrollView` as the outer container inside the `AndroidView` factory.

### Why `NestedScrollView` specifically

- `NestedScrollView` implements `NestedScrollingChild3` and `NestedScrollingParent3`.
  These interfaces are Compose's interop bridge — they allow the Android View to participate
  in Compose's nested scroll system properly.
- `NestedScrollView` is a `ScrollView` variant, so it:
  - Measures the child `TextView` at **unbounded height** (content size, not screen size)
  - Handles vertical scroll internally via `FILL_VIEWPORT`
  - Delegates nested-scroll events upward to any Compose scroll ancestor if needed
- `LinkMovementMethod` continues to work for link clicks because tap events (no scroll
  delta) still reach the `TextView` through the `NestedScrollView`.

### `NestedScrollView` vs plain `ScrollView`

Plain `ScrollView` does not implement the `NestedScrollingChild3` interface. Inside Compose,
a plain `ScrollView` will scroll, but it will fight with Compose's touch handling — resulting
in jerky movement or the gesture being split between the two systems. `NestedScrollView` is the
correct choice for Compose interop.

---

## Implementation

### Only `HelpContentView.kt` needs to change

```kotlin
@Composable
fun HelpContentView(
    assetFileName: String,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current

    var markdown by remember { mutableStateOf("") }
    LaunchedEffect(assetFileName) {
        markdown = withContext(Dispatchers.IO) {
            runCatching {
                context.assets.open("help/$assetFileName").bufferedReader().readText()
            }.getOrDefault("# Help\n\nDocumentation not found.")
        }
    }

    val markwon = remember {
        Markwon.builder(context)
            .usePlugin(HtmlPlugin.create())
            .usePlugin(TablePlugin.create(context))
            .usePlugin(LinkifyPlugin.create())
            .build()
    }

    AndroidView(
        modifier = modifier.fillMaxSize(),           // padding moved to TextView below
        factory = { ctx ->
            NestedScrollView(ctx).apply {
                val tv = TextView(ctx).apply {
                    movementMethod = LinkMovementMethod.getInstance()
                    setTextIsSelectable(true)
                    val p = (16 * ctx.resources.displayMetrics.density).toInt()
                    setPadding(p, p, p, p)
                }
                addView(tv, ViewGroup.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                ))
            }
        },
        update = { sv ->
            val tv = sv.getChildAt(0) as TextView
            markwon.setMarkdown(tv, markdown)
        },
    )
}
```

**Key changes from current implementation:**

| Change | Reason |
|--------|--------|
| `NestedScrollView` wraps `TextView` | Provides a proper scroll container and Compose interop |
| `TextView` uses `WRAP_CONTENT` height | Allows it to expand to full content size inside `NestedScrollView` |
| `.padding(16.dp)` removed from `AndroidView` modifier | Padding moved to `TextView.setPadding()` — Compose padding on `AndroidView` clips the View's draw area, which can cut off scroll indicators |
| `modifier.fillMaxSize()` without padding | `NestedScrollView` fills available space; `TextView` inside is unbounded vertically |

### New imports required in `HelpContentView.kt`

```kotlin
import android.view.ViewGroup
import androidx.core.widget.NestedScrollView
```

`NestedScrollView` is in `androidx.core:core` which is already a transitive dependency of
`androidx.compose.ui:ui` — no new Gradle dependency is needed.

---

## Why not the alternatives?

### Alternative A: `ScrollingMovementMethod` instead of `LinkMovementMethod`

`ScrollingMovementMethod` makes the `TextView` scroll itself, but **breaks link clicks** — it
does not handle `MotionEvent.ACTION_UP` for link detection. All hyperlinks in the help docs
would become unclickable. Not acceptable.

### Alternative B: Compose-native Markdown library

Libraries like `com.mikepenz:multiplatform-markdown-renderer` render markdown as Compose
content (no `AndroidView` at all). This fully eliminates the interop problem.

This is a valid long-term direction, but adds a new library, requires removing Markwon, and
has less mature table rendering than Markwon 4.6. Not worth the churn for a scroll fix.

### Alternative C: `RecyclerView` + `MarkwonAdapter`

Markwon provides `io.noties.markwon:markwon-recycler` which splits markdown blocks into
`RecyclerView` items. This is the highest-performance option for very long documents, but:
- Requires an additional Markwon module
- `RecyclerView` inside a Compose `AndroidView` has its own height measurement challenges
- The help docs are 1.6–4.2 KB — far too small to justify a virtualized list

Not needed for this use case.

---

## Verification Steps

1. `./gradlew assembleDebug` — clean build
2. Open a database → tap the inspector toggle
3. Navigate to each nav item (SUBSCRIPTIONS, QUERY, OBSERVERS, LOGGING, APP_METRICS, QUERY_METRICS)
4. Verify:
   - Content scrolls smoothly to the bottom of each file
   - The longest file (`logging.md`, 4.2 KB) scrolls all the way to the end
   - Tap a hyperlink → opens in the system browser (link clicks still work)
   - On tablet: inspector side panel scrolls independently of the main content
   - On phone: bottom sheet scrolls without fighting the sheet drag gesture
5. Verify `subscription.md` table renders fully and is accessible by scrolling
6. Verify code blocks in `query.md` don't clip horizontally
