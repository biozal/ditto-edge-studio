# Parity plan: VS Code presence viewer — multicast + large-mesh modes → SwiftUI + Android

**Status:** Implemented on both platforms (Phases 1–6, 2026-09-03), then two
adversarial review + fix rounds (same day) — awaiting user review.
Open question #6 resolved during round 2 (Android zoom max aligned to 2.0).
Remaining deferrals: instrumented `MigrationTest`/focus/banner tests await the
wipe-safe device; iPadOS ships the multicast toggle ungated per the resolved
open question #1 (entitlement risk accepted pending real-device validation).

## Adversarial review round 2 (2026-09-03)

Same process as round 1 (3 fresh reviewers: SwiftUI / Android /
fix-verification+test-adequacy; tiebreaker adjudication for single-source
findings; two-reviewer agreement gate). Tiebreaker: **17 of 18 single-source
claims confirmed** (the refuted one: phantom-endpoint perpetual-rebuild —
mechanism real but unreachable from the SDK data model). Plus two items with
direct two-reviewer agreement (SwiftUI focus-across-tab-switch incoherence;
scene/fix-logic test gaps). All confirmed items fixed; both suites green after
(708 SwiftUI unit tests incl. 12 new headless scene tests; 666 Android unit
tests; instrumented additions compile-verified).

Fixed in round 2 (highlights):
- SpriteKit action-key races that broke focus mode during churn: line/peer
  fade-in now lands on the dim-aware resting alpha (and dims remove competing
  creation fades); `layoutMove`/`focusMove` mutually cancel.
- Ghost focus via tap-entry on a departing node (entry paths now check the
  model-liveness snapshot, not the fading node dictionary).
- SwiftUI `SystemRepository` peers-list + transport counts now aggregate
  local-advertised edges (the same asymmetry fix the graph got).
- Multicast validation at the QR/JSON trust boundary on both platforms,
  unconditional (SwiftUI: `DittoConfigForDatabase.init(from:)`; Android:
  ungated sanitize + trimmed group storage); strict group-octet parsing; MCP
  port rejects JSON booleans.
- Android editor save no longer wipes transport/multicast config (carries all
  non-editor fields forward from the loaded row); `applyTransportSettings` has
  try/finally (sync always restarts) and only publishes StateFlows on success.
- Focus genuinely survives tab switches on SwiftUI (key hoisted to the VM +
  re-entry after scene rebuild — matches Android).
- Engine crowding floor is now chord-aware on both platforms (small rings with
  wide pills no longer overlap; extension's `expandDirectRingForLabels`/
  `expandFocusedRingForLabels` parity).
- Android: Direct mode drops post-filter edgeless nodes; expanded fallback
  projection lays out at 1×; mid-drag mode toggle restores the pre-focus
  camera.
- Test-adequacy gaps closed: SwiftUI scene-level suite via the MockPeer seam
  (tap routing, zombie/ghost focus, layoutDirty, dim authority, restore);
  Android multicast mapping seam (`toMulticastBetaSpec`), repository-level
  local-edge aggregation test, instrumented equal-toggle + re-entry cases.
- Plan self-consistency: open question #6 answer ("align to 2.0") is now what
  the code does.

**Reviewed but not fixed** (single-source and low/pre-existing, or refuted):
phantom-endpoint rebuild defensiveness (refuted); SwiftUI `setHighlighted`
glow-alpha residue (pre-existing); departure double-layout snapshot skew
(pre-existing); `hoveredNode` not cleared on departure (pre-existing); Android
`pillMeasureCache` unbounded growth across renames (trivial); edge-id `_`
separator collision risk (pre-existing pattern, key alphabet unverified);
banner name staleness on rename without topology change (fixed only for the
focus path via SF-8).

## Adversarial review round (2026-09-03)

Process: 3 independent reviewers (SwiftUI correctness / Android correctness /
parity-vs-extension) + a tiebreaker adjudicator for single-source findings;
issues required two-reviewer agreement to be actionable. **All 17 adjudicated
findings confirmed and fixed**; both suites green after fixes (SwiftUI unit
suite 708 tests; Android `check`). Fixed highlights:

- Direct-mode visibility now derives from the aggregated edge set (incl.
  locally-advertised edges) on both platforms; SwiftUI's perpetual
  connection-line rebuild flicker fixed with it.
- Zombie focus when the focused peer leaves (SwiftUI now checks the current
  model keys, not the still-fading node dictionary); focus state hoisted to
  `MainStudioViewModel` on Android (survives tab switches).
- Mode toggle with unchanged topology: SwiftUI gained the extension's
  `layoutDirty` equivalent; Android keys its layout effect on the mode.
- SwiftUI coalesce changed from debounce to the extension's fixed-window
  throttle; aspectFill-aware fit-zoom; background-effects toggle survives
  scene recreation; dead focus banner after tab switch; toggle clears
  selection+hover.
