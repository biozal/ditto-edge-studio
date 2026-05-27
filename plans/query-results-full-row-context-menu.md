# Query Results: Full-Row Context Menu + Copy _id

**Status:** Plan
**Date:** 2026-05-26
**Owner:** Aaron LaBeau

## What we're solving

Two separate but identical-rooted UX bugs in the Query Results pane, plus
one new menu item.

1. **JSON viewer right-click is dead on the JSON text itself.** Right-click
   in the empty padding to the right of the text gives the full app menu
   (Copy Document, Add Attachment…, Delete Attachment…). Right-click ON
   the text gives nothing useful. Plain click on the text doesn't open
   the JSON Inspector either — only clicks in the padding area do.
2. **Table viewer right-click only works on the row-number column.**
   Right-click on column 2+ (the data cells) gives nothing useful;
   right-click on the first column gives the full app menu.
3. **No way to copy just `_id`.** Users frequently want a peer key /
   document ID for a follow-up query or to paste into a tracking tool.
   Today the only options are "Copy Document" (full JSON) or manually
   selecting the value out of the displayed JSON.

The Add Attachment workflow is a load-bearing feature for the app —
it has to be one right-click away from any cell on any displayed
document.

## Root cause

Both #1 and #2 are the same bug, expressed in two places:

```swift
Text(value)
    .textSelection(.enabled)       // ← consumes right-click events
```

On macOS, `.textSelection(.enabled)` makes the Text view participate in
text selection by hosting an `NSTextView` under the hood. That
`NSTextView` claims all pointer events inside its bounds — including
right-click — and presents the system's text-selection context menu
(Copy / Look Up / Speech / …), which has none of the app's actions and
isn't compatible with overrides from a parent `.contextMenu` modifier.
The parent's `.contextMenu` only fires when the right-click lands on a
pixel **outside** any `.textSelection(.enabled)` Text — i.e. the
padding area to the right of the JSON, or the row-number column whose
Text doesn't enable selection.

Confirming the pattern in the code:

- `ResultJsonViewer.swift:205-211` — `Text(jsonString) … .textSelection(.enabled)`
  inside the row, with the row's `.contextMenu` attached to the parent
  `LazyVStack` (`:226`).
- `ResultTableViewer.swift:99-105` (macOS) and `:199-205` (iOS) —
  `Text(cellValue.displayValue) … .textSelection(.enabled)` inside
  each data cell, with `.contextMenu` attached to the row's `HStack`
  (`:125`, `:222`). The row-number column at `:84-90` (macOS) /
  `:188-193` (iOS) doesn't enable selection, which is why *that*
  column works.

## Fix

Drop `.textSelection(.enabled)` from the row-display Texts in both
viewers. The row then becomes a single uniform hit target for tap +
context menu, and right-click works everywhere on the row.

This is also the right *design* call, not just the cheapest fix.
Fine-grained character selection is an Inspector-level concern — the
JSON Inspector pane (driven by `onJsonSelected` on row tap) already has
its own selectable text view for users who need to copy specific
substrings. The Query Results pane should be optimized for row-level
operations (copy whole document, copy _id, add/delete attachment).

## Detailed changes

### 1. Extract a shared row-context-menu builder

**New file:** `SwiftUI/EdgeStudio/Components/QueryResultRowMenu.swift`

A single `@ViewBuilder` that both viewers call, so the menu can't drift
between JSON and Table modes:

```swift
@ViewBuilder
func queryResultRowMenu(
    json: String,
    hasAttachments: Bool,
    onCopyDocument: @escaping () -> Void,
    onCopyId: @escaping () -> Void,
    onAddAttachment: @escaping () -> Void,
    onDeleteAttachment: @escaping () -> Void
) -> some View {
    Button {
        onCopyDocument()
    } label: {
        Label("Copy Document", systemImage: "doc.on.doc")
    }
    Button {
        onCopyId()
    } label: {
        Label("Copy _id", systemImage: "number")
    }
    Divider()
    Button {
        onAddAttachment()
    } label: {
        Label("Add Attachment…", systemImage: "paperclip")
    }
    Button {
        onDeleteAttachment()
    } label: {
        Label("Delete Attachment…", systemImage: "trash")
    }
    .disabled(!hasAttachments)
}
```

Both call sites collapse from ~18 lines of menu Buttons to a single
`queryResultRowMenu(json:, hasAttachments:, …) { … }` call inside
`.contextMenu { … }`.

### 2. `_id` extraction helper

Same file, top-level:

