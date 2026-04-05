# Android Feature: Presence Viewer (Network Graph)

**Priority:** High  
**Complexity:** High  
**Status:** Not Started  
**Platforms with feature:** SwiftUI, .NET/Avalonia  

## Summary

Android is missing the interactive Presence Viewer — a network topology graph that visualizes Ditto peers as nodes with color-coded connection lines representing transport types (Bluetooth, LAN, P2P WiFi, WebSocket, Cloud). Both SwiftUI (SpriteKit) and .NET (SkiaSharp) have full implementations. Android needs an equivalent using Jetpack Compose Canvas.

## Current State in Android

- `ConnectedPeersScreen.kt` shows a grid of peer cards (local + remote) — this is the **Peers List** tab equivalent
- `MainStudioViewModel` already has `PeersUiState` with `localPeer` and `remotePeers` data
- `SystemRepository` already provides presence graph data via `peers` Flow
- **No network graph visualization exists**
- The subscription detail area currently only shows the peers list — no tab switching between Peers List / Presence Viewer / Settings

## What Needs to Be Built

### 1. Tab Structure in Subscription Detail Area

Both SwiftUI and .NET show three tabs when viewing Subscriptions:

| Tab | Content | Status in Android |
|-----|---------|-------------------|
| Peers List | Grid of peer cards | Exists (`ConnectedPeersScreen`) |
| Presence Viewer | Interactive network graph | **MISSING** |
| Settings | Transport configuration | Partially exists in `DatabaseEditorScreen` |

**Implementation:** Add a `TabRow` or segmented control to the subscriptions detail area that switches between these three views. Reference SwiftUI's `SubscriptionDetailsView` which uses a native `TabView` with `.tabViewStyle(.automatic)`.

### 2. Presence Graph Data Model

Create Kotlin equivalents of these models:

```kotlin
// New file: domain/model/PresenceGraphData.kt

data class PresenceNode(
    val peerKey: String,
    val deviceName: String,
    val isLocal: Boolean,
    val isCloudNode: Boolean = false,
    val isConnectedToCloud: Boolean = false,
    val os: PeerOS? = null
)

data class PresenceEdge(
    val peerKey1: String,
    val peerKey2: String,
    val connectionType: ConnectionType,  // reuse existing enum
    val connectionId: String
) {
    // For deduplication: sorted pair + type
    val normalizedPairKey: String
        get() = listOf(peerKey1, peerKey2).sorted().joinToString("-") + "-$connectionType"
}

data class PresenceGraphSnapshot(
    val nodes: List<PresenceNode>,
    val allEdges: List<PresenceEdge>,
    val localPeerKey: String
) {
    val deduplicatedEdges: List<PresenceEdge>
        get() = allEdges.distinctBy { it.normalizedPairKey }
    
    fun filterToDirectConnections(): PresenceGraphSnapshot {
        val directEdges = deduplicatedEdges.filter { 
            it.peerKey1 == localPeerKey || it.peerKey2 == localPeerKey 
        }
        val directPeerKeys = directEdges.flatMap { listOf(it.peerKey1, it.peerKey2) }.toSet()
        return copy(
            nodes = nodes.filter { it.peerKey in directPeerKeys },
            allEdges = directEdges
        )
    }
}
```

**Reference files:**
- SwiftUI: `SwiftUI/EdgeStudio/Components/PresenceViewer/PresenceProtocols.swift`
- .NET: `dotnet/src/EdgeStudio.Shared/Models/PresenceGraphData.cs`

### 3. Network Layout Engine (BFS Ring Layout)

Port the layout algorithm that positions peers in concentric rings:

```kotlin
// New file: domain/layout/NetworkLayoutEngine.kt

data class NodePosition(val x: Float, val y: Float)

object NetworkLayoutEngine {
    fun computeLayout(snapshot: PresenceGraphSnapshot): Map<String, NodePosition> {
        // 1. BFS from local peer to assign ring numbers
        // 2. Ring 0: local peer at (0,0)
        // 3. Ring 1: directly connected peers, evenly spaced on circle
        //    - Radius: max(124f, peerCount * 80f / (2 * PI))
        //    - Sort using greedy double-ended path for adjacency
        // 4. Ring 2+: multi-hop peers behind their parent
        //    - Arc-based positioning within parent's angular range
        // 5. Return map of peerKey -> (x, y) position
    }
}
```

