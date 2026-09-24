# Reordering pinned metrics

How drag-to-reorder works in the **Pinned** accordion on the System Metrics
screen, and — more importantly — the four ways it has already been broken.

Read this before touching `PinnedMetricsSection`, `ReorderablePinnedRow`, or
`SystemMetricsPinOrdering`. Every rule below cost a round of "still broken" to
learn, and none of them are visible from reading the code alone.

| Platform | Source |
|---|---|
| SwiftUI (macOS / iPadOS) | `SwiftUI/EdgeStudio/Views/Metrics/SystemMetricsDetailView.swift` |
| Android | `android/app/src/main/java/com/costoda/dittoedgestudio/ui/mainstudio/metrics/SystemMetricsScreen.kt` |
| Shared, pure logic | `SystemMetricsPinOrdering` (both platforms, same function names) |

---

## The mechanism

Reordering is an explicit **mode**, the Apple Music Edit-then-drag shape. A
`Reorder` / `Done` toggle in the Pinned header reveals a drag handle on every
row and suspends the screen's scrolling for the duration. The mode exists
because on a touch screen the enclosing scroll container wins a press-and-drag:
you scroll the page and the row never moves. Giving up the scroll is what hands
the gesture to the row.

**The same code path runs on every platform.** See [Rule 4](#rule-4).

While a drag is in flight:

1. The **committed order never changes.** `pins` is untouched from the moment
   the drag starts until the moment it ends.
2. The **dragged row** is drawn displaced by the pointer's full travel, lifted
   above its neighbours with a shadow so they cannot paint over it.
3. **Every row the drag has passed** slides one row height the other way,
   opening a gap where the dragged row will land.
4. On release, the order is committed **once** and persisted.

Two pure functions decide all of it, and both are unit-tested on both platforms:

```
dropIndex(startIndex:translation:heights:current:) -> Int
gapOffset(index:startIndex:dropIndex:draggedHeight:) -> CGFloat
```

`dropIndex` is anchored to the row centres of the list **as laid out when the
drag began**. Advancing needs the dragged row's centre to pass the *next* row's
centre; retreating needs it to fall behind the *previous* one. Between those two
anchors nothing changes — that gap is the dead zone, and it is what stops hand
tremor flicking the insertion point back and forth.

---

## The rules

### Rule 1 — Never measure the drag in the moving row's own coordinate space

**This is the one that will bite hardest, because everything compiles and the
bug looks like a performance problem.**

```swift
// ✅ correct
DragGesture(minimumDistance: 0, coordinateSpace: PinnedRowReorder.dragCoordinateSpace)

// ❌ the default, and a silent 50% bug
DragGesture(minimumDistance: 0)
```

`DragGesture.translation` is `location - startLocation`, measured in whichever
coordinate space you name. The default is `.local` — *this view's* space. But
this view is the one being moved by `.offset(y: translation)`, using the very
value the gesture reports. So the space the measurement is taken in shifts by
exactly the amount being measured:

```
translation = pointerMovement − offset
            = pointerMovement − translation

  ⟹  translation = pointerMovement / 2
```

The row tracks at **half** the pointer's speed and settles at an equilibrium
where further movement produces no progress.

How it presents: *"can't drag more than half way up, then it starts to stutter
and doesn't move past it."* It reads as a frame-rate problem. It is not. No
amount of profiling will find it, because nothing is slow.

Guarded by `SystemMetricsPinDragTests."the drag is measured in a space that does
not move with the row"`, which asserts `PinnedRowReorder.dragCoordinateSpace`.
The constant exists so the test has something to assert; do not inline the value
back into the gesture.

> This bug got **worse** as the implementation got better. An earlier version
> reset the offset to near zero after every swap, so the feedback stayed small
> and bounded. Letting the offset grow to the full drag distance — which is the
> correct design — let the error grow with it.

### Rule 2 — Never reorder the list while the drag is in flight

Rewriting the array on each crossing moves the dragged row's **view** to a
different slot in the `ForEach` / `LazyColumn`. Both frameworks tear down and
rebuild a view that changes position, and the active gesture dies with it.

How it presents: the drag works for a swap or two, then goes dead — you are
holding a button that nothing is listening to. Releasing and grabbing the row
again attaches a fresh gesture, so the second attempt works. *"I had to stop and
let go of the item and then click on it again to get it to go to the top."*

Android hit exactly this in `0bda9c3` (a missing `key()` re-identified rows by
slot); SwiftUI hit it later for the same underlying reason. Hence the gap: the
list stays still, and only the offsets change.

### Rule 3 — A swap threshold must leave a dead zone

An earlier version swapped when the row travelled half the **neighbour's**
height, then absorbed the neighbour's **full** height. That leaves the row
sitting at exactly `-h/2` — precisely on the threshold to swap straight back.
Zero dead zone, so ordinary hand tremor flips the rows continuously.

Simulated over a slow three-row drag: ±1pt of tremor produced 7 swaps and 4
direction reversals; ±2pt produced 15 and 12.

The current design sidesteps this entirely — `dropIndex` compares against
*fixed* anchors, so the dead zone falls out of the geometry rather than needing
to be engineered. Keep it that way. If you ever reintroduce incremental swapping,
the threshold must account for **both** rows' half-heights, not just one.

### Rule 4 — Do not split this by platform

There was an attempt to give macOS its own AppKit drag-and-drop path
(`onDrag`/`onDrop` with a `DropDelegate` and an insertion line) while iPadOS kept
the handle drag. It was deleted.

The idea was defensible — native drag-and-drop is smooth and idiomatic on
macOS — but every `#if os(macOS)` branch is a place where one platform silently
loses behaviour the other keeps. In the two days it existed it did exactly that,
twice:

- the Reorder toggle and drag handle were in the iOS branch, so **macOS lost the
  affordance entirely** — reordering appeared to vanish from the app;
- the `.offset(y:)` that draws the moving row was in the iOS branch, so macOS
  computed the displacement and discarded it — **the drag rendered nothing at
  all**, no moving row, no feedback.

Both compiled cleanly. Both passed the test suite. One shared path, exercised on
every platform, is worth more here than a per-platform ideal.

The only `#if` in the file is a pre-existing one on the search field's
autocorrect, and it is unrelated.

### Rule 5 — Heights are measured, and zero means "not yet"

Row heights differ (a label line, an expanded detail panel), so the crossing
points come from a `GeometryReader` / `onGloballyPositioned` measurement, keyed
by **series id, not index**.

Measurements arrive a frame or two late. Both `dropIndex` and `gapOffset` treat
a zero height as "not measured" and decline to act, rather than resolving
against a zero-height layout and teleporting the row.

---

## Testing

Pure logic, so it is genuinely unit-testable on both platforms — and the tests
are mirrored deliberately, function for function.

| | SwiftUI | Android |
|---|---|---|
| File | `SwiftUI/EdgeStudioUnitTests/Metrics/SystemMetricsPinDragTests.swift` | `android/app/src/test/.../SystemMetricsPinDragTest.kt` |
| Tests | 14 | 12 |

They cover:

- **a full-length drag** — seven rows, bottom to top, in one gesture (Rule 2's
  regression case);
- **a single large jump**, since gesture updates can skip several rows at once;
- **tremor** at ±1/2/4/8pt, asserting the insertion point never flicks back and
  forth (Rule 3);
- **mixed row heights**, resolving against each row's own centre;
- **unmeasured rows** leaving the slot alone (Rule 5);
- **the gap offsets** in both directions;
- **the coordinate space** (Rule 1).

What the tests *cannot* catch: Rule 1 and Rule 2 are properties of a live
gesture in a real view hierarchy. The coordinate-space test asserts a constant,
which guards the specific known regression but would not catch a *new* way of
reintroducing feedback. **Any change to the drag needs a manual pass with a
mouse on macOS**, dragging the bottom row of a long list all the way to the top.
That single gesture exercises Rules 1, 2 and 3 at once, and every bug listed here
would have been caught by it in seconds.

---

## Debugging guide

| Symptom | Almost certainly |
|---|---|
| Row tracks slowly, stalls part way, judders at the stall point | **Rule 1** — coordinate space feedback |
| Drag dies after a swap or two; works again after re-grabbing | **Rule 2** — the list reordered under the gesture |
| Rows flip back and forth continuously under the cursor | **Rule 3** — no dead zone in the threshold |
| Nothing moves at all; no visual feedback | **Rule 4** — a platform branch dropped the displacement |
| Row teleports on the first pixel of movement | **Rule 5** — resolved against unmeasured heights |

Worth saying plainly: the first three all look like stuttering, and the first
instinct is to profile. Rendering here costs **0.5–0.7 ms/frame** with every
modifier attached, measured by ablating `contextMenu`, `shadow`,
`GeometryReader` and `zIndex` in a hosted window. Performance has never been the
problem on this screen. Check the table above before optimising anything.
