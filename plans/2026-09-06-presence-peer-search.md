# Plan — Presence Viewer peer search (SwiftUI + Android)

**Status:** implemented on branch `pv-search` (2026-09-06) — **awaiting the
multi-peer manual pass in §9**, which is the only thing that can confirm the
end-to-end behaviour. See §12 for what was verified and what was not.
**Date:** 2026-09-06
**Platforms:** SwiftUI (macOS/iPadOS), Android (phone/tablet/fold)
**Reference implementation:** `~/Developer/ditto-vsc-es`, commit `2124682`
("Add peer search and peer detail card to the Presence Graph")

---

## 1. Goal

Let the user find a peer in a mesh of 100+ peers by typing part of its device
name or peer ID, and jump straight into that peer's focused-neighbourhood view.
The search box must cost the canvas **no vertical space** — it rides in the same
row as the Peers/Viewer tab selector, exactly like the VS Code extension.

The peer **detail card** half of that VS Code commit is already ported to both
platforms (`PeerDetailCardView.swift`, `PeerDetailCard.kt`). This plan covers
only the **search** half.

---

## 2. Reference behaviour (the contract)

Read directly from the extension source. These are the acceptance criteria; the
numbered items are referenced from the test and manual-verification sections.

Source files:
- `webview-ui/peers/peers-element.ts` — search box, results card, candidate set,
  matching, Enter/Escape, result-click routing (lines ~100–120, 244, 431–520,
  917–950, 1039–1069, 1341–1460).
- `webview-ui/presence-graph/presence-graph-element.ts` — `searchMatchKeys`
  property, `focusPeer()`, pending-focus-across-mode-flip (lines 45–48, 105,
  435–455, 482–545).
- `webview-ui/presence-graph/scene.ts` — `setSearchMatches()`, `focusForPeer()`,
  `focusForLine()` (lines 55–73, 136, 593, 770–805).
- `resources/help/presence.md` — user-facing description.
- `docs/MANUAL_TESTING.md` step 13 — manual script.