**Algorithm details (from SwiftUI's NetworkLayoutEngine.swift):**
- **Ring radii:** Base = 124px, increment = 101px per ring
- **Minimum radius:** `peerCount * 80 / (2 * PI)` to prevent overlaps
- **Ring 1 ordering:** Greedy double-ended path algorithm — start with highest-degree node, alternately extend at head/tail prioritizing neighbors with most connections
- **Ring 2+ positioning:** Group by BFS parent, distribute within parent's angular arc (max 60 degrees), minimum 15 degree separation

**Reference files:**
- SwiftUI: `SwiftUI/EdgeStudio/Components/PresenceViewer/NetworkLayoutEngine.swift`
- .NET: `dotnet/src/EdgeStudio.Shared/Services/NetworkLayoutEngine.cs`

### 4. PresenceViewerViewModel

```kotlin
// New file: viewmodel/PresenceViewerViewModel.kt

class PresenceViewerViewModel(
    private val systemRepository: ISystemRepository
) : ViewModel() {
    val snapshot: StateFlow<PresenceGraphSnapshot?>
    val positions: StateFlow<Map<String, NodePosition>>
    val zoomLevel: MutableStateFlow<Float> = MutableStateFlow(1.4f)
    val showDirectOnly: MutableStateFlow<Boolean> = MutableStateFlow(false)
    
    fun startObserving()   // Register presence observer
    fun stopObserving()    // Cancel observer
    fun zoomIn()           // += 0.15f, max 3.0f
    fun zoomOut()          // -= 0.15f, min 0.3f
    fun resetZoom()        // = 1.4f
}
```

**Reference files:**
- .NET: `dotnet/src/EdgeStudio/ViewModels/PresenceViewerViewModel.cs`

### 5. Compose Canvas Rendering

Create the graph visualization using Jetpack Compose `Canvas`:

```kotlin
// New file: ui/mainstudio/PresenceViewerScreen.kt

@Composable
fun PresenceViewerScreen(viewModel: PresenceViewerViewModel) {
    Box(modifier = Modifier.fillMaxSize()) {
        // Main graph canvas with gesture handling
        PresenceGraphCanvas(
            snapshot = viewModel.snapshot.collectAsState(),
            positions = viewModel.positions.collectAsState(),
            zoomLevel = viewModel.zoomLevel.collectAsState()
        )
        
        // Legend overlay (bottom-left)
        ConnectionTypeLegend(modifier = Modifier.align(Alignment.BottomStart))
        
        // Controls overlay (bottom-right)  
        GraphControls(
            zoomLevel = viewModel.zoomLevel,
            showDirectOnly = viewModel.showDirectOnly,
            onZoomIn = viewModel::zoomIn,
            onZoomOut = viewModel::zoomOut,
            onResetZoom = viewModel::resetZoom
        )
    }
}
```

### 6. Visual Design Specifications

#### Node Rendering
- **Shape:** Rounded pill/capsule (RoundedCornerShape(14.dp))
- **Height:** 28.dp, width = text width + 24.dp padding
- **Local peer:** Blue background (`#4285F4`), label "Me"
- **Remote peers:** Green background (`#4CAF50`), label = device name (max 16 chars + ellipsis)
- **Cloud node:** Purple background (`#9C27B0`), label "Ditto Cloud"
- **Text:** White, 11sp, default typeface

#### Connection Lines (Edges)
Draw using `Canvas` with `drawPath()` and `PathEffect.dashPathEffect()`:

| Transport | Color | Dash Pattern (on, off) |
|-----------|-------|----------------------|
| Bluetooth | `#0066D9` (blue) | [3, 3] |
| LAN | `#0D8540` (green) | [16, 4] |
| P2P WiFi | `#C71A38` (red) | [8, 4] |
| WebSocket | `#D97A00` (orange) | [10, 3, 3, 3] |
| Cloud | `#7326B8` (purple) | [8, 4] |

- **Line width:** 2.dp (3.dp when highlighted)
- **Path type:** Quadratic Bezier curves (not straight lines)
- **Multiple connections between same peers:** Offset perpendicular to line by +/- 12px
- **Non-local edges:** Add outward curve (up to 90px) for visual separation

#### Legend (Bottom-Left Overlay)
- Semi-transparent black background (`Color.Black.copy(alpha = 0.7f)`)
- Header: "Connection Types" in 10sp lighter gray
- 5 entries: colored dashed line sample + label text
- Corner radius: 8.dp, padding: 12.dp

#### Controls (Bottom-Right Overlay)
- **"Direct Only" toggle:** Switch + label in pill background
- **Zoom controls:** [-] button, percentage text, [+] button, reset button
- Semi-transparent black background

### 7. Gesture Handling

```kotlin
Modifier
    .pointerInput(Unit) {
        detectTransformGestures { _, pan, zoom, _ ->
            // Pan: offset += pan / currentZoom
            // Pinch zoom: zoomLevel *= zoom (clamped 0.3-3.0)
        }
    }
    .pointerInput(Unit) {
        detectDragGestures { change, _ ->
            // Hit test: find node under finger
            // If node found: drag node, update connected edges
            // If no node: pan the canvas
        }
    }
```

### 8. Animation

Use Compose `Animatable` or `animateFloatAsState` for:
- **Node appearing:** Scale 0.5 -> 1.0, alpha 0 -> 1 (400ms ease-out)
- **Node disappearing:** Scale 1.0 -> 0.5, alpha 1 -> 0 (300ms ease-in)
- **Position changes:** Animate x/y with spring or exponential interpolation (500ms)
- **Edge opacity:** Match endpoint node opacity (minimum of both)

### 9. Empty State

When no peers are connected, show centered:
- Graph icon (Material Icons)
- "Waiting for peer connections..."
- "Start sync to see the mesh network"

Reference: .NET's `PresenceViewerView.axaml` empty state overlay.

## Key Reference Files

### SwiftUI
- `SwiftUI/EdgeStudio/Components/PresenceViewer/PresenceNetworkScene.swift` — Core scene (rendering + layout + interaction)
- `SwiftUI/EdgeStudio/Components/PresenceViewer/NetworkLayoutEngine.swift` — BFS ring layout algorithm
- `SwiftUI/EdgeStudio/Components/PresenceViewer/PeerNode.swift` — Node visual
- `SwiftUI/EdgeStudio/Components/PresenceViewer/ConnectionLine.swift` — Edge visual with dash patterns
- `SwiftUI/EdgeStudio/Components/PresenceViewer/PresenceProtocols.swift` — Data abstractions
- `SwiftUI/EdgeStudio/Views/StudioView/Details/PresenceViewerSK.swift` — SwiftUI wrapper + ViewModel

### .NET/Avalonia
- `dotnet/src/EdgeStudio/Controls/PresenceGraphControl.cs` — Custom control with SkiaSharp rendering
- `dotnet/src/EdgeStudio/Controls/PresenceGraphRenderer.cs` — Drawing logic (colors, shapes, legend)
- `dotnet/src/EdgeStudio/Controls/PresenceGraphAnimator.cs` — Animation state machine
- `dotnet/src/EdgeStudio/Controls/AnimatedNodeState.cs` — Per-node animation tracking
- `dotnet/src/EdgeStudio.Shared/Services/NetworkLayoutEngine.cs` — Layout algorithm (C# port)
- `dotnet/src/EdgeStudio.Shared/Models/PresenceGraphData.cs` — Data models
- `dotnet/src/EdgeStudio/ViewModels/PresenceViewerViewModel.cs` — ViewModel
- `dotnet/src/EdgeStudio/Views/StudioView/Details/PresenceViewerView.axaml` — XAML view

### Android (existing files to modify)
- `android/app/src/main/java/com/costoda/dittoedgestudio/viewmodel/MainStudioViewModel.kt` — Add presence observer
- `android/app/src/main/java/com/costoda/dittoedgestudio/ui/mainstudio/MainStudioScreen.kt` — Add tab structure
- `android/app/src/main/java/com/costoda/dittoedgestudio/data/repository/SystemRepository*.kt` — Extend for graph snapshots

## Acceptance Criteria

- [ ] Three-tab layout in subscriptions detail: Peers List | Presence Viewer | Settings
- [ ] BFS-based ring layout positions local peer at center, direct peers on ring 1
- [ ] Nodes rendered as colored pills with device names
- [ ] Edges rendered as dashed Bezier curves with transport-specific colors
- [ ] Pinch-to-zoom (0.3x - 3.0x) and pan gestures
- [ ] Node dragging updates connected edges in real-time
- [ ] "Direct Only" toggle filters to local-connected peers only
- [ ] Zoom controls (in/out/reset/percentage display)
- [ ] Connection type legend overlay
- [ ] Empty state when no peers connected
- [ ] Real-time updates when peers join/leave
- [ ] Smooth animations for node appear/disappear/reposition
- [ ] Synthetic cloud node when connected to Ditto Cloud
