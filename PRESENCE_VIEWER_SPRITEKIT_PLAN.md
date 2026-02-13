# Presence Viewer SpriteKit Redesign - Implementation Plan

## Executive Summary

Build a dynamic network diagram presence viewer using **SpriteKit** to visualize Ditto peer connections in real-time. Features accessibility-first design (dash patterns for connection types), modern animations, test mode with 30 devices, and interactive controls (zoom/pan/drag).

## Current State Analysis

### Existing SpriteKit Components (Keep and Enhance)
✅ **Sprites to Keep:**
- `MobilePhoneNode.swift` - Mobile phone sprite
- `LaptopNode.swift` - Laptop sprite
- `CloudNode.swift` - Cloud sprite
- `ServerNode.swift` - Server sprite
- `FloatingSquaresLayer.swift` - Background animation layer (starfield)
- `PixelPhoneTexture.swift` - Phone texture generator
- `PixelLaptopTexture.swift` - Laptop texture generator
- `PixelCloudTexture.swift` - Cloud texture generator
- `PixelServerTexture.swift` - Server texture generator

✅ **Components to Refactor:**
- `PresenceViewerSK.swift` - Move to separate file, needs ViewModel
- `PresenceVisualizerScene.swift` - Enhance with network diagram logic
- `PresenceViewerTab.swift` - Update to use new ViewModel

### Architecture Changes Needed

#### Move PresenceViewerSK to Separate File
**Current:** PresenceViewerSK is inline, MainStudioView is getting too large
**New Structure:**
```
SwiftUI/Edge Debug Helper/
├── Components/
│   ├── PresenceViewer/
│   │   ├── PresenceViewerSK.swift                    // View (moved from inline)
│   │   ├── PresenceViewerViewModel.swift             // ViewModel (new)
│   │   ├── PresenceNetworkScene.swift                // Scene (replaces PresenceVisualizerScene)
│   │   ├── PeerNode.swift                            // Base peer node class (new)
│   │   ├── ConnectionLine.swift                      // Connection line renderer (new)
│   │   ├── NetworkLayoutEngine.swift                 // Layout algorithm (new)
│   │   └── MockPresenceDataGenerator.swift           // Test mode data (new)
│   ├── Sprites/                                      // Keep existing sprites
│   │   ├── MobilePhoneNode.swift
│   │   ├── LaptopNode.swift
│   │   ├── CloudNode.swift
│   │   ├── ServerNode.swift
│   │   └── FloatingSquaresLayer.swift
│   └── Textures/                                     // Keep existing textures
│       ├── PixelPhoneTexture.swift
│       ├── PixelLaptopTexture.swift
│       ├── PixelCloudTexture.swift
│       └── PixelServerTexture.swift
```

## Requirements

### FR1: Ditto Presence Graph Integration
- Use `DittoManager` to access Ditto instance
- Register observer: `ditto.presence.observe { presenceGraph in ... }`
- Access `presenceGraph.localPeer` for local device
- Access `presenceGraph.remotePeers` for connected peers
- Parse `DittoPeer` properties:
  - `peerKey`: Unique identifier (String)
  - `deviceName`: Display name (String)
  - `isConnectedToDittoCloud`: Cloud connection flag (Bool)
  - `connections`: Array of `DittoConnection` objects

### FR2: Connection Type Visualization (Accessibility-First)

**SpriteKit Line Rendering with Dash Patterns:**