| # | Behaviour |
|---|---|
| **B1** | The search box sits in the tab row, right-aligned after the tab selector, and is shown **only** while the Presence Viewer tab is selected. It takes no row of its own. |
| **B2** | Placeholder: `Search peers by name or ID…`. Accessibility label: `Search peers in the mesh`. |
| **B3** | Matching is **case-insensitive substring** over two fields: device name and peer key. Query is trimmed. |
| **B4** | Candidate set is the **full mesh**, not the mode-filtered graph — a multi-hop peer must be findable while **Direct** is ON, because picking it is exactly how the user jumps the graph to it. |
| **B5** | Candidate order: remote peers (graph order), then the synthetic **Ditto Cloud** node (only when a cloud link exists), then the **local device last**. Duplicates suppressed by key. |
| **B6** | While a query is active, matching peers **and every connection touching a match** stay at full opacity; everything else takes the same dimming a click selection gives. |
| **B7** | Search is the **weakest** focus source. An explicit focus/selection (and hover, where the platform dims on hover) wins over it. Clearing the query restores full opacity everywhere. |
| **B8** | Results are listed in a card that **drops down over the canvas** — the graph never reflows while typing. The card scrolls; it does not grow without bound. |
| **B9** | Each result row shows the device name (or `(unnamed)`) and a truncated peer key (24 chars + `…`). |
| **B10** | The local device is **listed but not clickable**, tagged `(this device)`, with the tooltip/description "The local device cannot be focused". The scene deliberately rejects focusing the local peer. |
| **B11** | Clicking a result focuses that peer exactly as a full-mesh pill click would — **including flipping Direct OFF first** when it is on, then focusing once the rebuilt full-mesh graph contains the peer. |
| **B12** | Picking the currently focused peer again **toggles focus off** (same as re-clicking its pill). Any open detail card must be cleaned up on that path. |
| **B13** | **Enter** focuses the first focusable (non-local) match. IME composition is ignored. |
| **B14** | The query is **deliberately kept** after picking a result, so the user can hop between results. |
| **B15** | A zero-hit query shows `No peers match “<query>”` and **dims the whole graph** — "nothing here" is useful feedback. (Implementation: active-with-no-hits is an *empty set*, never "inactive".) |
| **B16** | **Escape** (or the platform's back gesture) unwinds the innermost context first: an open detail card, *then* the search query. It works wherever focus is inside the panel, including on a result row just clicked. The focus view itself is untouched by either step. |
| **B17** | Query and its dimming **survive a Peers ↔ Viewer tab switch** (the graph view is torn down and rebuilt; the query is owned above it and re-applied to the fresh scene). |

---

## 3. What already exists (no need to build)

**SwiftUI**
- `Views/StudioView/Details/DetailViews.swift` — `syncTabsDetailView()` owns the
  header row: `Text("Presence")` + `DittoSegmentedPicker(["Peers","Viewer"])` +
  `TransportSettingsButton`, inside a `ViewThatFits`.
- `Views/StudioView/Details/PresenceViewerSK.swift` —
  `PresenceViewerSK.ViewModel` (hoisted to `MainStudioView` as `@State`) already
  owns `showDirectConnectedOnly`, `focusedPeerKey`, `detailPeerKey`,
  `controlsVisible`, and holds `rawRemotePeers` / `rawLocalPeer` = the
  **unfiltered** presence graph. `updateSceneWithCurrentFilter()` already
  re-enters a hoisted focus after a scene rebuild via
  `scene.restoreFocusAfterRebuild(for:)`.
- `Components/PresenceViewer/PresenceNetworkScene.swift` — focus mode, the
  tap-to-isolate highlight, and two authoritative resting-alpha functions:
  `restingAlpha(for line:)` and `restingAlpha(forPeerKey:)` (lines 727–752),
  plus `applyFocus()` / `restoreAllAlpha()` (1012–1066). Cloud key is
  `"ditto-cloud-node"` (line 90).

**Android**
- `ui/mainstudio/PresenceSection.kt` — `PresenceContentSection` owns the header
  `Row`: `DittoConnectedButtonGroup(["Peers","Viewer"])` + optional
  Subscriptions button + transport gear.
- `viewmodel/MainStudioViewModel.kt` — already hoists
  `showDirectConnectedOnly`, `presenceControlsVisible`,
  `presenceFocusedPeerId` (+ `setPresenceFocusedPeer`).
- `ui/mainstudio/presence/PresenceGraphView.kt` — focus mode, selection
  dimming, and a `LaunchedEffect(focusedPeerId, showDirectConnectedOnly,
  sceneSizePx)` that re-enters focus after a rebuild. Alpha decisions are two
  pure `when` blocks inside `drawBehind` (lines ~826 for edges, ~888 for pills).
  A `BackHandler` already dismisses the open detail card.
- `PeersUiState.Active.meshTopology.peers` is the **full mesh** (populated for
  indirect peers) — the direct analogue of the extension's
  `presenceGraph.remotePeers`. Cloud key is `CLOUD_NODE_KEY = "ditto-cloud-node"`.

---

## 4. Shared design decisions

**D1 — Nil vs empty set.** `searchMatchKeys` is `nil`/`null` when the box is
empty (no dimming) and an **empty set** when the query has no hits (everything
dims). Conflating the two breaks B15. This is the single most likely bug.

**D2 — Dim constants.** Do **not** import the extension's `0.25 / 0.08`. The
extension's own help text defines the search treatment as "the same treatment a
click selection gives", and `UNRELATED_PEER_ALPHA` *is* its selection dim. So
each platform reuses its **existing selection dim**: SwiftUI
`focusDimPeerAlpha = 0.35` / `focusDimEdgeAlpha = 0.2`; Android `0.35f` / `0.2f`.
This is faithful parity, not a deviation.

**D3 — Precedence.** Resting alpha resolves in this order:
`focus mode → click selection → search → 1.0`. Search never overrides the other
two (B7).

**D4 — Query ownership.** The query lives one level **above** the graph view, in
the same object that already survives the tab switch (`PresenceViewerSK.ViewModel`
on SwiftUI, `MainStudioViewModel` on Android). Required by B17.

**D5 — Pending focus.** A search pick while Direct is ON cannot focus
immediately: the peer is not in the scene yet. Store a `pendingFocusPeerKey`,
flip Direct off, and consume the pending key when the rebuilt full-mesh graph
has placed the peer. Mirrors the extension's `pendingFocusKey`.

**D6 — Results card overlays, never reflows** (B8). It must not be inside the
layout flow of the canvas.

**D7 — Scale.** 100+ peers. Matching is O(n) per keystroke over a ≤few-hundred
item list; no debounce needed. Memoize the candidate list per presence push
(`derivedStateOf` on Android; a cached computed property on SwiftUI) rather than
rebuilding it per character. Cap the results card height and make it scroll.

---

## 5. SwiftUI implementation

### 5.1 Scene — teach it about search matches

`Components/PresenceViewer/PresenceNetworkScene.swift`

1. Add stored state + setter:
   ```swift
   /// Peer keys matching the panel's search box; nil when the box is empty,
   /// EMPTY when the query has no hits (which dims the whole graph — B15).
   /// The weakest focus source: focus mode and the click selection both win.
   private(set) var searchMatchKeys: Set<String>?

   func setSearchMatches(_ keys: Set<String>?) {
       guard keys != searchMatchKeys else { return }
       searchMatchKeys = keys
       reapplyRestingAlpha()
   }
   ```
2. Extend **both** `restingAlpha` functions (lines 727–752) with a search branch
   **after** the `focusedPeerKey` and `highlightedNode` branches (D3):
   - peer: `searchMatchKeys.contains(key) ? 1.0 : focusDimPeerAlpha`
   - line: `matches.contains(from) || matches.contains(to) ? 1.0 : focusDimEdgeAlpha`
3. Add `reapplyRestingAlpha()` — fades every node and line to its
   `restingAlpha(...)` over `focusFadeDuration`, using the existing `"focusFade"`
   action key and removing `"lineDrawAnimation"` / `"appearAnimation"` first
   (same pattern as `applyFocus()`).
4. **Rewrite `restoreAllAlpha()` to fade to `restingAlpha(...)` instead of a
   hard `1.0`.** As written it would blow away an active search dim whenever a
   selection or focus is cleared. This is the "graph gets stuck un-dimmed"
   failure mode.
5. Call `reapplyRestingAlpha()` from `refreshFocusAfterTopologyChange()` so peers
   joining/leaving mid-query inherit the correct dim (the existing
   `animatePeerAppearance` / `animateLineDrawing` already fade *to*
   `restingAlpha`, so they need no change once step 2 lands).

### 5.2 ViewModel — query, candidates, focus routing

`Views/StudioView/Details/PresenceViewerSK.swift` → `PresenceViewerSK.ViewModel`

```swift
var searchQuery: String = "" { didSet { pushSearchMatchesToScene() } }
private var pendingFocusPeerKey: String?

struct SearchMatch: Identifiable, Equatable {
    var id: String { key }
    let key: String
    let name: String
    let isLocal: Bool
}

var searchIsActive: Bool            // trimmed query non-empty
var searchMatches: [SearchMatch]    // B3/B4/B5, memoized per presence push
func focusSearchResult(_ key: String)   // B11/B12
func focusFirstSearchResult()           // B13 — first non-local match
func clearSearch()                      // B16 step 2
```

- **Candidates (B4/B5):** `rawRemotePeers` (already the unfiltered graph) →
  `SearchMatch(key: $0.peerKeyString, name: $0.deviceName, isLocal: false)`;
  then `"ditto-cloud-node"` / `"Ditto Cloud"` when
  `rawLocalPeer.isConnectedToDittoCloud`; then `rawLocalPeer` last with
  `isLocal: true`. Dedupe by key, skip empty keys.
- **Cache:** rebuild the candidate array in `updateSceneWithCurrentFilter()`
  (the 250 ms-throttled push point), not on every keystroke.
- **`pushSearchMatchesToScene()`:**
  `scene?.setSearchMatches(searchIsActive ? Set(searchMatches.map(\.key)) : nil)`.
  Also call it at the end of `updateSceneWithCurrentFilter()` so a rebuilt scene
  gets the live query re-applied (B17 — the scene dies on tab switch, the VM
  does not).
- **`focusSearchResult(key:)` (B11/B12):**
  ```
  if showDirectConnectedOnly {
      pendingFocusPeerKey = key
      showDirectConnectedOnly = false     // didSet → updateSceneWithCurrentFilter()
      return
  }
  if key == focusedPeerKey { exitFocusMode(); return }   // B12 — takes the card with it
  detailPeerKey = nil; scene?.hasOpenDetailCard = false
  scene?.restoreFocusAfterRebuild(for: key)
  ```
- Consume `pendingFocusPeerKey` at the **end** of `updateSceneWithCurrentFilter()`,
  after `scene.updatePresenceGraph(...)` has placed the peer — guard on the peer
  actually existing, and clear the pending key unconditionally so a departed peer
  cannot leave it armed forever.

### 5.3 View — the field and the results card

New file **`Components/PresenceViewer/PresencePeerSearchField.swift`**
(create with **XcodeWrite**, per `CLAUDE.md` — it must land in the target).

```swift
struct PresencePeerSearchField: View {   // reads the VM internally — see below
    @Bindable var viewModel: PresenceViewerSK.ViewModel
    ...
}
```

- `TextField("Search peers by name or ID…", text: $viewModel.searchQuery)`,
  `.textFieldStyle(.roundedBorder)`, `.frame(width: 260)` with
  `.frame(minWidth: 140, maxWidth: 300)`, `.onSubmit { viewModel.focusFirstSearchResult() }`
  (B13), `.accessibilityIdentifier("PresencePeerSearchField")`,
  `.accessibilityLabel("Search peers in the mesh")`.
- Results card as **`.overlay(alignment: .topTrailing)` on the field itself**,
  offset down by the field height + 4, `.fixedSize()`, `.zIndex(1)` (D6/B8).
  - **Not** a `.popover`: on macOS a popover takes key focus away from the
    `TextField`, which kills type-ahead.
  - `ScrollView` + `LazyVStack`, `.frame(width: 320, maxHeight: 224)`,
    `.background(.regularMaterial)`, `.clipShape(.rect(cornerRadius: 6))`,
    shadow.
  - Rows: `Button` for focusable matches; a plain non-interactive `HStack` for
    the local row with the `(this device)` tag (B10). Name leading (truncating
    tail), truncated key trailing in `.monospaced` `.caption2` `.secondary`.
  - Empty state: `No peers match “<query>”`, italic secondary (B15).
  - `.accessibilityIdentifier("PresencePeerSearchResults")`, rows
    `"PresenceSearchResult_<key>"`.

Wire-up in **`DetailViews.swift` → `syncTabsDetailView()`**:

- Insert `if selectedSyncTab == 1 { PresencePeerSearchField(viewModel: presenceViewerVM) }`
  into the header row, **after** the picker, before `TransportSettingsButton`.
- ⚠️ **Two constraints from `CLAUDE.md` apply here and both are load-bearing:**
  1. *"No dynamic data inside `ViewThatFits`"* — and the field is dynamic. The
     existing comment (DetailViews.swift:9–11) records a real
     `onChange(of: Layout)` feedback loop. Put the field **outside** the
     `ViewThatFits`, in the enclosing `HStack`, so `ViewThatFits` keeps measuring
     only static content.
  2. `DittoSegmentedPicker` **refuses to be squeezed** (`EqualWidthSegments`
     never reports less than `count × widest segment`). A field in the same row
     will therefore push the picker rather than shrink it. Give the field
     `.layoutPriority(-1)` and a `minWidth`, and verify the narrow branch on
     iPad and on a narrow macOS window.
- ⚠️ `syncTabsDetailView()` is a **method on `MainStudioView`**, so anything it
  *reads* becomes a dependency of `MainStudioView.body` — the exact trap
  documented at DetailViews.swift:54–58. The header must reference
  `PresencePeerSearchField(viewModel:)` and **never read
  `presenceViewerVM.searchQuery` inline**. All query reads happen inside the
  leaf view.
- Escape (B16): add `.onExitCommand` (macOS) / an `.onKeyPress(.escape)` on the
  detail container that runs *card first, then query*:
  ```
  if viewModel.detailPeerKey != nil { viewModel.dismissDetail() }
  else if viewModel.searchIsActive { viewModel.clearSearch() }
  ```
  On iPadOS the `TextField`'s own clear button plus the hardware-keyboard
  `.onKeyPress` cover it.

---

## 6. Android implementation

### 6.1 ViewModel — hoisted query + pending focus

`viewmodel/MainStudioViewModel.kt`, alongside `presenceFocusedPeerId` (D4):

```kotlin
private val _presenceSearchQuery = MutableStateFlow("")
val presenceSearchQuery: StateFlow<String> = _presenceSearchQuery.asStateFlow()
fun setPresenceSearchQuery(q: String) { _presenceSearchQuery.value = q }

/** Armed by a search pick that had to flip Direct off first; consumed by
 *  PresenceGraphView once the rebuilt full-mesh layout has placed the peer. */
private val _presencePendingFocusPeerId = MutableStateFlow<String?>(null)
val presencePendingFocusPeerId: StateFlow<String?> = _presencePendingFocusPeerId.asStateFlow()
fun requestPresenceFocus(peerId: String?) { _presencePendingFocusPeerId.value = peerId }
```

### 6.2 Pure search logic (unit-testable, no Compose)

New file **`ui/mainstudio/presence/PresencePeerSearch.kt`**:

```kotlin
data class PeerSearchMatch(val key: String, val name: String, val isLocal: Boolean)

/** B4/B5 — full mesh, never the mode-filtered projection. */
fun PeersUiState.searchCandidates(): List<PeerSearchMatch>

/** B3 — case-insensitive substring over name and key; trimmed query. */
fun List<PeerSearchMatch>.matching(query: String): List<PeerSearchMatch>
```

- Candidates: `meshTopology.peers` when `meshTopology.localPeerKey` is non-blank,
  otherwise fall back to `remotePeers` (direct-only, pre-first-emission) —
  mirrors the extension's fallback branch exactly. Name resolution reuses
  `buildFullMeshModel`'s precedence: direct override → mesh `deviceName` →
  `peerKey.take(8)`.
- Then `CLOUD_NODE_KEY` / `CLOUD_NODE_DISPLAY_NAME` when the local peer is
  cloud-connected; then the local peer last with `isLocal = true`. Dedupe by key.

### 6.3 Search UI in the tab row

New file **`ui/mainstudio/presence/PresencePeerSearchBar.kt`** — an
`OutlinedTextField` (single line, `ImeAction.Search`, trailing clear ✕) plus the
results card.

Wire-up in `ui/mainstudio/PresenceSection.kt` → `PresenceContentSection`:

- The header `Row` gains, after `DittoConnectedButtonGroup` and inside the
  `Spacer(weight(1f))` region, `if (selectedTabIndex == 1) { PresencePeerSearchBar(...) }`.
- ⚠️ `DittoConnectedButtonGroup` is `width(IntrinsicSize.Max)` and M3 Expressive
  **morphs the selected segment wider on tap** — the reason the labels were
  shortened to "Peers"/"Viewer" in the first place (PresenceSection.kt:141–143).
  The field must take `Modifier.weight(1f)` with a `widthIn(min = 120.dp)` so it
  yields, not the button group or the gear. On a phone (compact width) fall back
  to a **search icon that expands the field over the row** rather than crushing
  all three into ~360 dp.
- Results card: wrap the header `Row` + content `Box` in a
  `Box(Modifier.fillMaxSize())` and render the results as a sibling **`Popup`**
  (or an overlay `Surface` with `zIndex`) anchored under the field, so it floats
  over the canvas and never reflows it (D6/B8). `LazyColumn`,
  `heightIn(max = 224.dp)`, `widthIn(max = 320.dp)`, `tonalElevation`.
- Rows: `Surface(onClick = …)` for focusable matches; a non-clickable `Row` for
  the local match with a `(this device)` suffix (B10).
  `testTag("PresenceSearchResult_$key")`.
- Empty state text `No peers match "<query>"` (B15).
- `ImeAction.Search` / `onKeyboardAction` → first non-local match (B13).
- **`BackHandler`** in `PresenceContentSection`, `enabled = query.isNotEmpty()`,
  clearing the query. It must sit **outside** `PresenceGraphView`, whose existing
  card `BackHandler` is nested deeper and therefore consumes back **first** —
  which is exactly the B16 card-then-query order, for free. Verify this ordering
  rather than assuming it.

### 6.4 Result pick → focus (B11/B12)

In `PresenceContentSection`'s click handler:

```kotlin
onPick = { key ->
    when {
        showDirectOnly -> { viewModel.requestPresenceFocus(key); viewModel.toggleDirectConnectedOnly() }
        key == focusedPeerId -> viewModel.setPresenceFocusedPeer(null)   // B12 toggle-off
        else -> viewModel.requestPresenceFocus(key)
    }
}
```

In `PresenceGraphView`, add a **new** `LaunchedEffect` keyed on
`(pendingFocusPeerId, showDirectConnectedOnly, graphModel.nodes, sceneSizePx.value)`
that calls `enterFocusMode(id)` once `!showDirectConnectedOnly &&
peerStates[id] != null && sceneSizePx != Zero`, then clears the pending id.

> ⚠️ **Do not reuse the existing tab-switch re-entry effect for this.** It bails
> out on `if (preFocusTransform.value != null) return` ("already entered here"),
> so picking a *second* search result while a focus session is live would set the
> hoisted id but never move the orbit. The new pending-focus effect must call
> `enterFocusMode` unconditionally (it already handles the
> replace-an-active-focus case). Close any open card on that path, matching
> `exitFocusMode`'s card cleanup.

### 6.5 Dimming (B6/B7)

`PresenceGraphView` takes a new `searchMatchIds: Set<String>?` parameter and
threads it into the two existing `when` blocks in `drawBehind`:

```kotlin
// edge alpha, after the focused/selected branches:
searchMatchIds != null ->
    if (edge.fromPeerId in searchMatchIds || edge.toPeerId in searchMatchIds) 1f else 0.2f

// pill alpha:
searchMatchIds != null && node.peerId !in searchMatchIds -> 0.35f
```

Placed **after** `focused != null` and `selected != null` (D3). Because these are
pure reads inside `drawBehind`, only the draw layer invalidates — no recomposition
cost per keystroke.

---

## 7. Pitfalls (from the reference commit's own review notes and this repo's history)

1. **Nil vs empty set** (D1) — the single likeliest defect; B15 is its test.
2. **`restoreAllAlpha()` hard-coding 1.0** on SwiftUI — clears an active search
   dim on every selection/focus exit. Must go through `restingAlpha`.
3. **Android's re-entry effect short-circuits** on `preFocusTransform != null` —
   hopping between search results silently does nothing (§6.4).
4. **Toggle-off must clean up the card.** The extension's own commit message
   calls this out as a review finding: `focusPeer()`'s toggle-off path has to run
   the same card cleanup as every other focus exit (B12).
5. **`ViewThatFits` + dynamic data** in `DetailViews.swift` — a documented
   feedback loop in this repo (§5.3).
6. **`MainStudioView.body` dependency creep** — reading the query inside
   `syncTabsDetailView()` re-runs the whole `NavigationSplitView` per keystroke
   (§5.3).
7. **`DittoSegmentedPicker` / `DittoConnectedButtonGroup` refuse to shrink** —
   the field must be the one that yields on a narrow pane (§5.3, §6.3).
8. **A card anchored to a departed peer** must close; a pending focus for a
   departed peer must be dropped, not left armed.
9. **`MainStudioView` per-frame cost:** the search field must not read the
   presence feed. Candidates are rebuilt on the throttled presence push only (D7).

---

## 8. Tests

**SwiftUI** — Swift Testing (`import Testing`), *not* XCTest. New file
`EdgeStudioUnitTests/Components/PresencePeerSearchTests.swift` (create via
XcodeWrite), alongside the existing `PresenceNetworkSceneTests.swift` /
`PresenceViewerTests.swift`.

| Test | Covers |
|---|---|
| candidates come from the unfiltered graph while Direct is ON | B4 |
| candidate order: remote → cloud → local last, deduped | B5 |
| match is case-insensitive over name **and** key; query trimmed | B3 |
| `searchMatchKeys` is nil when empty, empty-set on zero hits | B15/D1 |
| `focusForPeer`/`restingAlpha` — match 1.0, non-match dim, line touching a match 1.0 | B6 |
| focus and selection each win over an active search | B7/D3 |
| `focusSearchResult` while Direct ON arms pending + flips Direct; consumed on the next graph push | B11 |
| `focusSearchResult` on the already-focused peer exits focus **and** clears `detailPeerKey` | B12 |
| `focusFirstSearchResult` skips the local match | B13/B10 |
| `clearSearch` restores nil matches; query survives a scene rebuild | B14/B16/B17 |
| `restoreAllAlpha` keeps the search dim | pitfall 2 |

**Android** — JVM unit tests only (**no `connectedAndroidTest`**, no managed
devices — per standing instruction). New file
`app/src/test/java/.../presence/PresencePeerSearchTest.kt`, alongside the
existing `PresenceFocusPlannerTest.kt` etc. Same table as above for the pure
functions in `PresencePeerSearch.kt` (candidates, ordering, matching, the
mesh-empty fallback branch), plus the alpha-decision helper if the `when` blocks
are extracted to a testable function (recommended — extract
`fun peerAlphaFor(...)` / `fun edgeAlphaFor(...)` so the dimming rules are
covered without Compose).

Run with `--rerun-tasks` before quoting any Android test count (UP-TO-DATE
leaves stale XML that reads green).

**Builds (mandatory, both, before the work is called done):**
```bash
xcodebuild -project "SwiftUI/Edge Debug Helper.xcodeproj" -scheme "Edge Studio" \
  -configuration Debug -destination "platform=macOS,arch=arm64" build
xcodebuild -project "SwiftUI/Edge Debug Helper.xcodeproj" -scheme "Edge Studio" \
  -configuration Debug -destination "platform=iOS Simulator,name=iPad Pro 13-inch (M5)" build
```

---

## 9. Manual verification (a green build is not verification here)

Port of `docs/MANUAL_TESTING.md` step 13. Needs a real multi-peer mesh — the
MS-R1 Cuttlefish rig (`msr1-android-rig` skill) can stand up several Android
peers; pair with the Galaxy Z Fold 5 and a macOS instance.

1. Viewer tab: the search box appears in the tab row and the canvas keeps its
   full height. Switch to Peers: the box is gone.
2. Type a name fragment → matches and their edges stay lit, everything else dims;
   the graph does **not** reflow or resize.
3. Type nonsense → "No peers match", whole graph dims.
4. With **Direct ON**, search a multi-hop peer → it is listed; picking it flips
   Direct off and opens its focused-neighbourhood view.
5. Pick a **second** result while focused → the orbit moves to it (pitfall 3).
6. Pick the **focused** peer again → focus exits and any open card goes with it.
7. Press Enter → first non-local result focuses. The local row is listed, tagged
   `(this device)`, and is not clickable.
8. Escape / back: an open card closes first, the next one clears the query; the
   focus view survives both.
9. Round-trip Peers ↔ Viewer with a query active → the query and its dimming
   survive.
10. Narrow layouts: macOS window dragged narrow, iPad in a split pane, Fold
    **folded** cover screen (344 dp), phone portrait. Nothing truncates; the
    picker/button-group labels stay whole (pitfall 7).
11. Light and dark on both platforms.

Per `docs/FIX_VERIFICATION_RULE.md`: land this in **small verified batches**
(scene dimming → VM/logic → UI → wiring), and after each fix grep the
**production call site**, not just the test.

---

## 10. Suggested order

| Phase | Work | Verifiable by |
|---|---|---|
| 1 | Pure search logic + tests (both platforms, no UI) | unit tests |
| 2 | Scene/renderer dimming + tests | unit tests + eyeball with a hard-coded match set |
| 3 | VM state, pending-focus, focus routing | unit tests |
| 4 | SwiftUI field + results card + header wiring | manual §9 |
| 5 | Android search bar + results popup + header wiring | manual §9 |
| 6 | Docs: `docs/PRESENCE_GRAPH.md` note + in-app help paragraph (port `resources/help/presence.md`'s "Finding a peer with the search box"), and a manual-test section | review |

Phases 1–3 are platform-symmetric and can proceed in parallel per platform;
4 and 5 are independent of each other.

---

## 11. Out of scope

- Any change to the peer **detail card** (already ported).
- Filtering the graph *down* to matches — the extension dims, it does not filter,
  and the whole point is to keep the mesh visible while locating a peer.
- Fuzzy or token matching. B3 is plain case-insensitive substring; matching the
  reference exactly is a stated requirement.
- Search on the **Peers List** tab (that list has its own affordances).

---

## 12. Implementation record (2026-09-06)

### Verified

| Check | Result |
|---|---|
| macOS build (`Debug`, arm64) | ✅ `BUILD SUCCEEDED` |
| iOS build (iPad Pro 13-inch M5 simulator) | ✅ `BUILD SUCCEEDED` |
| SwiftUI unit tests (`EdgeStudioUnitTests`) | ✅ 859 tests in 140 suites passed (23 of them new) |
| Android `assembleDebug` | ✅ `BUILD SUCCESSFUL` |
| Android unit tests (`--rerun-tasks`) | ✅ 22 new tests pass (`PresencePeerSearchTest` 16, `PresenceSearchDimmingTest` 6) |
| Android `forbidNonAdaptiveSizeApis` | ✅ passes (the narrow-layout decision uses `BoxWithConstraints`, not `screenWidthDp`) |
| SwiftFormat / SwiftLint on all touched files | ✅ clean |
| Results card rendered (light + dark, hits / no-hits / 20 rows) | ✅ real production view snapshotted via `NSHostingView` |

**Pre-existing, unrelated failure:** `SystemRepositoryTest > mesh aggregation
includes edges only the local peer advertises` fails on Android. Confirmed by
stashing every change on this branch and re-running: it fails on the untouched
tree too. `--rerun-tasks` is what surfaces it — an UP-TO-DATE run reads green.
Not caused by, and not fixed by, this work.

### Found by rendering, not by the build

Snapshotting the results card caught a layout bug a green build could not: a
`ScrollView` is greedy and takes every point of height offered, so
`.frame(maxHeight: 224)` alone padded a three-hit card out with ~100pt of dead
space. Fixed with `.fixedSize(horizontal: false, vertical: true)` outside the
frame — the card now hugs its content and still caps and scrolls at 20 rows
(both re-rendered and confirmed).

### Deviations from the plan

- **`focusPeer` on the SwiftUI scene is new.** The plan routed search picks
  through `restoreFocusAfterRebuild`, which guards on `focusedPeerKey == nil` and
  so cannot *switch* focus — hopping between results would have done nothing. The
  same defect the plan flagged for Android (pitfall 3) turned out to exist on
  SwiftUI too. `focusPeer` replaces an active focus, carrying the pre-focus camera
  across by hand so a later exit still returns the user where they started.
- **Android's re-pick-to-toggle-off lives in `PresenceGraphView`, not the
  section.** Clearing the hoisted focus id from the caller leaves the camera stuck
  at the focus zoom and the peers on the orbit — only `exitFocusMode` restores
  both — so the toggle is handled where the pending focus is consumed.
- **`restoreAllAlpha()` now delegates to `reapplyRestingAlpha()`** rather than
  fading to a hard 1.0 (plan pitfall 2), so clearing a selection under an active
  query falls back to the search dim instead of un-dimming the graph.
- **The results card is its own file/composable on both platforms**
  (`PresencePeerSearchResultsCard.swift`, `PresencePeerSearchResults`), which is
  what made the SwiftUI render possible without a Ditto instance.
- **Android dim precedence was extracted** to `PresenceFocusPlanner.litPeerIds` /
  `litEdgeAnchors` / `dimmedPeerAlpha` / `dimmedEdgeAlpha` so the focus > selection
  > search order is unit-tested rather than asserted in a comment.
- **No `minWidth` on the SwiftUI box.** A minimum is reported back up the tree, so
  on a pane too narrow for it the tab row would overflow rather than compress.

### Not verified — needs the manual pass

- **Everything in §9 that requires a real multi-peer mesh**: the dimming as seen
  on the canvas, the Direct→full-mesh jump, hopping between results, Escape/Back
  unwind order, and query survival across the tab round trip. None of this is
  reachable from a unit test or a static render.
- **The SwiftUI tab row at narrow widths.** The box sits outside the
  `ViewThatFits` (it has to — it is dynamic), so how the row degrades on a narrow
  macOS window and on iPad in a split pane is unconfirmed.
- **The whole Android UI visually.** No screenshot-test harness is configured in
  this project and instrumented runs are off the table, so the search bar, the
  narrow-width icon fallback, and the results popup have never been rendered.
- **The Android edge-alpha `when` block** is covered only through the extracted
  planner functions it calls, not end-to-end through `drawBehind`.

---

## 13. Adversarial review round (2026-09-06)

Five independent reviewers (blind to each other), findings clustered by "would one
fix resolve both?", single-source findings sent to adversarial adjudication with two
adjudicators each — one instructed to refute, one to reproduce. Per
`docs/FIX_VERIFICATION_RULE.md`, nothing was fixed below two independent
confirmations.

13 raw findings → 11 distinct defects → **3 confirmed by two lenses**, 8 single-source
→ 4 adjudicated → **3 promoted unanimously**, 1 not promoted, 4 left unadjudicated.

### Fixed — all six met the bar

| # | Confirmations | Defect | Fix | Regression test proven by mutation |
|---|---|---|---|---|
| A4 | 2/2 adjudicators | `reapplyRestingAlpha` removed the `appearAnimation` key, which grouped the fade **and** the 0.5→1.0 scale-up. On the presence-push path a peer created in the same push was frozen as a permanent half-size pill. | Split into separately keyed `appearFade` / `appearScale`; every dim pass now kills only the fade. `PresenceNetworkScene.swift:695-712` | ✅ regrouping the keys fails `a search push does not cancel the scale-up of a peer that just joined` |
| A5 | 2/2 adjudicators | Android's `// key match` assertion was vacuous — satisfied by the *name* "Alpha", with a trailing `.filter` that discarded everything else. Deleting key matching kept CI green. | New `disjointState()` fixture where keys and names share no substring, plus a dedicated key-matching test. | ✅ deleting `it.key.lowercase().contains(needle)` fails `matching is case-insensitive over the peer key` |
| A1 | wiring + android | Crossing 600dp downward with an active query hid the field while the query, dimming and results card stayed live. `searchExpanded` is view-local and only the (narrow-only) magnifier sets it; `configChanges` means no recreation rescues it. Fold the Fold mid-search and you are stranded. | Extracted `PresencePeerSearch.showsExpandedNarrowSearch`; an active query always keeps a visible field. | ✅ reverting to `searchExpanded` alone fails `an active query keeps its field when the pane narrows past the threshold` |
| A2 | state + swiftui | `focusPeer` cleared the active focus *before* validating the target. A target failing `enterFocusMode`'s guards destroyed the user's focus session with nothing replacing it, and left `preFocusCamera*` armed so the **next** session exited to a stale camera. | New `canFocusPeer(_:)` as the single source of truth, checked before any mutation; `enterFocusMode` now guards through it so the two cannot drift. Failing is a no-op that keeps the existing focus (matching Android). | ✅ removing the guard fails `focusPeer on an unfocusable target keeps the focus the user already had` |
| A3 | state + swiftui | Candidates came from `rawRemotePeers`; the scene only ever receives edge-filtered `peersToShow`. Edgeless orphan peers were clickable rows that flipped Direct off and then silently failed to focus. | Candidates now filter through `PresenceEdgeAggregator.meshVisiblePeerKeys` — the same filter `peersToShow` uses, in the same function. Still the full mesh, so multi-hop peers stay findable. | `An edgeless orphan peer is not offered as a search result`; wiring confirmed by grep — `PresenceViewerSK.swift:643` (candidates) and `:670` (`peersToShow`) are the same filter in the same push |
| A6 | 2/2 adjudicators | The detail card's **"Focus this peer"** had never worked. `focusOpenPeer` routed through `restoreFocusAfterRebuild`, whose first guard is `focusedPeerKey == nil`, and the card only opens *while* focused. Pre-existing on `main`. | Routed to `focusPeer`, the path this branch added precisely because the restore path cannot switch focus. `PresenceViewerSK.swift:760-770` | — (covered indirectly by the `focusPeer` switch tests) |

### Recorded, deliberately NOT fixed

- **Not promoted (split verdict).** A SwiftUI test was claimed to pass via the scene's
  guard rather than the view-model guard it targets. Both adjudicators agreed the
  mechanics (the VM's `rawLocalPeer` is nil, so that guard is never reached), but the
  refuter showed the claimed user-visible regression cannot occur. A weak test, not a
  defect. Left alone rather than re-litigated.
- **Four single-source, unadjudicated** (rule 2 — never fix an unconfirmed finding):
  Android results card possibly covering the focus banner's exit button; Android orbit
  peers possibly stranded when hopping between results; no test that
  `reapplyRestingAlpha` actually repaints; no test for the deferred Direct→full-mesh
  focus on either platform. Worth a targeted adjudication round if any of them
  reproduces during the manual pass.

### Verification of this round

macOS + iPad builds; **863** SwiftUI unit tests (up from 859); Android `assembleDebug`,
`forbidNonAdaptiveSizeApis`, and **26** search tests (20 + 6, up from 22); SwiftLint
`--strict` clean on every changed Swift file. Four of the six fixes carry a regression
test proven to fail against the original defect, not merely to pass against the fix.

One self-inflicted problem caught and reverted: an earlier `swiftformat` run over whole
directories reformatted 34 unrelated files. Reverted, leaving only the intended six.

Still unverified, unchanged from §12: everything needing a real multi-peer mesh, the
SwiftUI tab row at narrow widths, and the Android UI visually.
