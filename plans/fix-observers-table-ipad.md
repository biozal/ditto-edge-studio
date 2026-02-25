# Fix: Observer Events Table — iPad Header Text Wrapping

## Status
READY TO IMPLEMENT

## Screenshot Evidence

`screens/observers-table-ipad.png` shows the header row rendering as:

```
Time | Count | In-    | Updat- | Delet- | Moves
            | serted | ed     | ed     |
```

The header cells for "Inserted", "Updated", and "Deleted" are hyphenating and wrapping
to a second line. Data rows are correct — only the header is broken.

---

## Root Cause — Two Compounding Problems

### Problem 1: `.lineLimit(1)` missing from iOS header cells

Data row cells already have it (line 94):
```swift
Text(values[colIdx])
    .font(.system(.body, design: .monospaced))
    .lineLimit(1)                              // ← present on data rows
    .frame(width: columnDefs[colIdx].width, ...)
```

iOS header cells are missing it (lines 116–121):
```swift
Text(columnDefs[colIdx].header)
    .font(.system(.headline, design: .monospaced))
    // ← .lineLimit(1) MISSING — allows wrapping
    .frame(width: columnDefs[colIdx].width, ...)
```

Without `.lineLimit(1)`, SwiftUI wraps long words with hyphens inside the fixed frame.

### Problem 2: Column widths are too narrow for iPad's headline font

The shared `columnDefs` uses widths designed for macOS (where `.headline` is ~13pt):

| Column   | Width | Padding | Usable | macOS headline (~13pt) | iPad headline (17pt) |
|----------|-------|---------|--------|------------------------|----------------------|
| Inserted | 80    | 16      | 64px   | ~8 chars × 7.8px = 62px ✅ | ~8 chars × 10.2px = 82px ❌ |
| Updated  | 80    | 16      | 64px   | ~7 chars × 7.8px = 55px ✅ | ~7 chars × 10.2px = 71px ❌ |
| Deleted  | 70    | 16      | 54px   | ~7 chars × 7.8px = 55px ❌* | ~7 chars × 10.2px = 71px ❌ |
| Count    | 70    | 16      | 54px   | ~5 chars × 7.8px = 39px ✅ | ~5 chars × 10.2px = 51px ✅ |
| Moves    | 70    | 16      | 54px   | ~5 chars × 7.8px = 39px ✅ | ~5 chars × 10.2px = 51px ✅ |

*macOS headline is actually fine because `.headline` resolves to the system headline which is
smaller on macOS than iOS; observed as no issue on macOS.

Even after adding `.lineLimit(1)`, "Inserted" (82px) won't fit in 64px and will truncate to
"Insert..." — still readable but not ideal. "Deleted" (71px) also won't fit in 54px.

---

## Fix

**File:** `SwiftUI/Edge Debug Helper/Components/ObserverEventsTableView.swift`

Two minimal changes — iOS only.

### Change 1 — Add `.lineLimit(1)` to iOS header cells

```swift
// BEFORE
Text(columnDefs[colIdx].header)
    .font(.system(.headline, design: .monospaced))
    .frame(width: columnDefs[colIdx].width, alignment: .leading)
    .padding(.horizontal, 8)
    .padding(.vertical, 8)
    .background(Color(UIColor.systemBackground))

// AFTER
Text(columnDefs[colIdx].header)
    .font(.system(.headline, design: .monospaced))
    .lineLimit(1)
    .frame(width: columnDefs[colIdx].width, alignment: .leading)
    .padding(.horizontal, 8)
    .padding(.vertical, 8)
    .background(Color(UIColor.systemBackground))
```

### Change 2 — Use platform-specific column widths

Split `columnDefs` into `#if os(macOS)` / `#else` so iOS gets wider columns for the
problematic headers. iPad has ample horizontal space (800–1000pt detail pane).

```swift
// BEFORE — single shared definition
private let columnDefs: [(header: String, width: CGFloat)] = [
    ("Time", 180), ("Count", 70), ("Inserted", 80),
    ("Updated", 80), ("Deleted", 70), ("Moves", 70)
]

// AFTER — platform-aware widths
#if os(macOS)
private let columnDefs: [(header: String, width: CGFloat)] = [
    ("Time", 180), ("Count", 70), ("Inserted", 80),
    ("Updated", 80), ("Deleted", 70), ("Moves", 70)
]
#else
private let columnDefs: [(header: String, width: CGFloat)] = [
    ("Time", 200), ("Count", 80), ("Inserted", 100),
    ("Updated", 100), ("Deleted", 90), ("Moves", 80)
]
#endif
```

iOS widths chosen so every header fits without truncation at 17pt monospaced:
- "Inserted" (8 chars × 10.2px = 82px) fits in 100px − 16px padding = 84px ✅
- "Updated"  (7 chars × 10.2px = 71px) fits in 100px − 16px = 84px ✅
- "Deleted"  (7 chars × 10.2px = 71px) fits in 90px − 16px = 74px ✅

---

## Files to Change

| File | Change |
|------|--------|
| `Components/ObserverEventsTableView.swift` | Add `.lineLimit(1)` to iOS header; split `columnDefs` by platform |

---

## Verification

1. Build macOS + iOS
2. On iPad simulator: open Observers → activate an observer → verify:
   - Column headers show on **one line**: Time, Count, Inserted, Updated, Deleted, Moves ✅
   - No hyphenation or wrapping in any header cell ✅
   - Data rows still align correctly under each header ✅
3. On macOS: verify no change to appearance (macOS keeps original widths) ✅
