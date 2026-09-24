# Presence Viewer — Detail Cards in Focus Mode (2026-09-04)

In focus mode, tapping a peer opens a **detail card** showing everything the SDK knows
about it. Tapping again — or tapping the card — closes it.

Status: **shipped on Android. SwiftUI and the VS Code extension still to do.**

Revision 3 — rewritten to describe what actually shipped. Revisions 1 and 2 specified an
anchored card behind a "Details" switch; both ideas were dropped after testing on device.
The design decisions below are kept with their reasoning because the same forces apply on
the other two clients, and the [traps](#traps-we-hit-expect-them-again) section is the
part worth reading before porting.

---

## What shipped

| | Decision | Why |
|---|---|---|
| Where | Focus mode only | Outside focus the mesh can be 120 peers; no card is legible at the zoom that frames it |
| Collapsed | Unchanged — today's pill | Card never reaches `peerFootprints`, so ring layout and edges are untouched |
| Expanded | **Screen-space overlay, centred in the viewport**, fixed dp | See below |
| Open | Tap a peer | Tap had three meanings in focus mode; this is the one people come for |
| Close | Tap the peer again, tap the card, tap empty canvas, or Android back | No close button — it was chrome |
| Refocus | **"Focus this peer" button on the card** | Tap used to do this; moved rather than dropped |
| At once | One card | Two overlays would occlude each other with no layout to separate them |

**No Details switch.** Revision 2 gated all of this behind a toggle. On device it was
four gates deep (Direct off → tap peer → focus → switch on) with no affordance at any
step, and once the behaviour was tried it was obviously just how focus mode should work.

**Centred, not anchored.** Anchoring put the card wherever its peer happened to be,
including hard against an edge, where the graph container's `clipToBounds()` cut off the
sync rows — the rows the card exists for. Centring removed that failure mode instead of
managing it with flip-and-clamp rules, and it also means the card no longer has to chase
its node during a pan or pinch. The trade is that it covers the middle of the graph.

---

## The sizing argument (still the reason it's an overlay)

Focus orbit, 12 neighbours (the SDK caps connections per peer for battery), current ring
floors and focus camera. Rendered card width after the camera fits the orbit:

| card width | orbit radius | content | Fold cover (344) | Fold open (690) | iPad 13″ (1024) | desktop (1600) |
|---|---|---|---|---|---|---|
| 145 dp | 319 | 911 | 0.38× → **55 dp** | 0.76× → 110 dp | 1.12× → 163 dp | 1.25× → 181 dp |
| 180 dp | 386 | 1081 | 0.32× → **57 dp** | 0.64× → 115 dp | 0.95× → 171 dp | 1.25× → 225 dp |
| 240 dp | 502 | 1373 | 0.25× → **60 dp** | 0.50× → 121 dp | 0.75× → 179 dp | 1.17× → 280 dp |

55, 57, 60 dp — **a narrower card gains nothing.** Twelve nodes on a ring need radius ≈
1.93·(W+20), so content is always ~6× the card width; shrink the card and the orbit
shrinks with it. Rendered width converges to ≈ viewport ÷ 4.9, which depends only on the
screen. Laid-out cards work from about iPad size up and **cannot** work on a phone.

---

## Card content

Everything on `DittoPeer`, all of it available for **indirect** peers too:

| Row | Empty state |
|---|---|
| Peer key | "not reported" (blank on older SDKs) |
| OS | "not yet known" — the SDK learns it gradually |
| Ditto SDK | "not yet known" |
| Cloud link | Connected / None — true even for peers we can't reach |
| Compatible | "not yet known" |
| Peer metadata | key count, or "—" |
| Identity metadata | key count, or "—" |
| Sync | three-way, below |

Metadata is a **key count, never the blob** — the SDK caps each object at 4 KB, and
inlining it would make card height depend on the peer. Connections are omitted: transport
is already on the edges, with the legend as the key.

### The sync section has three states, and that is the point

`syncedUpToLocalCommitId` / `lastUpdateReceivedTime` come from
`system:data_sync_info` — a **local table computed from where this device actually
receives data**. It has rows only for peers we hold a sync session with, and **never for
indirect peers** (confirmed by the Ditto team; the SDK docs don't state the scope).

- **Direct peer** → commit id and last update, or "nothing yet" / "never".
- **Indirect peer** → *"No sync session — not directly connected"* plus one line of
  explanation. A focus orbit is the *focused* peer's neighbourhood, not ours, so this is
  the common case, not the exception.
- **Local peer** → *"This device"*. That table records what remote peers confirmed of
  **our** commits, so there is no row for ourselves; saying "not directly connected"
  about the local device would be nonsense.

---

## Traps we hit. Expect them again.

Each of these was a real defect in the Android build, found by testing or by adversarial
review. They are not Android-specific in nature.

### 1. Never let card size reach the layout engine

`peerFootprints` is a single scalar treated as horizontal extent by both ring floors. If
the card's size feeds it, ring radii move when a card opens, and a tall card overlaps its
neighbours near the top and bottom of the orbit. **The regression test is that every
pre-existing layout test passes unchanged** — if one needs editing, the card has leaked.

### 2. Don't consume pointer events wholesale on the card

The obvious way to stop taps leaking through to the graph canvas — a blanket pointer
consumer on the card wrapper — runs in the **Main pass**, which propagates child → parent.
The child sees the down, starts tracking, then the wrapper consumes the up, and tap
detection treats a consumed change as a cancelled tap. **Every interactive child inside
the card dies**: the close button, the focus action, the scroll. It looks like "the button
does nothing".

What works: an ordinary `clickable` on the wrapper (which closes the card and consumes
taps naturally, while children are hit first and consume their own), plus an explicit
"is this point inside the card?" guard in the graph's own gesture handler to cover drags
and pinches.

### 3. Don't put volatile data in the node's equality

Adding the detail payload to `PeerNode` put `lastUpdateReceivedTime` into its `equals`,
so `graphModel.nodes` changed on **every presence emission**. That re-fired the layout
effect, which refreshed focus, which re-centred the camera — throwing away the user's pan
and zoom while they were reading a card — and cancelled/relaunched every node's position
animation several times a second.

Two fixes, both worth having anyway: a focus **refresh** must not re-centre the camera
(only an explicit entry should), and the layout diff must skip nodes already at rest on
their target.

### 4. `isNull` is a type discriminator, not an emptiness check

`ObjectValue.isNull` asks "is this the JSON literal null?" — always false for an object.
Verified: an empty `ObjectValue` reports `isNull=false, isEmpty=true, toString="{}"`. A
`takeIf { !it.isNull }` guard therefore never fires, so every peer that never set metadata
was reported as having some. Use emptiness.

### 5. `ObjectValue.toString()` is not JSON

It emits Kotlin map syntax: `{role=my kiosk}`. `org.json.JSONObject` rejects it. Any key
count derived by parsing that string silently returns 0. **Carry the count from the SDK's
typed object**; keep the raw string only for verbatim display.

### 6. A modal surface must out-rank content back handlers

Back dispatch goes to the **most recently added** enabled callback, and registration
follows composition order. A scaffold that registers its drawer handler before `content()`
loses to any handler the content registers — back then silently dismisses something the
user cannot see. Registering the drawer's handler *after* `content()` fixes it for all
current and future content.

### 7. Strict mocks hide new SDK reads

A repository test mocking `DittoPeer` will throw the moment production code reads a field
the mock doesn't stub — and the failure surfaces somewhere unrelated (the observer dies,
a flow stays empty, a different test fails). One test also stubbed `isNull = true`, a
state the SDK cannot produce, which is what hid trap 4. Prefer real SDK value objects over
stubs in these fixtures.

---

## Android implementation map

| Concern | Location |
|---|---|
| Card UI | `presence/PeerDetailCard.kt` |
| Centring + card hit-test (pure, unit-tested) | `presence/PeerCardPlacement.kt` |
| Open/close state, overlay, tap routing | `presence/PresenceGraphView.kt` |
| `PeerDetail` + both projections | `presence/PresenceGraphState.kt` |
| `MeshPeer` detail fields | `domain/model/MeshTopology.kt` |
| `DittoPeer` → `MeshPeer`, metadata counts | `data/repository/SystemRepositoryImpl.kt` |
| Drawer back-handler ordering | `ui/mainstudio/StudioScaffold.kt` |

Tests: `PeerCardPlacementTest` (centring, pinning, hit-test), `PresenceGraphStateTest`
(direct/indirect/local detail projection, metadata counts carried not parsed).

---

## Ports still to do

### SwiftUI (`SwiftUI/`)

SpriteKit, which helps: the `SKCameraNode` scales the node tree, so the card must be a
**SwiftUI overlay above the `SpriteView`** rather than an `SKNode`, which gives
screen-space sizing for free and sidesteps trap 3's camera plumbing entirely.

- Focus state already exists in `PresenceNetworkScene`.
- Trap 1 applies verbatim — `recalculateLayout` passes `peerFootprints`; keep the card out.
- Trap 6 applies in its platform form (dismiss priority vs sheets/navigation).
- Traps 4 and 5 apply if the Swift SDK's metadata type behaves like the Kotlin one — **check
  before trusting either guard**.

### VS Code extension (`~/Developer/ditto-vsc-es`)

Land [getditto/vsc-es#25](https://github.com/getditto/vsc-es/pull/25) (balanced ring
packing) first so this doesn't stack on an unmerged base.

- Graph is **2D canvas** (`webview-ui/presence-graph/peer-node.ts` draws pills via `ctx`
  with a `measureText` cache), but the card should be **DOM positioned over the canvas** —
  far less work than drawing a card in canvas, and it gives text selection and scrolling
  free.
- `scene.ts` already owns `focusedPeerKey` / `isFocusedView` / `focusViewZoom`.
- Trap 2 has a direct analogue: stop the card's events reaching the canvas handler, without
  killing interaction inside the card (`stopPropagation` on the card root).

---

## Explicit non-goals

- Cards outside focus mode. Cheap to add — the overlay never touches layout — but out of
  scope.
- Changing `packBfsRings`, `calculateOptimalAngles`, or the ring floors.
- A 2D footprint model in the layout engine.
- The connections list inside the card.