- Android: stale gesture-handler captures (`rememberUpdatedState` throughout),
  drag-end deferred layout now runs full mode/focus bookkeeping, QR decode
  validates multicast fields (invalid → disabled + defaults), transport filter
  reads the real multicast flag (+ per-connection card filtering), expanded
  mode filters orphan peers (extension pass-2 parity, both platforms).
- Focus tap routing aligned with the extension on both: context-peer tap exits
  focus; local-in-orbit tap is a no-op; orbit peer refocuses; re-tap exits.

**Reviewed but not fixed** (single-source, low/polish, or pre-existing —
recorded for future reference): SwiftUI ex-neighbour orbit stranding until next
push; `noteActivity` not wired to drag paths; `updateZoomLevel` snapping camera
animations; NULL-DB-row port-0 read path; selection-dim alphas 0.35/0.20 vs
extension 0.25/0.08 (both natives agree, pre-existing values); macOS hover
emphasis gap; solitary-focus 1.0× pin; focus-fit padding asymmetry (64/88);
focus transition choreography (natives animate, extension snaps); reset-button
semantics broader than extension; rename not re-running SwiftUI layout; legend
row order (WebSocket before Multicast on natives).
**Source:** `~/Developer/ditto-vsc-es` (v0.9.1 binary; key commits `0e44828` transport
gating, `9fba4f6` expanded spread, `53a1458` focus mode, `7e3acfe` packed multi-ring
layout, `a0467e9` Multicast connection type, `5d1f5cd` focus-zoom fit).
**Android multicast reference implementation:** `~/Developer/demoapp-retail` (Zava
Retail, Ditto SDK 5.1.0, multicast verified on-device).
**Goal:** bring the extension's presence-viewer upgrades to both native apps:
(1) multicast transport support, (2) multicast as a first-class connection type in
the graph, (3) the large-mesh UI modes that keep the graph usable at 30+ devices.

**Terminology:** the extension has no literal "indirect mode". The user-facing control
is the **Direct checkbox** (state field `directConnectedOnly`, default `true`).
Unchecked = *full-mesh / expanded mode*, which is what renders indirect (multi-hop,
transitive) peers. This plan uses "Direct mode" and "Expanded mode" throughout.

---

## What the extension ships (evidence trail)

### A. Multicast as a presence-graph connection type (commit `a0467e9`)

- `ConnectionType` gains `'Multicast'`. The JS SDK cannot *create* multicast
  connections but reports multicast edges learned from the mesh (e.g. from Android
  peers running the multicast beta).
- **Edge aggregation fix** (`src/ditto/peer-info.ts:254-258`): the local peer's own
  `connections` are aggregated into the graph edge set, not just remote peers' —
  otherwise a transport (notably multicast) is lost when only the local side
  advertises the edge.
- Style: bright golden-yellow `#FFD60A`, dotted dash `[2, 3]`; legend row;
  peer-card gradient `rgb(255,214,10) → rgb(170,125,0)` with a broadcast icon.
- Dominant-connection-type priority for card gradients:
  `WebSocket > AccessPoint > P2PWiFi > Multicast > Bluetooth`.

### B. Multicast transport configuration

Two different SDK surfaces, both relevant:

1. **Multicast peer discovery** rides the LAN flag (extension,
   `DittoManager.ts:247-256`):
   `lan.isEnabled = lan.isMdnsEnabled = lan.isMulticastEnabled = <lanOn>`.
   No separate toggle; LAN supported on all platforms.
2. **Reliable UDP multicast transport** (`peerToPeer.multicastBeta`) — the JS SDK
   can't create these, but the native SDKs can. The retail app proves the Android
   path; the Swift binary confirms the macOS/iOS API (both verified below).

Verified SDK 5.1.0 API surface:

```swift
// DittoSwift 5.1.0 (macos-arm64 + ios-arm64 swiftinterface, verified in DerivedData)
public struct DittoMulticastBetaConfig : Sendable, Codable, Equatable {
  public var isEnabled: Bool
  public var groupAddress: String   // SDK default 224.1.2.3
  public var port: UInt16           // SDK default 6003
  public var interfaceName: String?
}
// config.peerToPeer.multicastBeta ; also config.peerToPeer.lan.isMDNSEnabled / .isMulticastEnabled
```

```kotlin
// ditto-kotlin-android 5.1.0 (sources jar) + retail app DittoManager.kt:278-295
ditto.updateTransportConfig { c ->
    c.peerToPeer.multicastBeta.enabled = config.enabled
    c.peerToPeer.multicastBeta.groupAddress = config.groupAddress
    c.peerToPeer.multicastBeta.port = config.port.toUShort()
    c.peerToPeer.multicastBeta.interfaceName = config.interfaceName
}
```

Retail-app platform lessons (verified on-device, `demoapp-retail/android/AGENTS.md`):

- **CRITICAL: multicast config changes are DEFERRED while sync is active on
  Android.** Apply before `sync.start()` on cold open (the retail app stages a
  `pendingMulticastConfig`), and for live changes do stop → apply → start in a
  `try/finally` so sync always restarts.