| Connection Type | Color (Secondary) | Dash Pattern (SpriteKit) | Label | Bandwidth Context |
|----------------|-------------------|--------------------------|-------|-------------------|
| Bluetooth | Blue (#0066FF) | `[2, 3]` - Small dashes | Bluetooth | Low bandwidth |
| LAN (accessPoint) | Green (#00CC66) | `[12, 3]` - Long dashes | LAN | High bandwidth |
| P2P WiFi | Pink (#FF0099) | `[6, 3]` - Medium dashes | P2P WiFi | Medium bandwidth |
| WebSocket | Orange (#FF6600) | `[8, 2, 2, 2]` - Dash-dot | WebSocket | Variable bandwidth |
| Cloud | Purple (#9933FF) | Custom pattern with circles | Cloud | Cloud connection |

**SpriteKit Implementation:**
- Use `SKShapeNode` for connection lines
- Create custom path with dash patterns using `CGPathCreateCopyByDashingPath`
- For cloud connections: Draw line segments with small `SKShapeNode` circles at intervals
- Line width: 2pt (increases to 3pt on hover/selection)
- Alpha: 0.7 (increases to 1.0 on hover/selection)

### FR3: Peer Node Display

**Node Type Selection (Based on Device Type):**
When device type is determinable:
- iOS devices → Use `MobilePhoneNode`
- macOS devices → Use `LaptopNode`
- Ditto Cloud → Use `CloudNode`
- Servers/unknown → Use `ServerNode`

**Device Name Display:**
- Show device name in `SKLabelNode` below sprite
- Font: System font, size 12pt
- Color: White with drop shadow for readability
- Dynamic width: Label auto-sizes to fit device name
- Max width: 150pt (truncate with ellipsis if longer)

**Local Peer Styling:**
- Use local peer's device name (from `localPeer.deviceName`)
- Larger scale: 1.3x compared to remote peers
- Blue glow effect: `SKEffectNode` with glow filter
- Always at center of diagram (position 0, 0 in scene)
- Different rotation: Face forward (zRotation = 0)

**Cloud Connection Node:**
- If peer has `isConnectedToDittoCloud = true`, show connection to cloud
- Create special `CloudNode` instance at fixed position
- Label: "Ditto Cloud"
- Use purple connection line with circle pattern

### FR4: Test Mode vs Production Mode

**ViewModel State Management:**
```swift
@Observable
class PresenceViewerViewModel {
    var isTestMode: Bool = false
    var testModeUpdateTimer: Timer?
    var presenceObserver: DittoObserver?
    var peers: [String: DittoPeer] = [:]
    var localPeerKey: String?

    // Scene reference
    weak var scene: PresenceNetworkScene?
}
```

**Test Mode Features:**
- Toggle control in SwiftUI view (above SpriteView)
- When enabled:
  - Stop Ditto presence observer
  - Start mock data generator
  - Generate 30 peer devices with varied properties
  - Update every 7 seconds (add/remove 1-3 peers randomly)
- When disabled:
  - Stop mock data generator
  - Resume Ditto presence observer
  - Clear test peers and reload real data

**Mock Data Generator:**
```swift
class MockPresenceDataGenerator {
    func generate30Peers() -> [MockPeer]
    func simulateChange(currentPeers: [MockPeer]) -> [MockPeer]

    struct MockPeer {
        let peerKey: String
        let deviceName: String
        let deviceType: DeviceType // phone, laptop, server, cloud
        let connections: [MockConnection]
        let isConnectedToDittoCloud: Bool
    }

    struct MockConnection {
        let type: DittoConnectionType
        let id: String
    }
}
```

**Device Name Examples for Test Mode:**
- iPhones: "iPhone 17 Pro Max (sim)", "iPhone 16 (sim)", "iPhone 15 Pro (sim)"
- iPads: "iPad Pro 12.9\" (sim)", "iPad mini (A17 Pro) (sim)", "iPad Air (sim)"
- Macs: "MacBook Pro 16\" M3", "MacBook Air M2", "iMac 24\" M3", "Mac Studio"
- Others: "Windows Desktop", "Surface Pro 9", "Galaxy S24", "Pixel 8 Pro", "Linux Server", "Raspberry Pi 5"

### FR5: Interactive Controls

**Zoom (Already Implemented in PresenceViewerSK):**
- Current implementation: +/- buttons, zoom level indicator
- Enhance: Add scroll wheel support in SpriteKit scene
- Range: 50% to 200%
- Apply to camera node: `cameraNode.setScale(zoomLevel)`

**Pan (New Feature):**
- Detect pan gesture in SpriteKit scene
- Update camera position: `cameraNode.position`
- Smooth momentum/inertia when releasing
- Use `SKAction.move` with easing

**Node Dragging (New Feature):**
- Override `touchesBegan` in scene to detect touch on peer node
- Track `touchesMoved` to update node position
- On `touchesEnded`, snap to new position or revert
- Update connected lines in real-time during drag
- Allow dragging local peer (center node)

**SpriteKit Gesture Handling:**
```swift
override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
    guard let touch = touches.first else { return }
    let location = touch.location(in: self)
    let touchedNodes = nodes(at: location)

    // Check if touched a peer node
    if let peerNode = touchedNodes.first(where: { $0 is PeerNode }) as? PeerNode {
        selectedNode = peerNode
        isDraggingNode = true
    } else {
        // Start panning
        isPanning = true
        lastPanLocation = location
    }
}

override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
    guard let touch = touches.first else { return }
    let location = touch.location(in: self)

    if isDraggingNode, let node = selectedNode {
        // Update node position
        node.position = location
        // Update connected lines
        updateConnectionsForNode(node)
    } else if isPanning {
        // Update camera position
        let delta = CGPoint(
            x: location.x - lastPanLocation.x,
            y: location.y - lastPanLocation.y
        )
        camera?.position.x -= delta.x
        camera?.position.y -= delta.y
        lastPanLocation = location
    }
}
```

### FR6: Layout Algorithm (Circular Topology)

**NetworkLayoutEngine Class:**
```swift
class NetworkLayoutEngine {
    struct Ring {
        let radius: CGFloat
        let peerKeys: [String]
    }

    func calculateLayout(
        localPeer: String,
        peers: [String: DittoPeer],
        connections: [Connection]
    ) -> [String: CGPoint] {
        // Algorithm:
        // 1. Assign peers to rings using BFS from local peer
        // 2. Calculate ring radii (200pt, 350pt, 500pt, ...)
        // 3. Distribute peers evenly around each ring
        // 4. Optimize angles to minimize line crossings
        // 5. Return position dictionary
    }

    private func assignRings(
        localPeer: String,
        connections: [Connection]
    ) -> [Ring] {
        // BFS from local peer
        // Ring 0: Local peer
        // Ring 1: Direct connections to local peer
        // Ring 2: Connections to ring 1 peers
        // Ring 3+: Further connections
    }

    private func distributeOnRing(
        peerKeys: [String],
        radius: CGFloat,
        optimizeFor connections: [Connection]
    ) -> [String: CGFloat] {
        // Return peerKey -> angle mapping
        // Optimize angle distribution to minimize crossings
    }
}
```

**Ring Radii:**
- Ring 0 (local): radius = 0pt (center)
- Ring 1: radius = 220pt
- Ring 2: radius = 400pt
- Ring 3: radius = 580pt
- Ring 4+: radius = 760pt, 940pt, ...

**Collision Detection:**
- Minimum angular separation: 15° between adjacent nodes
- If collision detected, adjust angles slightly
- May expand ring radius if too many nodes

**Line Routing:**
- Use `SKShapeNode` with `CGPath`
- For same-ring connections: Use curved path (arc)
- For cross-ring connections: Use quadratic or cubic Bézier curve
- Control points positioned to avoid crossing other nodes

### FR7: Connection Line Rendering (SpriteKit)

**ConnectionLine Class:**
```swift
class ConnectionLine: SKNode {
    let fromPeerKey: String
    let toPeerKey: String
    let connectionType: DittoConnectionType

    private var shapeNode: SKShapeNode
    private var dashPattern: [CGFloat]
    private var lineColor: SKColor

    init(
        from: String,
        to: String,
        type: DittoConnectionType,
        fromPos: CGPoint,
        toPos: CGPoint
    ) {
        // Set color and dash pattern based on type
        // Create SKShapeNode with path
        // Apply dash pattern using CGPathCreateCopyByDashingPath
    }

    func updatePath(fromPos: CGPoint, toPos: CGPoint) {
        // Recalculate Bézier curve
        // Update shapeNode.path
    }

    func setHighlighted(_ highlighted: Bool) {
        // Increase line width and alpha when highlighted
        shapeNode.strokeColor = highlighted ? lineColor.withAlphaComponent(1.0) : lineColor.withAlphaComponent(0.7)
        shapeNode.lineWidth = highlighted ? 3.0 : 2.0
    }
}
```

**Dash Pattern Implementation (Core Graphics):**
```swift
func createDashedPath(
    from: CGPoint,
    to: CGPoint,
    controlPoint: CGPoint,
    dashPattern: [CGFloat]
) -> CGPath {
    let path = CGMutablePath()
    path.move(to: from)
    path.addQuadCurve(to: to, control: controlPoint)

    // Apply dash pattern
    let dashedPath = path.copy(
        dashingWithPhase: 0,
        lengths: dashPattern
    )

    return dashedPath
}
```

**Cloud Connection Pattern (Custom):**
- Create path segments with circles
- Use multiple `SKShapeNode` objects:
  - Dashed line: Main connection line
  - Circles: Small filled circles at intervals along path
- Calculate circle positions by sampling Bézier curve at regular intervals

**Future: Packet Animation:**
- Store connection line paths as array of CGPoints
- Create `PacketNode` as small `SKSpriteNode` (colored square)
- Animate along path using `SKAction.follow()`
- Color packet based on connection type

### FR8: Animations (SpriteKit Actions)

**Peer Appearance Animation:**
```swift
func animatePeerAppearance(node: SKNode) {
    // Initial state
    node.alpha = 0.0
    node.setScale(0.5)
    node.position = centerPosition // Start at center

    // Animate to final state
    let fadeIn = SKAction.fadeIn(withDuration: 0.4)
    let scaleUp = SKAction.scale(to: 1.0, duration: 0.4)
    let moveToPosition = SKAction.move(to: finalPosition, duration: 0.4)

    let group = SKAction.group([fadeIn, scaleUp, moveToPosition])
    group.timingMode = .easeOut
    node.run(group)
}
```

**Peer Disappearance Animation:**
```swift
func animatePeerDisappearance(node: SKNode, completion: @escaping () -> Void) {
    // Animate to center
    let fadeOut = SKAction.fadeOut(withDuration: 0.3)
    let scaleDown = SKAction.scale(to: 0.5, duration: 0.3)
    let moveToCenter = SKAction.move(to: centerPosition, duration: 0.3)

    let group = SKAction.group([fadeOut, scaleDown, moveToCenter])
    group.timingMode = .easeIn

    let remove = SKAction.removeFromParent()
    let sequence = SKAction.sequence([group, remove])

    node.run(sequence, completion: completion)
}
```

**Connection Line Draw Animation:**
```swift
func animateLineDrawing(line: ConnectionLine) {
    // Use stroke animation
    // Start with strokeEnd = 0.0
    // Animate to strokeEnd = 1.0

    let draw = SKAction.customAction(withDuration: 0.5) { node, time in
        let progress = time / 0.5
        // Update line path stroke progress
    }

    draw.timingMode = .easeInEaseOut
    line.run(draw)
}
```

**Staggered Animation:**
- When multiple peers appear simultaneously, stagger their animations
- Delay each animation by 50ms: `SKAction.wait(forDuration: 0.05 * index)`

**Hover/Selection Effects:**
- Detect mouse hover using `mouseEntered`/`mouseExited` (macOS)
- Scale node slightly: `SKAction.scale(to: 1.1, duration: 0.15)`
- Increase shadow intensity
- Highlight connected lines

**Smooth Transitions:**
- When layout changes, animate nodes to new positions
- Use `SKAction.move(to:duration:)` with ease-in-out timing
- Update connection lines in parallel

### FR9: PeerNode Base Class

**Unified Peer Node Structure:**
```swift
class PeerNode: SKNode {
    let peerKey: String
    let deviceName: String
    let isLocal: Bool
    let deviceType: DeviceType

    private var spriteNode: SKSpriteNode // MobilePhoneNode, LaptopNode, etc.
    private var labelNode: SKLabelNode
    private var glowEffect: SKEffectNode?

    enum DeviceType {
        case phone
        case laptop
        case cloud
        case server
    }

    init(
        peerKey: String,
        deviceName: String,
        deviceType: DeviceType,
        isLocal: Bool = false
    ) {
        self.peerKey = peerKey
        self.deviceName = deviceName
        self.isLocal = isLocal
        self.deviceType = deviceType
        super.init()

        setupSprite()
        setupLabel()
        if isLocal {
            setupGlowEffect()
        }
    }

    private func setupSprite() {
        switch deviceType {
        case .phone:
            spriteNode = MobilePhoneNode()
        case .laptop:
            spriteNode = LaptopNode()
        case .cloud:
            spriteNode = CloudNode()
        case .server:
            spriteNode = ServerNode()
        }

        addChild(spriteNode)

        if isLocal {
            spriteNode.setScale(1.3)
        }
    }

    private func setupLabel() {
        labelNode = SKLabelNode(text: deviceName)
        labelNode.fontName = "Helvetica"
        labelNode.fontSize = 12
        labelNode.fontColor = .white
        labelNode.position = CGPoint(x: 0, y: -50)

        // Add shadow for readability
        let shadow = labelNode.copy() as! SKLabelNode
        shadow.fontColor = .black
        shadow.alpha = 0.5
        shadow.position = CGPoint(x: 1, y: -1)
        labelNode.addChild(shadow)

        addChild(labelNode)
    }

    private func setupGlowEffect() {
        glowEffect = SKEffectNode()
        glowEffect?.shouldEnableEffects = true

        let glow = CIFilter(name: "CIGaussianBlur")
        glow?.setValue(10.0, forKey: kCIInputRadiusKey)
        glowEffect?.filter = glow

        // Add blue glow color overlay
        let colorOverlay = SKSpriteNode(color: .blue, size: spriteNode.size)
        colorOverlay.alpha = 0.5
        colorOverlay.blendMode = .add
        glowEffect?.addChild(colorOverlay)

        insertChild(glowEffect!, at: 0)
    }

    func setHighlighted(_ highlighted: Bool) {
        let scale = isLocal ? 1.3 : 1.0
        let targetScale = highlighted ? scale * 1.1 : scale

        let scaleAction = SKAction.scale(to: targetScale, duration: 0.15)
        scaleAction.timingMode = .easeOut
        spriteNode.run(scaleAction)
    }
}
```

**Device Type Detection:**
```swift
func detectDeviceType(from deviceName: String) -> PeerNode.DeviceType {
    let lowerName = deviceName.lowercased()

    if lowerName.contains("iphone") || lowerName.contains("ipad") ||
       lowerName.contains("pixel") || lowerName.contains("galaxy") {
        return .phone
    } else if lowerName.contains("macbook") || lowerName.contains("imac") ||
              lowerName.contains("windows") || lowerName.contains("surface") {
        return .laptop
    } else if lowerName.contains("cloud") || lowerName.contains("ditto") {
        return .cloud
    } else {
        return .server
    }
}
```

### FR10: PresenceNetworkScene Implementation

**Scene Structure:**
```swift
class PresenceNetworkScene: SKScene {
    // ViewModel reference
    weak var viewModel: PresenceViewerViewModel?

    // Layers
    private var backgroundLayer: FloatingSquaresLayer?
    private var peerNodesLayer: SKNode = SKNode()
    private var connectionsLayer: SKNode = SKNode()

    // Camera
    private var cameraNode: SKCameraNode?

    // State
    private var peerNodes: [String: PeerNode] = [:]
    private var connectionLines: [String: ConnectionLine] = [:]
    private var layoutEngine: NetworkLayoutEngine = NetworkLayoutEngine()

    // Interaction
    private var selectedNode: PeerNode?
    private var isDraggingNode: Bool = false
    private var isPanning: Bool = false
    private var lastPanLocation: CGPoint = .zero

    override func didMove(to view: SKView) {
        setupCamera()
        setupLayers()
        setupBackground()
    }

    private func setupLayers() {
        connectionsLayer.zPosition = 0
        peerNodesLayer.zPosition = 10

        addChild(connectionsLayer)
        addChild(peerNodesLayer)
    }

    // Update from ViewModel
    func updatePresenceGraph(localPeer: DittoPeer, remotePeers: [DittoPeer]) {
        // Process peer additions/removals
        let newPeerKeys = Set([localPeer.peerKey] + remotePeers.map { $0.peerKey })
        let currentPeerKeys = Set(peerNodes.keys)

        // Remove disconnected peers
        for removedKey in currentPeerKeys.subtracting(newPeerKeys) {
            removePeer(key: removedKey)
        }

        // Add/update peers
        updatePeer(localPeer, isLocal: true)
        for peer in remotePeers {
            updatePeer(peer, isLocal: false)
        }

        // Update connections
        updateConnections(remotePeers: remotePeers)

        // Recalculate layout
        recalculateLayout()
    }

    private func updatePeer(_ peer: DittoPeer, isLocal: Bool) {
        if let existingNode = peerNodes[peer.peerKey] {
            // Update existing peer
            existingNode.labelNode.text = peer.deviceName
        } else {
            // Create new peer node
            let deviceType = detectDeviceType(from: peer.deviceName)
            let node = PeerNode(
                peerKey: peer.peerKey,
                deviceName: peer.deviceName,
                deviceType: deviceType,
                isLocal: isLocal
            )

            peerNodes[peer.peerKey] = node
            peerNodesLayer.addChild(node)

            // Animate appearance
            animatePeerAppearance(node: node)
        }
    }

    private func removePeer(key: String) {
        guard let node = peerNodes[key] else { return }

        animatePeerDisappearance(node: node) { [weak self] in
            self?.peerNodes.removeValue(forKey: key)
        }

        // Remove associated connections
        let connectionsToRemove = connectionLines.filter {
            $0.value.fromPeerKey == key || $0.value.toPeerKey == key
        }
        for (id, line) in connectionsToRemove {
            line.removeFromParent()
            connectionLines.removeValue(forKey: id)
        }
    }

    private func updateConnections(remotePeers: [DittoPeer]) {
        // Clear existing connections
        connectionLines.values.forEach { $0.removeFromParent() }
        connectionLines.removeAll()

        // Create new connections
        for peer in remotePeers {
            for connection in peer.connections {
                let connectionId = "\(peer.peerKey)-\(connection.id)"

                guard let fromNode = peerNodes[peer.peerKey],
                      let toNode = peerNodes[viewModel?.localPeerKey ?? ""] else {
                    continue
                }

                let line = ConnectionLine(
                    from: peer.peerKey,
                    to: viewModel?.localPeerKey ?? "",
                    type: connection.connectionType,
                    fromPos: fromNode.position,
                    toPos: toNode.position
                )

                connectionLines[connectionId] = line
                connectionsLayer.addChild(line)

                // Animate line drawing
                animateLineDrawing(line: line)
            }
        }
    }

    private func recalculateLayout() {
        guard let localKey = viewModel?.localPeerKey else { return }

        let positions = layoutEngine.calculateLayout(
            localPeer: localKey,
            peers: peerNodes,
            connections: Array(connectionLines.values)
        )

        // Animate nodes to new positions
        for (peerKey, position) in positions {
            guard let node = peerNodes[peerKey] else { continue }

            let move = SKAction.move(to: position, duration: 0.5)
            move.timingMode = .easeInEaseOut
            node.run(move)
        }

        // Update connection line paths
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.updateAllConnectionPaths()
        }
    }

    private func updateAllConnectionPaths() {
        for (_, line) in connectionLines {
            guard let fromNode = peerNodes[line.fromPeerKey],
                  let toNode = peerNodes[line.toPeerKey] else {
                continue
            }

            line.updatePath(fromPos: fromNode.position, toPos: toNode.position)
        }
    }

    // Touch handling (pan and drag)
    override func mouseDown(with event: NSEvent) {
        let location = event.location(in: self)
        let touchedNodes = nodes(at: location)

        if let peerNode = touchedNodes.first(where: { $0 is PeerNode }) as? PeerNode {
            selectedNode = peerNode
            isDraggingNode = true
            peerNode.setHighlighted(true)
        } else {
            isPanning = true
            lastPanLocation = location
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let location = event.location(in: self)

        if isDraggingNode, let node = selectedNode {
            node.position = location
            updateConnectionsForNode(node)
        } else if isPanning {
            let delta = CGPoint(
                x: location.x - lastPanLocation.x,
                y: location.y - lastPanLocation.y
            )
            camera?.position.x -= delta.x
            camera?.position.y -= delta.y
            lastPanLocation = location
        }
    }

    override func mouseUp(with event: NSEvent) {
        if let node = selectedNode {
            node.setHighlighted(false)
        }

        selectedNode = nil
        isDraggingNode = false
        isPanning = false
    }

    override func scrollWheel(with event: NSEvent) {
        // Zoom with scroll wheel
        guard let camera = cameraNode else { return }

        let zoomDelta: CGFloat = event.deltaY > 0 ? 0.05 : -0.05
        let newScale = max(0.5, min(2.0, camera.xScale + zoomDelta))

        let scaleAction = SKAction.scale(to: newScale, duration: 0.1)
        camera.run(scaleAction)

        // Notify ViewModel to update zoom UI
        viewModel?.updateZoomLevel(newScale)
    }

    private func updateConnectionsForNode(_ node: PeerNode) {
        // Update all connections connected to this node
        for (_, line) in connectionLines {
            if line.fromPeerKey == node.peerKey || line.toPeerKey == node.peerKey {
                guard let fromNode = peerNodes[line.fromPeerKey],
                      let toNode = peerNodes[line.toPeerKey] else {
                    continue
                }
                line.updatePath(fromPos: fromNode.position, toPos: toNode.position)
            }
        }
    }
}
```

### FR11: ViewModel Implementation

**PresenceViewerViewModel.swift:**
```swift
import Foundation
import SwiftUI
import DittoSwift
import SpriteKit

@Observable
class PresenceViewerViewModel {
    // Test mode state
    var isTestMode: Bool = false {
        didSet {
            if isTestMode {
                startTestMode()
            } else {
                stopTestMode()
            }
        }
    }

    // Zoom state
    var zoomLevel: CGFloat = 1.0

    // Ditto presence data
    var localPeer: DittoPeer?
    var remotePeers: [DittoPeer] = []
    var localPeerKey: String?

    // Scene reference
    weak var scene: PresenceNetworkScene?

    // Observers and timers
    private var presenceObserver: DittoObserver?
    private var testModeTimer: Timer?
    private var mockDataGenerator: MockPresenceDataGenerator?

    // Ditto instance
    private var ditto: Ditto?

    init(ditto: Ditto?) {
        self.ditto = ditto
        startProductionMode()
    }

    // MARK: - Production Mode (Real Ditto)

    func startProductionMode() {
        guard let ditto = ditto else { return }

        presenceObserver = ditto.presence.observe { [weak self] presenceGraph in
            guard let self = self else { return }

            DispatchQueue.main.async {
                self.localPeer = presenceGraph.localPeer
                self.remotePeers = Array(presenceGraph.remotePeers)
                self.localPeerKey = presenceGraph.localPeer.peerKey

                // Update scene
                self.scene?.updatePresenceGraph(
                    localPeer: presenceGraph.localPeer,
                    remotePeers: Array(presenceGraph.remotePeers)
                )
            }
        }
    }

    func stopProductionMode() {
        presenceObserver?.stop()
        presenceObserver = nil
    }

    // MARK: - Test Mode (Mock Data)

    func startTestMode() {
        stopProductionMode()

        mockDataGenerator = MockPresenceDataGenerator()

        // Generate initial data
        updateTestData()

        // Update every 7 seconds
        testModeTimer = Timer.scheduledTimer(withTimeInterval: 7.0, repeats: true) { [weak self] _ in
            self?.updateTestData()
        }
    }

    func stopTestMode() {
        testModeTimer?.invalidate()
        testModeTimer = nil
        mockDataGenerator = nil

        startProductionMode()
    }

    private func updateTestData() {
        guard let generator = mockDataGenerator else { return }

        let mockData = generator.generateUpdate()

        localPeer = mockData.localPeer
        remotePeers = mockData.remotePeers
        localPeerKey = mockData.localPeer.peerKey

        // Update scene
        scene?.updatePresenceGraph(
            localPeer: mockData.localPeer,
            remotePeers: mockData.remotePeers
        )
    }

    // MARK: - Zoom Control

    func zoomIn() {
        let newZoom = max(0.5, zoomLevel - 0.1)
        updateZoomLevel(newZoom)
    }

    func zoomOut() {
        let newZoom = min(2.0, zoomLevel + 0.1)
        updateZoomLevel(newZoom)
    }

    func updateZoomLevel(_ level: CGFloat) {
        zoomLevel = level
        scene?.camera?.setScale(level)
    }

    // MARK: - Cleanup

    deinit {
        stopProductionMode()
        stopTestMode()
    }
}
```

### FR12: Mock Data Generator

**MockPresenceDataGenerator.swift:**
```swift
import Foundation
import DittoSwift

class MockPresenceDataGenerator {
    private var mockPeers: [MockPeer] = []
    private let deviceNames: [String] = [
        "iPhone 17 Pro Max (sim)",
        "iPhone 17 Pro (sim)",
        "iPhone 16 Pro Max (sim)",
        "iPhone 16 (sim)",
        "iPad Pro 12.9\" (sim)",
        "iPad mini (A17 Pro) (sim)",
        "iPad Air (sim)",
        "MacBook Pro 16\" M3 Max",
        "MacBook Air M2",
        "iMac 24\" M3",
        "Mac Studio",
        "Mac mini M3",
        "Windows Desktop",
        "Surface Pro 9",
        "Galaxy S24 Ultra",
        "Pixel 8 Pro",
        "Linux Server",
        "Raspberry Pi 5",
        "Android Tablet",
        "Smart TV"
    ]

    struct MockPeer {
        let peerKey: String
        let deviceName: String
        let connections: [MockConnection]
        let isConnectedToDittoCloud: Bool
    }

    struct MockConnection {
        let type: String // "bluetooth", "accessPoint", "p2pWiFi", "webSocket"
        let id: String
    }

    struct MockPresenceData {
        let localPeer: DittoPeer
        let remotePeers: [DittoPeer]
    }

    init() {
        // Generate initial 30 peers
        mockPeers = generateInitialPeers(count: 30)
    }

    func generateUpdate() -> MockPresenceData {
        // Simulate peer changes
        simulateChange()

        // Convert to DittoPeer format
        let localPeer = createLocalPeer()
        let remotePeers = mockPeers.map { createDittoPeer(from: $0) }

        return MockPresenceData(localPeer: localPeer, remotePeers: remotePeers)
    }

    private func generateInitialPeers(count: Int) -> [MockPeer] {
        var peers: [MockPeer] = []

        for i in 0..<count {
            let deviceName = deviceNames[i % deviceNames.count]
            let suffix = i / deviceNames.count > 0 ? " (\(i / deviceNames.count + 1))" : ""

            // 40% single connection, 40% dual connection, 20% cloud
            let random = Double.random(in: 0...1)
            let connectionCount = random < 0.4 ? 1 : random < 0.8 ? 2 : 0
            let hasCloud = random >= 0.8

            var connections: [MockConnection] = []
            let types = ["bluetooth", "accessPoint", "p2pWiFi", "webSocket"]

            for j in 0..<connectionCount {
                connections.append(MockConnection(
                    type: types[Int.random(in: 0..<types.count)],
                    id: "conn-\(i)-\(j)"
                ))
            }

            peers.append(MockPeer(
                peerKey: "mock-peer-\(i)",
                deviceName: deviceName + suffix,
                connections: connections,
                isConnectedToDittoCloud: hasCloud
            ))
        }

        return peers
    }

    private func simulateChange() {
        // Remove 1-2 random peers
        let removeCount = Int.random(in: 1...2)
        for _ in 0..<removeCount where mockPeers.count > 20 {
            let index = Int.random(in: 0..<mockPeers.count)
            mockPeers.remove(at: index)
        }

        // Add 1-3 new peers
        let addCount = Int.random(in: 1...3)
        let newPeers = generateInitialPeers(count: addCount)
        mockPeers.append(contentsOf: newPeers)
    }

    private func createLocalPeer() -> DittoPeer {
        // Create mock local peer
        // Note: This requires accessing DittoPeer initializer or creating a mock object
        // For now, returning a placeholder
        fatalError("Need to create mock DittoPeer - may require protocol abstraction")
    }

    private func createDittoPeer(from mockPeer: MockPeer) -> DittoPeer {
        // Convert MockPeer to DittoPeer
        // Note: This requires accessing DittoPeer initializer or creating a mock object
        fatalError("Need to create mock DittoPeer - may require protocol abstraction")
    }
}

// ALTERNATIVE: Protocol-based approach if DittoPeer can't be mocked
protocol PeerProtocol {
    var peerKey: String { get }
    var deviceName: String { get }
    var connections: [ConnectionProtocol] { get }
    var isConnectedToDittoCloud: Bool { get }
}

protocol ConnectionProtocol {
    var type: String { get } // Map to DittoConnectionType
    var id: String { get }
}

// Then use protocol in ViewModel and Scene instead of concrete DittoPeer
```

### FR13: SwiftUI View Structure

**PresenceViewerSK.swift (Moved to Separate File):**
```swift
import SwiftUI
import SpriteKit
import DittoSwift

struct PresenceViewerSK: View {
    let ditto: Ditto?

    @State private var viewModel: PresenceViewerViewModel
    @State private var scene: PresenceNetworkScene?

    init(ditto: Ditto?) {
        self.ditto = ditto
        _viewModel = State(initialValue: PresenceViewerViewModel(ditto: ditto))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Test mode toggle
            testModeToggle

            // SpriteKit scene
            ZStack(alignment: .bottomTrailing) {
                // Main scene view
                SpriteKitSceneView(scene: $scene, viewModel: viewModel)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Zoom controls overlay
                zoomControls
                    .padding(16)

                // Legend overlay
                VStack {
                    Spacer()
                    HStack {
                        connectionLegend
                            .padding(16)
                        Spacer()
                    }
                }
            }
        }
        .onAppear {
            createScene()
        }
        .onDisappear {
            cleanupScene()
        }
    }

    // MARK: - Test Mode Toggle

    private var testModeToggle: some View {
        HStack {
            Spacer()

            Toggle("Test Mode", isOn: Binding(
                get: { viewModel.isTestMode },
                set: { viewModel.isTestMode = $0 }
            ))
            .toggleStyle(.switch)

            if viewModel.isTestMode {
                Text("Using Mock Data")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial)
                    .cornerRadius(8)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    // MARK: - Zoom Controls

    private var zoomControls: some View {
        HStack(spacing: 8) {
            // Zoom out
            Button(action: { viewModel.zoomOut() }) {
                FontAwesomeText(icon: ActionIcon.minus, size: 14)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.zoomLevel >= 2.0)

            // Zoom indicator
            Text("\(Int(viewModel.zoomLevel * 100))%")
                .font(.caption)
                .frame(width: 50)

            // Zoom in
            Button(action: { viewModel.zoomIn() }) {
                FontAwesomeText(icon: ActionIcon.plus, size: 14)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.zoomLevel <= 0.5)
        }
        .padding(8)
        .background(.ultraThinMaterial)
        .cornerRadius(8)
    }

    // MARK: - Connection Legend

    private var connectionLegend: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Connection Types")
                .font(.caption)
                .fontWeight(.semibold)

            LegendRow(color: .blue, pattern: "● ● ●", label: "Bluetooth")
            LegendRow(color: .green, pattern: "████ ████", label: "LAN")
            LegendRow(color: .pink, pattern: "██ ██ ██", label: "P2P WiFi")
            LegendRow(color: .orange, pattern: "███·███·", label: "WebSocket")
            LegendRow(color: .purple, pattern: "████ ○ ████", label: "Cloud")
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .cornerRadius(8)
    }

    // MARK: - Scene Management

    private func createScene() {
        let newScene = PresenceNetworkScene()
        newScene.size = CGSize(width: 1000, height: 800)
        newScene.scaleMode = .aspectFill
        newScene.viewModel = viewModel

        scene = newScene
        viewModel.scene = newScene
    }

    private func cleanupScene() {
        scene?.removeAllChildren()
        scene?.removeAllActions()
        scene?.removeFromParent()
        scene = nil
    }
}

// MARK: - Legend Row

struct LegendRow: View {
    let color: Color
    let pattern: String
    let label: String

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)

            Text(pattern)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(color)

            Text(label)
                .font(.caption)
        }
    }
}

// MARK: - SpriteKit Scene View (NSViewRepresentable)

struct SpriteKitSceneView: NSViewRepresentable {
    @Binding var scene: PresenceNetworkScene?
    let viewModel: PresenceViewerViewModel

    func makeNSView(context: Context) -> SKView {
        let skView = SKView()
        skView.ignoresSiblingOrder = true
        skView.showsFPS = false
        skView.showsNodeCount = false

        if let scene = scene {
            skView.presentScene(scene)
        }

        return skView
    }

    func updateNSView(_ nsView: SKView, context: Context) {
        if let scene = scene, nsView.scene !== scene {
            nsView.presentScene(scene)
        }
    }
}
```

**Update MainStudioView.swift:**
- Remove inline PresenceViewerSK definition
- Import new component:
```swift
// In syncDetailView():
.tabItem {
    Label("Presence Viewer", systemImage: "network")
}
PresenceViewerSK(ditto: dittoManager.dittoSelectedApp)
```

## Implementation Phases

### Phase 1: Refactoring and Structure (2-3 hours)
**Tasks:**
1. ✅ Move PresenceViewerSK to separate file
   - Create `SwiftUI/Edge Debug Helper/Components/PresenceViewer/PresenceViewerSK.swift`
   - Remove inline definition from MainStudioView
2. ✅ Create PresenceViewerViewModel
   - Create `SwiftUI/Edge Debug Helper/Components/PresenceViewer/PresenceViewerViewModel.swift`
   - Implement @Observable class with test mode and zoom state
3. ✅ Create PeerNode base class
   - Create `SwiftUI/Edge Debug Helper/Components/PresenceViewer/PeerNode.swift`
   - Integrate existing sprite nodes (MobilePhoneNode, etc.)
4. ✅ Reorganize sprite files
   - Move sprite nodes to `Components/Sprites/` folder
   - Move texture generators to `Components/Textures/` folder
5. Update MainStudioView to use new component

**Success Criteria:**
- PresenceViewerSK in separate file with ViewModel
- Project compiles successfully
- No regressions in existing functionality

### Phase 2: Scene Architecture (2-3 hours)
**Tasks:**
1. Create PresenceNetworkScene (rename/replace PresenceVisualizerScene)
   - Remove placeholder phone/laptop setup code
   - Add peer nodes layer and connections layer
   - Implement updatePresenceGraph() method stub
2. Create ConnectionLine class
   - SKNode subclass for rendering connection lines
   - Implement dash pattern rendering using Core Graphics
   - Create special cloud pattern renderer
3. Implement touch/mouse handling
   - Pan gesture for camera movement
   - Drag gesture for node repositioning
   - Scroll wheel for zoom
4. Connect scene to ViewModel
   - Pass scene reference to ViewModel
   - Pass ViewModel reference to scene

**Success Criteria:**
- Scene renders empty background with floating squares
- Camera pan and zoom work correctly
- ViewModel <-> Scene communication established

### Phase 3: Layout Algorithm (3-4 hours)
**Tasks:**
1. Create NetworkLayoutEngine class
   - Implement BFS ring assignment
   - Calculate ring radii and angles
   - Return position dictionary
2. Implement collision detection
   - Check minimum angular separation
   - Adjust positions to avoid overlaps
3. Test with mock peer data
   - Create simple test data (5, 15, 30 peers)
   - Verify circular layout
   - Measure layout calculation performance

**Success Criteria:**
- Layout engine assigns peers to correct rings
- No overlapping peer nodes
- Layout calculation < 50ms for 30 peers

### Phase 4: Peer Node Rendering (2-3 hours)
**Tasks:**
1. Implement PeerNode class
   - Use existing sprite nodes based on device type
   - Add device name label
   - Implement local peer glow effect
2. Implement device type detection
   - Parse device name to determine type
   - Select appropriate sprite node
3. Test peer node appearance
   - Create test scene with various device types
   - Verify labels render correctly
   - Verify local peer styling

**Success Criteria:**
- Peer nodes render with correct sprites
- Device names display below sprites
- Local peer has blue glow effect

### Phase 5: Connection Line Rendering (3-4 hours)
**Tasks:**
1. Implement ConnectionLine class
   - Create SKShapeNode with Bézier curve path
   - Apply dash patterns using Core Graphics
   - Implement cloud pattern (dashes + circles)
2. Implement line path calculation
   - Calculate control points for smooth curves
   - Handle same-ring and cross-ring connections
3. Implement line highlighting
   - Detect hover over line
   - Increase width and opacity
4. Test connection rendering
   - Create test scene with various connection types
   - Verify dash patterns are distinguishable
   - Verify cloud pattern renders correctly

**Success Criteria:**
- Lines render with correct dash patterns
- Cloud pattern shows dashes with circles
- Hover highlighting works
- Lines update when nodes move

### Phase 6: Animations (2-3 hours)
**Tasks:**
1. Implement peer appearance animation
   - Fade in from center
   - Scale from 0.5 to 1.0
   - Move to final position
2. Implement peer disappearance animation
   - Fade out toward center
   - Scale down to 0.5
3. Implement line drawing animation
   - Stroke animation effect
   - Stagger multiple lines
4. Implement smooth position transitions
   - Animate layout changes
   - Update connection lines during transition

**Success Criteria:**
- New peers fade in smoothly
- Removed peers fade out smoothly
- Lines animate drawing from local peer
- Layout changes animate smoothly

### Phase 7: Ditto Integration (2-3 hours)
**Tasks:**
1. Implement presence observer in ViewModel
   - Register observer on ditto.presence
   - Handle presence graph updates
   - Update scene when changes occur
2. Parse DittoPresenceGraph
   - Extract local peer data
   - Extract remote peers array
   - Map connection types
3. Handle peer lifecycle
   - Detect new peers (animate appearance)
   - Detect removed peers (animate disappearance)
   - Update existing peers
4. Handle cloud connections
   - Detect isConnectedToDittoCloud flag
   - Create special cloud node
   - Use cloud connection pattern

**Success Criteria:**
- Presence observer triggers updates
- Peer nodes appear/disappear based on presence
- Connection types map correctly
- Cloud connections render with special pattern

### Phase 8: Test Mode (2-3 hours)
**Tasks:**
1. Create MockPresenceDataGenerator
   - Generate 30 mock peers
   - Mix of device types and connection types
   - Periodic updates (add/remove peers)
2. Implement protocol abstraction (if needed)
   - Create PeerProtocol and ConnectionProtocol
   - Update ViewModel and Scene to use protocols
   - Support both real DittoPeer and mock data
3. Implement test mode toggle
   - Add toggle UI in PresenceViewerSK
   - Start/stop mock data generator
   - Stop/start Ditto observer
4. Test with 30 devices
   - Verify layout handles 30+ peers
   - Measure performance (60fps target)
   - Verify animations work smoothly

**Success Criteria:**
- Test mode generates 30 mock peers
- Toggle switches between test and production
- Layout and animations work with 30 peers
- Performance remains at 60fps

### Phase 9: Polish and Testing (2-3 hours)
**Tasks:**
1. Add connection legend UI
   - Create legend overlay
   - Show all connection types with patterns
   - Use glassmorphic styling
2. Implement hover tooltips
   - Detect mouse hover on peer nodes
   - Show device name and connection info
   - Position tooltip near cursor
3. Performance optimization
   - Profile with Instruments
   - Optimize layout calculations
   - Optimize line rendering
4. Manual testing
   - Test with real Ditto presence data
   - Test with test mode (30 devices)
   - Test all interactions (zoom, pan, drag)
   - Test animations
5. Update documentation
   - Update CLAUDE.md
   - Add code comments
   - Create troubleshooting guide

**Success Criteria:**
- Legend displays correctly
- Hover tooltips show peer info
- Performance at 60fps with 30 peers
- All manual tests pass
- Documentation complete

## Technical Considerations

### Performance Targets
- **60fps rendering** with 30 peers (16.67ms per frame)
- **Layout calculation** < 50ms for 30 peers
- **Animation smoothness** no dropped frames
- **Memory usage** < 100MB for scene + sprites

### SpriteKit Optimizations
- Use texture atlases for sprites (reduce draw calls)
- Batch connection lines into single SKNode where possible
- Use SKCropNode for efficient clipping
- Disable unnecessary physics simulation
- Use SKAction completion blocks efficiently

### Dash Pattern Implementation
**Core Graphics Approach:**
```swift
extension CGPath {
    func dashed(pattern: [CGFloat]) -> CGPath {
        return copy(dashingWithPhase: 0, lengths: pattern) ?? self
    }
}
```

**Cloud Pattern Approach:**
- Create custom path with circles at intervals
- Use `CGPath.addArc()` for circles
- Combine multiple paths into single `SKShapeNode`

### Device Type Detection
**Heuristics:**
- Contains "iPhone", "iPad", "Pixel", "Galaxy" → phone
- Contains "MacBook", "iMac", "Windows", "Surface" → laptop
- Contains "Cloud", "Ditto" → cloud
- Default → server

### Protocol Abstraction for Testing
If `DittoPeer` can't be mocked directly, create protocols:
```swift
protocol PeerProtocol {
    var peerKey: String { get }
    var deviceName: String { get }
    var connections: [ConnectionProtocol] { get }
    var isConnectedToDittoCloud: Bool { get }
}

extension DittoPeer: PeerProtocol {
    // DittoPeer already conforms
}

struct MockPeer: PeerProtocol {
    let peerKey: String
    let deviceName: String
    let connections: [ConnectionProtocol]
    let isConnectedToDittoCloud: Bool
}
```

## Risk Mitigation

### Risk 1: DittoPeer Mocking Difficulty
**Mitigation:**
- Use protocol abstraction (PeerProtocol)
- Or create MockDittoPresenceGraph that wraps mock data
- Or use dependency injection for presence observer

### Risk 2: Performance with 30 Peers
**Mitigation:**
- Use texture atlases to reduce draw calls
- Batch connection lines where possible
- Profile early and optimize hot paths
- Consider level-of-detail for distant nodes

### Risk 3: Layout Complexity
**Mitigation:**
- Start with simple circular layout
- Allow manual node repositioning as escape hatch
- Provide "Reset Layout" button if needed
- Test extensively with various peer counts

### Risk 4: Dash Patterns Not Distinguishable
**Mitigation:**
- User test with colorblind individuals
- Adjust dash lengths if needed
- Provide alternative indicators (line thickness, opacity)
- Allow customization in settings

## Questions for Clarification

1. **Device type detection**: Should we parse device names, or does Ditto provide device type info?
2. **Cloud node placement**: Should "Ditto Cloud" be a fixed position, or calculated by layout engine?
3. **Multiple connections**: If two peers have both Bluetooth AND LAN, draw two lines or one combined line?
4. **Zoom limits**: Confirm 50% to 200% range, or different limits?
5. **Local peer device name**: Use `ditto.deviceName` or custom label?
6. **Test mode UI placement**: Confirm toggle at top of view, or different location?
7. **Connection line thickness**: Should different connection types have different default thickness?
8. **Future packet animation**: Should this influence current architecture decisions?

## Success Metrics

### Quantitative Metrics
- [ ] Renders 30 peers at 60fps
- [ ] Layout calculation < 50ms for 30 peers
- [ ] Presence update to visual update < 200ms
- [ ] Memory usage < 100MB
- [ ] No dropped frames during animations

### Qualitative Metrics
- [ ] Dash patterns clearly distinguishable without color
- [ ] Layout minimizes line crossings
- [ ] Interactions feel responsive
- [ ] Device names readable at default zoom
- [ ] UI looks modern and polished

### User Acceptance Criteria
- [ ] Test mode generates 30 mock devices
- [ ] Toggle switches between test and production
- [ ] Zoom with +/- buttons and scroll wheel
- [ ] Pan by click-dragging canvas
- [ ] Drag individual peers to reposition
- [ ] Peers appear/disappear with animations
- [ ] Lines draw from local peer to targets
- [ ] Legend shows all connection types
- [ ] Works with real Ditto presence data

## Next Steps

1. ✅ Review and approve plan
2. ✅ Answer clarification questions
3. Begin Phase 1: Refactoring and Structure
4. Iterate through phases with check-ins
5. Final testing and documentation

---

**Plan Version:** 2.0 (SpriteKit Implementation)
**Created:** 2026-02-10
**Updated:** 2026-02-10
**Author:** Claude (Sonnet 4.5)
**Estimated Total Time:** 20-28 hours
**Priority:** High (Major Feature)