```swift
/// Parse `_id` out of a JSON document string and return a clipboard-
/// safe representation.
///
/// `_id` is typically a `String` but Ditto also supports composite
/// keys (`{ "a": 1, "b": "x" }`) and integer keys. Strings are returned
/// raw; everything else is re-encoded to JSON so the value round-trips
/// (paste it into a `WHERE _id = …` clause and it parses).
func extractIdString(fromJSON jsonString: String) -> String? {
    guard let data = jsonString.data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let id = obj["_id"]
    else {
        return nil
    }
    if let stringId = id as? String { return stringId }
    if let nsnum = id as? NSNumber { return nsnum.stringValue }
    // Composite/object keys: re-encode so it pastes back as valid JSON.
    if let data = try? JSONSerialization.data(withJSONObject: id, options: [.sortedKeys]),
       let s = String(data: data, encoding: .utf8) {
        return s
    }
    return String(describing: id)
}
```

`Optional` return so callers can fall back to a toast / no-op if `_id`
is missing (defensive — system documents have it; user docs always do
in DQL but ad-hoc JSON might not).

### 3. `ResultJsonViewer.swift`

- **Drop `.textSelection(.enabled)`** at `:211` on the row Text.
- **Replace the inline menu** at `:226-244` with
  `queryResultRowMenu(...)` from the helper.
- **Wire `onCopyId`** to a new `copyIdToClipboard()` method on
  `ResultItem` that calls `extractIdString(fromJSON: jsonString)` and
  pushes the result through the same `NSPasteboard` / `UIPasteboard`
  path the existing `copyToClipboard()` uses. Show the same green
  checkmark transient indicator (`isCopied`) so users get feedback
  identical to "Copy Document".

### 4. `ResultTableViewer.swift`

Same shape, twice — there's a macOS table view and an iPadOS table view,
each with its own row HStack.

- **Drop `.textSelection(.enabled)`** in both cell branches:
  - `:104` (macOS data cells, inside `if let cellValue = …`).
  - `:204` (iPadOS data cells).
- **Replace the inline menus** at `:125-143` (macOS) and `:222-240`
  (iPadOS) with `queryResultRowMenu(...)`.
- **Wire `onCopyId`** — table rows already expose `row.originalJson`,
  so `extractIdString(fromJSON: row.originalJson)` works the same way.
  Optionally short-circuit: if `row.cells["_id"]?.displayValue` is
  present, use it directly to avoid re-parsing JSON — but only if it
  matches the JSON parse result, otherwise we could leak a stringified
  composite key. Simpler: just call `extractIdString` and stay
  consistent with the JSON viewer.

### 5. Tap behavior unchanged

The single-tap behaviors (JSON viewer: copy + send to inspector; table
viewer: double-tap to copy whole row) keep working because removing
`.textSelection(.enabled)` also removes the NSTextView that was
intercepting taps. We may even pick up a small bonus: single-click on
the JSON text body will now invoke the row's `onTapGesture` and open
the Inspector, which it doesn't today.

## Trade-offs

**What users lose:** the ability to drag-select specific characters
inside the rendered JSON in the Query Results pane.

**Why it's still the right call:**

- The JSON Inspector (opened on row tap) already provides selectable
  text for users who need fine-grained extraction.
- The new "Copy _id" covers the single most common targeted-copy case.
- "Copy Document" covers the rest — the displayed text is a redacted
  preview anyway (cells are `.lineLimit(3)`-truncated in the table).
- The current behavior surprises users (right-click on text → wrong
  menu) more than it helps them.

If anyone misses character selection in the row display, the followup
move is a "Copy field…" submenu listing every top-level key with its
value — but that's a separate, larger feature, not a blocker for this
fix.

## Verification

- [ ] In JSON mode: right-click anywhere on a row — on the text, on the
      padding, on the check icon side — produces the full menu (Copy
      Document, Copy _id, Add Attachment…, Delete Attachment…).
- [ ] In JSON mode: single-click on the text body sends JSON to the
      Inspector (matches what padding-click does today).
- [ ] In Table mode (macOS): right-click on any data column produces
      the same menu. Row-number column still works (regression check).
- [ ] In Table mode (iPadOS): same as macOS table check.
- [ ] "Copy _id" copies the raw string for string-valued _ids, the
      digits for numeric _ids, and JSON for composite-key _ids.
      Verify the copied value pastes back into a DQL `WHERE _id = …`
      clause without re-quoting.
- [ ] Existing UI tests still green — no accessibility identifiers
      changed.
- [ ] Build clean on macOS and iPadOS Simulator per CLAUDE.md.

## Out of scope

- Field-level "Copy field…" submenu (potential v1.1 feature).
- Right-click on result-pane *headers* (sort, hide column, etc.) —
  the user only asked for body-row context-menu parity.
- Touch-and-hold context menu on iPadOS — already works via
  `.contextMenu` and the fix to `.textSelection(.enabled)` resolves it
  for table cells too.

## Files touched

- New: `SwiftUI/EdgeStudio/Components/QueryResultRowMenu.swift` (~60 lines)
- Modified: `SwiftUI/EdgeStudio/Components/ResultJsonViewer.swift`
  (~10 lines changed, ~15 removed)
- Modified: `SwiftUI/EdgeStudio/Components/ResultTableViewer.swift`
  (~20 lines changed, ~30 removed across two table layouts)