- Manifest needs `android.permission.CHANGE_WIFI_MULTICAST_STATE`
  (unconditional; `sync.start` throws if multicast is enabled without it).
  SDK KDoc mentions `ACCESS_LOCAL_NETWORK` for **targetSdk 37+** — Edge Studio
  targets 36 today; note for the future targetSdk bump.
- The SDK holds its own engine-level `MulticastLock`; the retail app additionally
  holds an app-level non-reference-counted lock for the whole enabled period.
- Config model with validation: class-D IPv4 group (first octet 224–239),
  port 1..65535 (**0 rejected** — SDK treats it as "any port" and group rendezvous
  silently breaks), nullable interface name. Defaults match SDK: `224.1.2.3:6003`.
- Live verification: count `DittoConnectionType.Multicast` edges on
  `presence.observe()` and surface as a status badge.

### C. Large-mesh layout modes

**Expanded mode** (Direct unchecked; `NetworkLayoutEngine.ts` +
`presence-graph/scene.ts`):

- `EXPANDED_RADIUS_SCALE = 1.75` ring spread (compact mode = 1).
- **`packBfsRings`**: logical BFS layers pack into *multiple concentric visual
  rings*; a crowded layer may consume several rings, but the next BFS layer never
  starts until the current one is complete. Ring capacity comes from
  `peersPerExpandedRing()` using `EXPANDED_NODE_FOOTPRINT = 200` (or real measured
  pill widths via `peerFootprints`), with a chord-length reduction loop so the
  widest pill fits between neighbors.
- Expanded rings use **equal angular spacing** — parent anchoring is disabled
  because it "would bunch siblings together again".
- Ring-1 chord-locality ordering (`sortRing1Peers` greedy double-ended path) is
  computed on the *logical* ring before packing.
- The crowding-based minimum circumference floor (`calculateRingRadii`) is
  intentionally **not** scaled by `radiusScale`.
- Entering Direct mode sets fit-on-next-layout; `fitZoomToLayout` only ever zooms
  **out**, never over the user's zoom-in.

**Focus mode** (click a remote peer *in Expanded mode*; `scene.ts:685-940`):

- Selected peer re-laid-out at center; its direct neighbours form a BFS ring around
  it (separate layout call over `{key, ...neighboursOf(key)}`).
- Label-aware ring expansion (`expandFocusedRingForLabels`): `FOCUS_RING_GAP = 24`,
  `FOCUS_NODE_HEIGHT = 22.5`, `FOCUS_ESTIMATED_CHAR_WIDTH = 7`.
- Focus owns its zoom: `focusViewZoom` targets `clamp(max(zoom, FOCUS_ZOOM=1.25),
  fitZoom)`; fit uses `FOCUS_VIEW_PADDING_X = 64` / `Y = 88`.
- Background mesh stays as dimmed context: peers `0.08` alpha, lines `0.04`;
  140 ms fade. (The extension also blurs 2 px *during the fade only* — optional on
  native, see open questions.)
- UI: top-center pill banner "Focused on \<label\>" + exit button; exit via button,
  re-click, or click empty canvas.
- Neighbour set cached per `(focusKey, linesEpoch)` — scanning all lines per peer
  per frame was O(peers × lines) at 60 fps.

**Selection dimming (both modes):** hover/click selection dims unrelated peers to
`0.25`, unrelated lines to `0.08`; selected lines draw at width 3 vs 2. In Direct
mode the local peer is never selectable (every line touches it).

**Mode invariants to port exactly:** switching modes clears selection/focus/hover;
mode + controls-visibility state is owned by the *parent* so it survives tab
rebuilds; a mode toggle runs layout exactly once; entering Direct may auto-lower
(never raise) zoom.

### D. Controls & chrome

- Zoom range `0.25 – 2.0`, snapped to whole percents.
- **Center button** — recenters on the local node's actual position, resets zoom
  to 100 %.
- **Background-effects toggle** (stars + gradient on/off).
- **Eye button** — hides/shows legend + Direct + zoom; center and eye always
  remain; state parent-owned.
- Legend: every transport gets color **and** dash-pattern sample (accessibility:
  never color alone), rows for Bluetooth / LAN / P2P WiFi / Multicast / WebSocket /
  Cloud.
- Header: sync status dot + Stop/Start Sync button + transport gear popover.

### E. Performance techniques

- 250 ms presence coalesce + JSON fingerprint before pushing to the view (no
  re-render on unchanged data).
- Layout re-runs **only** when topology/labels/measurement context change.
- Pill-width `measureText` cache, invalidated on rename.
- Canvas idle freeze after 3 s without input/pushes.
- Parallel edges between the same pair get perpendicular offsets (±10 px base).
- Deliberately **not** used: no virtualization, clustering, WebGL, or LoD beyond
  the modes above. Scale comes from canvas + packing + idle freezing.

---

## Current state in this repo

**SwiftUI** (`SwiftUI/EdgeStudio/`): SpriteKit scene (`PresenceNetworkScene`) +
`NetworkLayoutEngine` (the extension's engine is a direct port of ours). Already
has: `showDirectConnectedOnly` toggle (default true), zoom 0.5–2.0, drag/pan/hover,
tap-to-isolate dimming, reset-view button, legend incl. a Multicast row, per-type
dash styles incl. `.multicast` (teal `0,0.55,0.60` dash `[4,4]` — **not** the
extension's gold), per-database transport flags BLE/LAN/AWDL in
`DittoConfigForDatabase` (SQLCipher) edited via `TransportConfigView`, MCP
`configure_transport`. Missing: any `multicastBeta` configuration
(`SystemRepository.isConnectionTypeEnabled(.multicast)` hard-returns true), the
local-peer edge aggregation fix (verify), expanded-mode packing, focus mode with
re-layout, label-aware layout, background-effects toggle (the 160-sprite
`FloatingSquaresLayer` always animates), controls-visibility toggle, zoom min 0.25.
No presence-viewer tests exist.

**Android** (`android/`): Compose `drawBehind` renderer (`PresenceGraphView`) +
pure-Kotlin `PresenceGraphLayout` (line-for-line port of the iOS engine) +
`PresenceGraphState.toGraphModel()` (already has Direct/Expanded projections fed by
the unfiltered `meshTopology` flow). Already has: Direct toggle, zoom 0.5–2.5,
tap-to-select dimming, reset view, legend (no Multicast row), per-transport dash
styles. Missing: `ConnectionType.Multicast` (SDK Multicast currently collapses to
`LAN` in `SystemRepositoryImpl.toConnectionType()`), all multicast transport
configuration (no manifest permission, no `multicastBeta`, no app lock), Room
columns (DB v6 — needs v7 migration + schema JSON), expanded-mode packing, focus
mode, label-aware layout (though `measurePeerPill` exists in the renderer),
controls-visibility toggle. No background particles by design (`plans/android/
presence-viewer.md`) — the effects toggle is N/A on Android. Good test coverage of
layout/state/styles already exists to extend.

---

## Work items

### Phase 0 — Verification spikes (small; before Phase 2)

1. **iPadOS entitlement check (SwiftUI).** UDP multicast on iOS/iPadOS requires the
   restricted `com.apple.developer.networking.multicast` entitlement (Apple
   approval). Determine: does `multicastBeta` on iPadOS no-op/fail without it?
   Outcome decides whether the iPadOS UI shows the toggle or gates it to macOS.
   macOS needs no entitlement.
2. **Swift sync-activity semantics.** Android defers multicast changes while sync
   is active; verify whether the Swift SDK has the same constraint (our existing
   apply path already does stop → apply → restart, so this is documentation only).
3. Android needs **no** PoC — the retail app validated the full flow on-device
   against 5.1.0.

### Phase 1 — Multicast connection type rendering (small; both platforms) — **Implemented** (2026-09-03)

Both platforms: gold `#FFD60A` dotted `[2,3]` style, legend rows, card gradients,
broadcast icon, dominant-type priority (WebSocket > LAN > P2PWiFi > Multicast >
Bluetooth), and the local-peer edge-aggregation fix (SwiftUI: extracted pure
`PresenceEdgeAggregator` used by both the change-detection and draw passes;
Android: `meshTopology` now includes `graph.localPeer.connections`). Tests:
SwiftUI `PresenceViewerTests` (7 new, full unit suite green); Android
`ConnectionStylesTest`/`ConnectionTypeEnabledTest`/`PresenceGraphStateTest`
extended (`./gradlew check` green; Gradle daemon must run on a JDK **with jlink**
— the redhat.java VS Code extension JRE lacks it; pass
`-Porg.gradle.java.installations.paths=$HOME/.gradle/jdks/eclipse_adoptium-21-aarch64-os_x.2/jdk-21.0.7+6/Contents/Home -Porg.gradle.java.installations.auto-detect=false`).

SwiftUI:
- `ConnectionLine.swift`: change `.multicast` to gold `#FFD60A`, dash `[2, 3]` to
  match the extension (supersedes the current teal; check `docs/BRAND_COLORS.md`
  conventions when doing so). Update the legend row in `PresenceViewerSK` and the
  card gradient in `ConnectedPeersView` to `rgb(255,214,10) → rgb(170,125,0)` with
  a broadcast-style icon.
- Port the **local-peer edge aggregation fix**: ensure the scene's edge set
  includes `localPeer.connections` (verify `PresenceViewerSK.ViewModel` /
  `PresenceNetworkScene` today; the extension comment explains why — a transport
  is lost when only the local side advertises the edge).
- Dominant-type priority for card gradients: insert Multicast between P2PWiFi and
  Bluetooth.
- Tests (Swift Testing, new): connection-style table; edge-aggregation using the
  existing unused `MockPeer`/`MockConnection` seam in `PresenceProtocols.swift`.

Android:
- `domain/model/SyncStatusInfo.kt`: add `ConnectionType.Multicast`; stop mapping
  SDK `Multicast → LAN` in `SystemRepositoryImpl.toConnectionType()`.
- `ConnectionStyles.kt`: gold `#FFD60A` + `[2f, 3f]` dash (light/dark variants);
  legend row in `ConnectionLegendCard`; `ConnectionsByTransport.multicast` count +
  `ConnectionsMenuButton` row; `RemotePeerCard` gradient/icon/`displayName`.
- Verify `SystemRepositoryImpl._meshTopology` aggregates `graph.localPeer.
  connections` too; add if missing (same fix as SwiftUI).
- Update `ConnectionType.isEnabledIn(config)` once the Phase 2 flag exists
  (until then Multicast passes through, mirroring today's behavior).
- Tests: extend `PresenceGraphStateTest` (multicast edges direct + mesh, dedup),
  `ConnectionStylesTest`, `ConnectionTypeEnabledTest`; instrumented legend
  assertion in `PresenceGraphViewTest`.

### Phase 2 — Multicast transport configuration (medium; both platforms) — **Implemented** (2026-09-03)

Both platforms: per-database multicast settings (default OFF, SDK-default
`224.1.2.3:6003`, nullable interface), validated `MulticastConfig` model (class-D
group, port 1–65535, port-0 rejected), LAN discovery parity
(`lan.isMDNSEnabled`/`isMulticastEnabled` ride the LAN flag), transport-settings UI
toggle + advanced fields with validation, and the disabled-transport filter now
reads the real flag. SwiftUI: SQLCipher schema v6 (+ `SchemaMigrationV6Tests`),
`DittoConfigForDatabase` coding with back-compat defaults, editor pass-through,
MCP `configure_transport` multicast args (+ manifest test). Android: manifest
`CHANGE_WIFI_MULTICAST_STATE`, Room v7 + `MigrationTest` (v7), app-level
`MulticastLockController` at the single apply chokepoint, QR payload round-trip.
Green: full SwiftUI unit+integration suites (except one **pre-existing
environmental failure** — `MCPToolExecutionTests.testListDatabasesReturnsResult`
fails because the shared unit-test store dir
`~/Library/Containers/com.costoda.dittoedgestudio.debug/…/ditto_edge_studio_unit_test/`
carries `com.apple.quarantine` xattrs from Aug 6 and lacks `sqlcipher.key`; the
EPERM occurs in key-file read, a code path this change provably does not touch;
remedy: delete or de-quarantine that directory) and `./gradlew check` (same JDK
flags as Phase 1; instrumented `MigrationTest` compiles, awaits the wipe-safe
device). Open-question note: the SwiftUI toggle ships on iPadOS **ungated** —
Phase 0's entitlement check (`com.apple.developer.networking.multicast`) is still
unresolved and may require gating the toggle to macOS.

Shared decisions: per-database `isMulticastEnabled` flag, **default OFF** (beta,
same-subnet-only — unlike BLE/LAN which default on). Optional advanced overrides
(group address / port / interface) with the retail app's validation; defaults
`224.1.2.3:6003`. Also wire LAN *discovery* parity with the extension:
`lan.isMdnsEnabled`/`lan.isMulticastEnabled` follow the LAN flag on both
platforms.

SwiftUI:
- `DittoConfigForDatabase` += `isMulticastEnabled` (back-compat
  `decodeIfPresent ?? false`) + optional `multicastGroupAddress: String?`,
  `multicastPort: UInt16?`, `multicastInterfaceName: String?`; repository write
  path (`DatabaseRepository.updateDittoAppConfig`).
- `DittoManager.applyTransportConfig(...)` + the `AdvancedSettingsApplier` open
  sequence: set `config.peerToPeer.multicastBeta.*` from the flags; extend
  `transportFlags(for:)`/`logTransportReadback`; multicast stays off under UI
  testing like the other p2p transports.
- `TransportConfigView`: "Multicast (beta)" toggle + collapsed advanced section
  (validated group/port/interface fields), same stop→apply→restart progress
  machine. Gate by Phase 0 entitlement outcome on iPadOS.
- `SystemRepository.isConnectionTypeEnabled(.multicast)` reads the new flag.
- MCP `configure_transport`: add `multicast` boolean (+ optional group/port).
- Tests: model defaults/legacy decode (`ModelTests`), pure-decision extraction for
  the flag→config mapping (`DittoManagerPureDecisionsTests` pattern), MCP schema
  test, `AdvancedSettingsApplierTests` ordering.

Android:
- Manifest: `CHANGE_WIFI_MULTICAST_STATE` (unconditional).
- Port `MulticastConfig` (enabled/groupAddress/port/interfaceName + validation)
  from the retail app into `domain/model/`, with its unit tests.
- `DittoDatabase` + `DatabaseConfigEntity` += the four fields; Room v6→v7
  migration + committed schema JSON + `MigrationTest` update.
- `DittoManager.applyTransportConfig()`: add `multicastBeta { … }` (port via
  `.toUShort()`) and `lan { multicastEnabled = mdnsEnabled = lanEnabled }`.
- `StudioSession.applyTransportSettings()` already does stop → apply → persist →
  restart — this satisfies the deferred-while-sync-active constraint; add a
  comment citing it, and confirm hydrate applies config before `startSync()`.
- App-level non-reference-counted `WifiManager.MulticastLock`
  (tag `"edge-studio-multicast"`, guarded `isHeld` acquire/release) held while
  enabled — port from retail `DittoManager.kt:321-332`.
- `TransportConfigSheet`: "Multicast (beta)" toggle + advanced validated fields;
  live multicast connection count badge fed by the existing presence flow
  (retail `MulticastScreen.kt:52-57` pattern).
- Tests: `MulticastConfigTest` (validation incl. port-0 rejection), Room
  migration test, `DittoManagerTest` transport-builder mapping, instrumented
  sheet test on the wipe-safe device.

### Phase 3 — Expanded-mode ring packing (medium; both platforms) — **Implemented** (2026-09-03)

Both engines ported from the extension's `NetworkLayoutEngine.ts` (itself a port of
our SwiftUI engine): `radiusScale` (1.75 in full-mesh mode), `packBfsRings`
(logical BFS layers → multiple visual rings, next layer never starts early),
ring-1 chord-locality ordering computed on the logical ring before packing,
equal angular spacing in expanded rings, measured pill footprints feeding
`peersPerExpandedRing` with the chord-length reduction loop, and the unscaled
crowding floor. Scene/view wiring: Direct-off layouts pass
`radiusScale = EXPANDED_RADIUS_SCALE` + measured pill widths; entering Direct mode
fit-zooms (zoom-out only, never past the user's zoom-in) once the compact layout
lands. Tests: new SwiftUI `NetworkLayoutEngineTests` (14) and extended Android
`PresenceGraphLayoutTest` (+6), both porting the extension's contract scenarios —
including the 12-direct+1-indirect packing case, 340-wide footprint packing,
100-peer uniqueness, and the unscaled-floor case. Port note: JS `slice()` silently
clamps the pack window — Kotlin `subList` throws, so the Android port clamps
explicitly. Green: full SwiftUI unit suite, `./gradlew check`.

Port `packBfsRings` + `EXPANDED_RADIUS_SCALE = 1.75` + `EXPANDED_NODE_FOOTPRINT =
200` semantics into both layout engines. The engines are siblings (the TS one is a
port of ours), so this is a port-back:

- Logical BFS layers → multiple visual rings; next BFS layer never starts early.
- Ring capacity from measured pill footprints (fall back to 200 pt/dp);
  chord-length reduction loop so the widest pill fits.
- Expanded rings use equal angular spacing (no parent anchoring); ring-1 chord
  locality computed on the logical ring before packing.
- Circumference floor not scaled by `radiusScale`.
- Entering Direct mode: fit-zoom that only ever lowers zoom.

SwiftUI: extend `NetworkLayoutEngine.calculateLayout` with a mode parameter; pill
widths from `PeerNode` label measurement (cache them). Extract the packing math as
pure static functions and add the **first** `NetworkLayoutEngine` test suite
(Swift Testing), porting the extension's `NetworkLayoutEngine.test.ts` scenarios —
including the named `['local', …direct, 'indirect']` case asserting indirect peers
land outside all direct peers' packed rings.

Android: extend `PresenceGraphLayout.calculateRadialLayout` the same way. Keep it
Compose-free: `PresenceGraphView` already measures pills (`measurePeerPill`);
inject a footprint map into the layout call. Extend `PresenceGraphLayoutTest` with
expanded-mode cases (multi-ring packing, equal spacing, no-early-next-layer).

### Phase 4 — Focus mode (medium-large; both platforms) — **Implemented** (2026-09-03)

Both platforms: tap a remote peer in Expanded mode → focused-neighbourhood view
(focused peer re-laid-out at centre, direct neighbours on one orbit via the shared
engine, rest of mesh dimmed to context alphas 0.08/0.04), focus-owned zoom
(extension formula `clampZoom(min(max(zoom, 1.25), fit))`, translated to SpriteKit
camera-scale semantics on iOS), top-center "Focused on \<label\>" banner with exit
button, exit via banner / re-tap / empty-canvas tap, and the mode invariants
(mode toggle discards focus + selection with exactly one layout pass; focused
peer leaving the mesh exits; topology change refreshes the orbit). Pure decisions
extracted + tested: `PresenceFocusPlanner` (Swift) / `PresenceFocusPlanner`
(Kotlin) — neighbour extraction, fit, zoom formula. Deviation by design: the
extension's 2px blur during the fade is skipped (dim-only; `SKEffectNode` blur is
expensive, and the extension itself blurs only during the 140ms fade), and its
`expandFocusedRingForLabels` is superseded by the Phase-3 engine's
footprint-aware crowding floor. Note: on Android the local peer stays selectable
in Direct mode (pre-existing intentional divergence, documented in
`PresenceGraphView`); focus is remote-peers-only on both. Green: full SwiftUI
unit suite (7 new planner tests), `./gradlew check` (+6 planner tests; 2 new
instrumented banner tests compile, await the wipe-safe device).

- Trigger: tap a remote peer **in Expanded mode**. Direct-mode tap keeps today's
  dim-only behavior (extension parity).
- Selected peer to center; direct neighbours on a BFS ring (separate layout over
  `{key} ∪ neighboursOf(key)`); label-aware ring expansion (`FOCUS_RING_GAP = 24`,
  node height 22.5, est. char width 7 fallback).
- Focus zoom: target `max(current, 1.25)` clamped to fit the focused layout
  (padding 64/88); restore previous zoom on exit.
- Context: non-neighbourhood peers at 0.08 alpha, lines at 0.04; 140 ms fade.
- Top-center "Focused on \<label\>" banner with exit; exit via button / re-tap /
  empty-canvas tap.
- Neighbour-set cache keyed by `(focusKey, edgesEpoch)`.
- Mode invariants: mode toggle clears focus/selection/hover; focus + controls
  state hoisted to the parent (`MainStudioView`/`MainStudioViewModel` and
  `PresenceContentSection`/`MainStudioViewModel`) so it survives tab switches;
  exactly one layout per toggle.

SwiftUI notes: `PresenceNetworkScene` gains `focusPeerKey` state; reuses
`NetworkLayoutEngine` for the neighbourhood layout. The extension's 2 px blur is
**optional** — SpriteKit `SKEffectNode` blur is expensive; propose dim-only
(open question below).
Android notes: focus layout reuses `calculateRadialLayout` on the neighbourhood
subgraph; `Animatable` transitions already exist; banner as an overlay composable;
semantics node for the exit button.
Tests: pure focus-layout/neighbour-set unit tests on both platforms; instrumented
Compose test via the semantics overlay; SwiftUI scene-level tests via the
`MockPeer` seam.

### Phase 5 — Controls & chrome parity (small-medium; both platforms) — **Implemented** (2026-09-03)

Shipped: deep zoom-out for large meshes — Android `Transform.MIN_SCALE` 0.5 →
**0.25** (direct magnification, extension parity); SwiftUI camera-scale range
0.5–2.0 → **0.5–4.0** (4.0 scale = 0.25 magnification) across scroll wheel,
pinch, toolbar buttons, the Direct-entry fit-zoom cap, and the focus planner's
clamp (planner test updated). Android max 2.5 → **2.0** per the resolved open
question #6 (aligned in the round-2 review sweep). Center/
reset buttons audited — both already match `resetViewToLocal` (recenter + 100 %,
focus-aware on both after Phase 4). **Eye toggle** on both: SwiftUI
`controlsVisible` on the hoisted `PresenceViewerSK.ViewModel` (hides legend +
Direct + zoom cluster; reset/eye/effects remain); Android
`presenceControlsVisible` StateFlow on the session-scoped `MainStudioViewModel`
(same hidden set; banner unaffected). **Background-effects toggle** (SwiftUI
only): `FloatingSquaresLayer.isEnabled` hides + pauses all sprites, plumbed
scene → VM → toolbar (sparkles button). Legend dash samples audited — both
platforms fine as-is. Header sync controls remain out of scope (native apps
have sync controls elsewhere). Green: full SwiftUI unit suite, `./gradlew check`.

- Zoom: lower min to **0.25** on both (extension range 0.25–2.0; Android max
  2.5 → align to 2.0, see open questions); snap percentage label to whole
  percents.
- Center-on-local button semantics match `resetViewToLocal` (recenter on the
  local node's *actual* position + 100 % zoom) — audit native reset buttons.
- Controls-visibility (eye) toggle on both; state hoisted to survive tab
  switches.
- Background-effects toggle: SwiftUI only (`FloatingSquaresLayer` on/off);
  Android N/A by design.
- Legend: dash-pattern samples per row everywhere (Android `LegendRow` already
  does; audit SwiftUI rows).
- Extension header extras (sync status dot, Stop/Start Sync in the presence
  header): **proposed out of scope** — native apps have sync controls elsewhere;
  confirm in review.

### Phase 6 — Performance hardening (small; both platforms) — **Implemented** (2026-09-03)

Audit results + changes:
- **Fingerprint**: Android already covered — `StateFlow` dedupes equal
  `MeshTopology` emissions and `derivedStateOf` gates recomposition; SwiftUI
  scene already skips rebuilds via topology snapshots. No code needed.
- **Presence coalesce (250 ms)**: added to the SwiftUI VM observer path
  (debounced `Task`, cancelled on stop; the Direct-toggle path stays immediate).
  Android's per-emission DQL query is tiny and StateFlow-conflated — documented,
  not changed.
- **Pill caches**: Android label-keyed `measurePeerPill` cache added (topology
  churn re-measures nothing); SwiftUI already measures only on create/rename.
- **Idle freeze (SwiftUI)**: `FloatingSquaresLayer.isFrozen` pauses (not hides)
  the sprites after 3 s without input or presence pushes; activity
  (`updatePresenceGraph`, mouse/touch/scroll/pinch) unfreezes. Android verified
  invalidation-driven (no idle cost; the only perpetual animation is the
  selection pulse, active only while a selection exists).
- **Engine determinism fix (both platforms, found via a flaky full-suite
  failure of `radiusScaleSpreadsRings`)**: BFS iterated `Set` neighbors and
  appended `Set`-derived disconnected peers unsorted, so ring/angle order was
  hash-seed dependent. Both engines now sort BFS neighbors and disconnected
  peers — layouts are deterministic per topology on both platforms.
- Single-layout-per-toggle invariant: verified during Phase 4 (both platforms).
- Viewport culling: deliberately not built (SpriteKit culls; Android `drawBehind`
  redraws only on invalidation).

Green: full SwiftUI unit suite (3× isolated reruns of the previously flaky
test + full suite), `./gradlew check`.

- Presence coalesce + change fingerprint before view updates (250 ms):
  SwiftUI — audit `SystemRepository` backpressure pipeline + scene topology
  snapshots (likely already equivalent; document or add fingerprint);
  Android — add 250 ms `conflate`/fingerprint on the `meshTopology` publish path
  so `drawBehind` isn't invalidated by no-op emissions.
- Pill-width measurement caches on both platforms.
- Single-layout-per-toggle audit on both (extension invariant).
- SwiftUI: pause `FloatingSquaresLayer` after ~3 s idle (idle-freeze parity) and
  when effects are toggled off. Android: already invalidation-driven (idle ≈ 0)
  — verify only.
- Optional, only if profiling demands: viewport culling in Android's draw loop;
  SpriteKit culls off-screen nodes already, but edge path rebuilds could be
  deferred. Do **not** build speculatively.

---

## Testing strategy

- Per `docs/TESTING.md`: Swift Testing (`@Suite`/`@Test`) for unit/integration,
  XCTest only for UI; ≥80 % coverage on new code via extracted pure logic (layout
  packing, focus neighbourhood, multicast config mapping/validation are all pure
  and must be extracted/tested); Android JVM unit tests (JUnit4 + MockK +
  `runTest`) plus instrumented Compose tests on the designated wipe-safe device
  (`ANDROID_SERIAL=… ./gradlew connectedAndroidTest`).
- Each phase keeps `EdgeStudioUnitTests` and `./gradlew check` green.
- Port the extension's behavioral contracts where they exist:
  `NetworkLayoutEngine.test.ts` ring assertions, `PresenceGraphScene.test.ts`
  mode/focus/zoom invariants, `peer-info.test.ts` "preserves multicast edges".
- Follow `docs/FIX_VERIFICATION_RULE.md`: findings need two confirmations; verify
  fixes at the production call site (e.g. presence-callback path the view actually
  uses, not just VM methods).

## Docs to update when implemented

- `docs/PRESENCE_GRAPH.md` — multicast edge semantics + the Direct/Expanded/Focus
  mode definitions (both platforms reference this doc).
- Android: manifest permission + Room migration notes in `docs/android/`
  (DITTO_MANAGER / ARCHITECTURE as applicable).
- User-facing transport-settings docs if any exist for `TransportConfigView` /
  `TransportConfigSheet`.

## Open questions (resolve in review)

1. **iPadOS multicast entitlement** — Phase 0 outcome: ship toggle on iPadOS or macOS-only initially? - ship on all platforms.
2. **Multicast color alignment** — replace SwiftUI's existing teal multicast style with the extension's gold `#FFD60A` (proposed: yes, "mimic the extension"), or preserve teal for brand consistency? - ship with the gold color.
3. **Multicast defaults** — transport default OFF (proposed; beta + same-subnet)
   while LAN *discovery* (`lan.isMulticastEnabled`) rides the LAN flag, matching the extension. Confirm. - yes
4. **Advanced group/port/interface fields** — expose in native UIs (proposed: toggle + collapsed advanced section, retail-app validation) or on/off only? 
5. **Focus-mode blur** — skip the 140 ms 2 px blur on native (proposed: skip, keep dim-only) or implement? - skip just dim
6. **Android zoom max** — align to the extension's 2.0 (proposed) or keep 2.5? - align to 2.0
7. **Header Stop/Start Sync + status dot** — confirm out of scope (native apps surface sync controls elsewhere). out of scope

## Ordering

Phase 0 spikes first (they gate Phase 2's UI shape). Phases 1 (rendering) and 2
(transport config) are independent of each other and of 3–6 — Phases 1+2 can land
in either order, then 3 → 4 → 5 → 6 sequentially (each builds on the previous
layout/mode behavior). Per-phase PRs keep reviews small and honor the
fix-verification rule's "small batches" requirement.
