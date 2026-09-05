import DittoSwift
import SpriteKit

/// Main SpriteKit scene for visualizing Ditto presence graph as a network diagram
class PresenceNetworkScene: SKScene {
    // MARK: - Nested Types

    /// Information about a peer-to-peer connection
    struct PeerConnectionInfo {
        let connectionId: String
        let from: String
        let to: String
        let type: DittoConnectionType
        let isCloud: Bool
    }

    // MARK: - Properties

    /// Configuration
    /// Initial zoom level to apply when scene first appears
    var initialZoomLevel: CGFloat = 1.0

    /// When true, only draw connection lines that involve the local peer directly
    var showDirectConnectedOnly = true

    /// Callbacks
    /// Called when user changes zoom level via scroll wheel or gestures
    var onZoomChanged: ((CGFloat) -> Void)?

    // Scene layers
    private var backgroundLayer: FloatingSquaresLayer?
    private var connectionsLayer: SKNode!
    private var peerNodesLayer: SKNode!

    /// Camera
    private var cameraNode: SKCameraNode!

    // State
    private var peerNodes: [String: PeerNode] = [:] // Use peerKeyString as key
    private var connectionLines: [String: ConnectionLine] = [:]
    private var localPeerKey: String?

    /// Cloud node is treated as a regular peer with this well-known key
    private let cloudNodeKey = "ditto-cloud-node"

    /// Scene readiness flag — set to true only after didMove(to:) completes setup
    private var isReady = false

    // Change detection to avoid unnecessary animations
    private var lastPeerKeysSnapshot: Set<String> = []
    private var lastConnectionsSnapshot: Set<String> = [] // "fromKey-toKey-type" format
    /// The filter mode that produced the last APPLIED layout. A flip changes the ring
    /// radius scale and the packing strategy, so it has to count as a topology change:
    /// when every peer is directly connected and there are no remote-to-remote edges,
    /// both snapshots below are identical across the toggle and the layout would
    /// otherwise be skipped, leaving the mesh at the wrong scale.
    private var lastDirectOnlySnapshot: Bool?

    // Interaction state
    private var selectedNode: PeerNode?
    private var isDraggingNode = false
    private var isPanning = false
    private var lastPanLocation: CGPoint = .zero
    private var hoveredNode: PeerNode?
    private var isUserInteracting = false // Tracks if user is actively dragging/panning
    private var needsLayoutAfterInteraction = false // Defer layout until interaction completes

    // Tap-to-isolate state — ports the Android tap-to-isolate UX. When a peer is the
    // current `highlightedNode`, all non-incident edges fade to 0.2 alpha and all peers
    // outside that peer's neighbourhood fade to 0.35, so the user can see at a glance
    // which peers it's connected to. Tapping empty canvas (or the same peer again)
    // clears the highlight.
    private var highlightedNode: PeerNode?
    private var pointerDownLocation: CGPoint = .zero
    private var didDragSincePointerDown = false
    private let tapMovementThreshold: CGFloat = 10.0
    private let focusDimEdgeAlpha: CGFloat = 0.2
    private let focusDimPeerAlpha: CGFloat = 0.35
    private let focusFadeDuration: TimeInterval = 0.2

    // Layout
    private let centerPosition = CGPoint.zero
    private var layoutEngine = NetworkLayoutEngine()
    private var currentRingAssignments: [Int: [String]] = [:]

    // MARK: - Scene Lifecycle

    override func didMove(to view: SKView) {
        super.didMove(to: view)

        // Make scene background transparent (like JavaScript version)
        backgroundColor = .clear

        setupCamera()
        setupLayers()
        setupBackground()

        // Apply initial zoom level from configuration
        cameraNode.setScale(initialZoomLevel)

        isReady = true
    }

    // MARK: - Setup

    private func setupCamera() {
        cameraNode = SKCameraNode()
        cameraNode.position = centerPosition
        addChild(cameraNode)
        camera = cameraNode
    }

    private func setupLayers() {
        // Create layers with proper z-ordering
        connectionsLayer = SKNode()
        connectionsLayer.name = "connectionsLayer"
        connectionsLayer.zPosition = 0
        addChild(connectionsLayer)

        peerNodesLayer = SKNode()
        peerNodesLayer.name = "peerNodesLayer"
        peerNodesLayer.zPosition = 10
        addChild(peerNodesLayer)
    }

    private func setupBackground() {
        // Add floating squares background (stars)
        backgroundLayer = FloatingSquaresLayer()
        // Dense star field with lots of movement
        backgroundLayer?.setup(in: self, count: 160)
        if let bg = backgroundLayer {
            bg.addToScene(self)
        }
    }

    // MARK: - Public API

    /// Update the presence graph visualization
    /// Now accepts PeerProtocol to support both real DittoPeer and mock test data
    func updatePresenceGraph(localPeer: PeerProtocol, remotePeers: [PeerProtocol]) {
        guard isReady else { return }
        // Store local peer key (use peerKeyString for dictionary lookups)
        localPeerKey = localPeer.peerKeyString

        // Determine which peers to add/remove/update
        let newPeerKeys = Set([localPeer.peerKeyString] + remotePeers.map(\.peerKeyString))
        let existingPeerKeys = Set(peerNodes.keys)

        // Remove disconnected peers (with animation)
        // Exclude cloud node since it's synthetic and managed separately
        let peersToRemove = existingPeerKeys.subtracting(newPeerKeys).filter { $0 != cloudNodeKey }
        for peerKey in peersToRemove {
            removePeer(key: peerKey)
        }

        // Add or update local peer
        updatePeer(localPeer, isLocal: true)

        // Add or update remote peers
        for peer in remotePeers {
            updatePeer(peer, isLocal: false)
        }

        // Cloud connectivity is only knowable for the local device — the SDK does not
        // expose remote peer cloud status through the presence graph.
        let hasCloudConnection = localPeer.isConnectedToDittoCloud

        // Add or remove cloud node (treated as a regular peer)
        if hasCloudConnection {
            // Create cloud as a synthetic peer if it doesn't exist
            if peerNodes[cloudNodeKey] == nil {
                let cloudPeer = PeerNode(
                    peerKey: cloudNodeKey,
                    deviceName: "Ditto Cloud",
                    deviceType: .cloud,
                    isLocal: false
                )
                peerNodes[cloudNodeKey] = cloudPeer
                peerNodesLayer.addChild(cloudPeer)
            }
        } else {
            // Remove cloud node if it exists
            if peerNodes[cloudNodeKey] != nil {
                removePeer(key: cloudNodeKey)
            }
        }

        // Update connections (including cloud connections)
        updateConnections(localPeer: localPeer, remotePeers: remotePeers, hasCloudConnection: hasCloudConnection)

        // Check if layout needs recalculation (only if topology changed)
        let currentPeerKeys = Set(peerNodes.keys)
        let currentConnections = Set(connectionLines.keys)

        let peersChanged = currentPeerKeys != lastPeerKeysSnapshot
        let connectionsChanged = currentConnections != lastConnectionsSnapshot
        let modeChanged = lastDirectOnlySnapshot != showDirectConnectedOnly

        if peersChanged || connectionsChanged || modeChanged {
            // Check if user is currently interacting with the scene
            if isUserInteracting {
                // Defer layout until interaction completes
                needsLayoutAfterInteraction = true
                Log.debug("User is interacting, deferring layout animation")
            } else {
                // Something changed, recalculate layout immediately
                recalculateLayout()
            }

            // Update snapshots
            lastPeerKeysSnapshot = currentPeerKeys
            lastConnectionsSnapshot = currentConnections
            lastDirectOnlySnapshot = showDirectConnectedOnly

            // After a topology change, re-apply the tap-to-isolate focus so brand-new
            // peers/edges respect the dim, and clear the focus entirely if the
            // highlighted peer left the mesh in this update.
            refreshFocusAfterTopologyChange()
        } else {
            // Nothing changed, skip animation
            Log.debug("No topology changes detected, skipping layout animation")
        }
    }

    // MARK: - Peer Management

    private func updatePeer(_ peer: PeerProtocol, isLocal: Bool) {
        let peerKeyString = peer.peerKeyString

        if let existingNode = peerNodes[peerKeyString] {
            // Update existing peer (e.g., device name changed)
            existingNode.updateDeviceName(peer.deviceName)
        } else {
            // Create new peer node
            let deviceType = PeerNode.DeviceType.detect(from: peer.deviceName)
            let node = PeerNode(
                peerKey: peerKeyString,
                deviceName: peer.deviceName,
                deviceType: deviceType,
                isLocal: isLocal
            )

            peerNodes[peerKeyString] = node
            peerNodesLayer.addChild(node)

            // Animate appearance
            animatePeerAppearance(node: node)
        }
    }

    private func removePeer(key: String) {
        guard let node = peerNodes[key] else { return }

        // Animate disappearance
        animatePeerDisappearance(node: node) { [weak self] in
            self?.peerNodes.removeValue(forKey: key)
        }

        // Remove associated connections
        let connectionsToRemove = connectionLines.filter {
            $0.value.fromPeerKey == key || $0.value.toPeerKey == key
        }

        for (connectionId, line) in connectionsToRemove {
            line.removeFromParent()
            connectionLines.removeValue(forKey: connectionId)
        }
    }

    // MARK: - Connection Management

    private func updateConnections(localPeer: PeerProtocol, remotePeers: [PeerProtocol], hasCloudConnection: Bool) {
        // Build what connections SHOULD exist (without clearing current ones yet)
        var expectedConnectionIds: Set<String> = []

        // Collect peer-to-peer connection IDs using actual endpoints (peerKeyString1/2).
        // Deduplicate globally by (pairKey, type) — the SDK returns A→B and B→A as separate
        // DittoConnection objects with the same type, so normalization prevents double entries.
        let localPeerKey = localPeer.peerKeyString
        var seenExpectedPairTypes: Set<String> = []
        for remotePeer in remotePeers {
            for connection in remotePeer.connectionProtocols {
                let pk1 = connection.peerKeyString1
                let pk2 = connection.peerKeyString2
                // Apply the same filter as the draw loop so change-detection stays in sync
                if showDirectConnectedOnly, pk1 != localPeerKey, pk2 != localPeerKey {
                    continue
                }
                let pairKey = [pk1, pk2].sorted().joined(separator: "_")
                let id = "\(pairKey)_\(connection.type)"
                guard seenExpectedPairTypes.insert(id).inserted else { continue }
                expectedConnectionIds.insert(id)
            }
        }

        // Add cloud connection ID — only the local peer's cloud connection is knowable.
        if hasCloudConnection {
            expectedConnectionIds.insert("cloud_\(localPeer.peerKeyString)")
        }

        // Check if connections have actually changed
        let currentConnectionIds = Set(connectionLines.keys)
        if expectedConnectionIds == currentConnectionIds {
            // Connections unchanged, skip rebuild to avoid flicker
            return
        }

        // Clear existing connections
        connectionLines.values.forEach { $0.removeFromParent() }
        connectionLines.removeAll()

        // Group connections by peer pair (to detect bidirectional connections)
        var peerPairConnections: [String: [PeerConnectionInfo]] = [:]

        // Collect all peer-to-peer connections using actual endpoints from peerKeyString1/2.
        // This correctly draws edges between the real participants of each connection, so
        // multihop peers (e.g. iPhone→DT0-4196→Mac) appear linked to their actual neighbor,
        // not falsely drawn as if they connect directly to the local device.
        // Deduplicate globally by (pairKey, type) — the SDK returns A→B and B→A as separate
        // DittoConnection objects with the same type but different IDs.
        var seenPairTypes: Set<String> = []
        for remotePeer in remotePeers {
            for connection in remotePeer.connectionProtocols {
                let pk1 = connection.peerKeyString1
                let pk2 = connection.peerKeyString2
                guard !pk1.isEmpty, !pk2.isEmpty else { continue }

                // When filtering to direct connections only, skip edges that don't
                // involve the local device (e.g., PeerA ↔ PeerB connections).
                if showDirectConnectedOnly, pk1 != localPeerKey, pk2 != localPeerKey {
                    continue
                }

                let pairKey = [pk1, pk2].sorted().joined(separator: "_")
                let connectionId = "\(pairKey)_\(connection.type)"

                guard seenPairTypes.insert(connectionId).inserted else { continue }

                if peerPairConnections[pairKey] == nil {
                    peerPairConnections[pairKey] = []
                }

                peerPairConnections[pairKey]?.append(PeerConnectionInfo(
                    connectionId: connectionId,
                    from: pk1,
                    to: pk2,
                    type: connection.type,
                    isCloud: false
                ))
            }
        }

        // Add cloud connection — only the local peer connects to Ditto Cloud from this device's
        // perspective. Remote peer cloud status is unknowable via the presence graph.
        if hasCloudConnection {
            let connectionId = "cloud_\(localPeer.peerKeyString)"
            let pairKey = [cloudNodeKey, localPeer.peerKeyString].sorted().joined(separator: "_")

            if peerPairConnections[pairKey] == nil {
                peerPairConnections[pairKey] = []
            }

            peerPairConnections[pairKey]?.append(PeerConnectionInfo(
                connectionId: connectionId,
                from: localPeer.peerKeyString,
                to: cloudNodeKey,
                type: .webSocket,
                isCloud: true
            ))
        }

        // Create connection lines with offsets for bidirectional connections
        for (_, connections) in peerPairConnections {
            let count = connections.count
            let baseOffset: CGFloat = 10.0 // Base offset distance

            for (index, conn) in connections.enumerated() {
                guard let fromNode = peerNodes[conn.from],
                      let toNode = peerNodes[conn.to] else
                {
                    continue
                }

                // Calculate offset for this line
                var offset: CGFloat = 0
                if count == 2 {
                    // Two connections: offset one up, one down
                    offset = (index == 0) ? baseOffset : -baseOffset
                } else if count > 2 {
                    // More than two: distribute evenly
                    let step = (baseOffset * 2) / CGFloat(count - 1)
                    offset = baseOffset - (step * CGFloat(index))
                }

                // Arc outward for peer-to-peer connections (neither endpoint is the local peer).
                // This routes the chord around the outside of the node cluster instead of
                // cutting through nodes that sit between the two ring-1 endpoints.
                let isPeerToPeer = conn.from != localPeerKey && conn.to != localPeerKey && !conn.isCloud
                let line = ConnectionLine(
                    from: conn.from,
                    to: conn.to,
                    type: conn.type,
                    fromPos: fromNode.position,
                    toPos: toNode.position,
                    offset: offset,
                    isCloudConnection: conn.isCloud,
                    arcOutward: isPeerToPeer
                )

                connectionLines[conn.connectionId] = line
                connectionsLayer.addChild(line)

                // Animate line drawing
                animateLineDrawing(line: line)
            }
        }
    }

    private func updateAllConnectionPaths() {
        // Update all connections (including cloud connections)
        for (_, line) in connectionLines {
            guard let fromNode = peerNodes[line.fromPeerKey],
                  let toNode = peerNodes[line.toPeerKey] else
            {
                continue
            }

            line.updatePath(fromPos: fromNode.position, toPos: toNode.position)
        }
    }

    private func updateConnectionsForNode(_ node: PeerNode) {
        // Update all connections involving this node (including cloud connections)
        for (_, line) in connectionLines {
            if line.fromPeerKey == node.peerKey || line.toPeerKey == node.peerKey {
                guard let fromNode = peerNodes[line.fromPeerKey],
                      let toNode = peerNodes[line.toPeerKey] else
                {
                    continue
                }
                line.updatePath(fromPos: fromNode.position, toPos: toNode.position)
            }
        }
    }

    // MARK: - Layout Algorithm

    private func recalculateLayout() {
        guard let localKey = localPeerKey else { return }

        // Build connection info for layout engine
        var connectionInfo: [NetworkLayoutEngine.ConnectionInfo] = []
        for (_, line) in connectionLines {
            connectionInfo.append(NetworkLayoutEngine.ConnectionInfo(
                fromPeer: line.fromPeerKey,
                toPeer: line.toPeerKey
            ))
        }

        // Measured pill widths feed ring capacity, so a mesh of long device names
        // packs fewer peers per orbit instead of overlapping them.
        var peerFootprints: [String: CGFloat] = [:]
        for (peerKey, node) in peerNodes {
            let width = node.calculateAccumulatedFrame().width
            if width > 0 {
                peerFootprints[peerKey] = width
            }
        }

        // Calculate BFS-based ring layout. With the "Direct Connected Only" filter off
        // the whole mesh is on screen, so switch to expanded mode: rings spread wider
        // and the mesh is packed into as many balanced concentric orbits as it needs,
        // rather than crowding every peer onto one ring.
        let layoutResult = layoutEngine.calculateLayout(
            localPeerKey: localKey,
            allPeers: peerNodes,
            connections: connectionInfo,
            radiusScale: showDirectConnectedOnly ? 1.0 : NetworkLayoutEngine.expandedRadiusScale,
            peerFootprints: peerFootprints
        )

        // Store ring assignments for connection routing optimization (Phase 3, Task 8)
        currentRingAssignments = layoutResult.ringAssignments

        // Animate all peers (including cloud) to their calculated positions WITH line updates
        let animationDuration: TimeInterval = 0.5

        for (peerKey, targetPosition) in layoutResult.positions {
            guard let peerNode = peerNodes[peerKey] else { continue }

            // Animate to new position
            let move = SKAction.move(to: targetPosition, duration: animationDuration)
            move.timingMode = .easeInEaseOut
            peerNode.run(move, withKey: "layoutMove")
        }

        // Create a custom action that updates connection lines continuously during animation
        // This runs at ~60 FPS, updating lines each frame to keep them attached to moving peers
        let updateAction = SKAction.customAction(withDuration: animationDuration) { [weak self] _, _ in
            self?.updateAllConnectionPaths()
        }

        // Run the update action on the scene
        run(updateAction, withKey: "lineUpdateDuringAnimation")

        // Final update after animation completes (cleanup). Structured Task so the
        // deferred work is visible to the concurrency runtime and is skipped if the
        // scene is torn down during the wait (weak self). Replaces a GCD
        // `asyncAfter`, which was both redundant (the scene is already @MainActor)
        // and uncancellable.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(animationDuration + 0.1))
            self?.updateAllConnectionPaths()
        }
    }

    // MARK: - Animations

    private func animatePeerAppearance(node: SKNode) {
        // Initial state: invisible, small, at center
        node.alpha = 0.0
        node.setScale(0.5)
        node.position = centerPosition

        // Target state: visible, normal size, at final position
        let fadeIn = SKAction.fadeIn(withDuration: 0.4)
        let scaleUp = SKAction.scale(to: 1.0, duration: 0.4)

        // Note: Position will be set by layout algorithm
        let group = SKAction.group([fadeIn, scaleUp])
        group.timingMode = .easeOut

        node.run(group, withKey: "appearAnimation")
    }

    private func animatePeerDisappearance(node: SKNode, completion: @escaping () -> Void) {
        // Animate to center, fade out, scale down
        let fadeOut = SKAction.fadeOut(withDuration: 0.3)
        let scaleDown = SKAction.scale(to: 0.5, duration: 0.3)
        let moveToCenter = SKAction.move(to: centerPosition, duration: 0.3)

        let group = SKAction.group([fadeOut, scaleDown, moveToCenter])
        group.timingMode = .easeIn

        let remove = SKAction.removeFromParent()
        let sequence = SKAction.sequence([group, remove])

        node.run(sequence) {
            completion()
        }
    }

    private func animateLineDrawing(line: ConnectionLine) {
        // Start with alpha 0, fade in
        line.alpha = 0.0

        let fadeIn = SKAction.fadeIn(withDuration: 0.4)
        fadeIn.timingMode = .easeInEaseOut

        line.run(fadeIn, withKey: "lineDrawAnimation")
    }

    // MARK: - Mouse/Touch Handling

    #if os(macOS)
    override func mouseDown(with event: NSEvent) {
        let location = event.location(in: self)
        let touchedNodes = nodes(at: location)

        // Mark that user is actively interacting
        isUserInteracting = true
        pointerDownLocation = location
        didDragSincePointerDown = false

        // Check if we touched a peer node (cloud is treated as a regular peer).
        // We don't apply the highlight here — that's deferred to mouseUp so we can
        // distinguish a tap (toggle persistent highlight) from a drag (move the peer).
        if let peerNode = touchedNodes.first(where: { $0 is PeerNode }) as? PeerNode {
            selectedNode = peerNode
            isDraggingNode = true
        } else {
            // Start panning the camera
            isPanning = true
            lastPanLocation = location
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let location = event.location(in: self)
        if hypot(location.x - pointerDownLocation.x, location.y - pointerDownLocation.y)
            > tapMovementThreshold
        {
            didDragSincePointerDown = true
        }

        if isDraggingNode, let node = selectedNode {
            // Drag the peer node (including cloud if it's selected)
            node.position = location

            // Update connected lines in real-time
            updateConnectionsForNode(node)
        } else if isPanning {
            // Pan the camera using event delta for smooth, accurate movement
            // Note: event.deltaX/deltaY provide raw mouse movement, immune to coordinate system changes
            cameraNode.position.x -= event.deltaX
            cameraNode.position.y += event.deltaY // Y is inverted in AppKit
        }
    }

    override func mouseUp(with event: NSEvent) {
        // Tap (no drag) → toggle persistent highlight on the peer that was hit, or
        // clear the highlight if the tap landed on empty canvas.
        if !didDragSincePointerDown {
            if let peer = selectedNode {
                toggleHighlight(for: peer)
            } else {
                clearHighlight()
            }
        }
        endInteraction()
    }

    override func mouseMoved(with event: NSEvent) {
        let location = event.location(in: self)
        let touchedNodes = nodes(at: location)

        // Find peer node under cursor.
        // Hover-highlight composes with persistent tap-highlight: never strip the
        // 1.1× scale from the persistently highlighted peer when the cursor leaves —
        // the user explicitly selected it and expects it to stay emphasized.
        if let peerNode = touchedNodes.first(where: { $0 is PeerNode }) as? PeerNode {
            if hoveredNode !== peerNode {
                if let prev = hoveredNode, prev !== highlightedNode {
                    prev.setHighlighted(false)
                }
                hoveredNode = peerNode
                if peerNode !== highlightedNode {
                    peerNode.setHighlighted(true)
                }
                NSCursor.pointingHand.set()
            }
        } else {
            if let hovered = hoveredNode, hovered !== highlightedNode {
                hovered.setHighlighted(false)
            }
            hoveredNode = nil
            NSCursor.arrow.set()
        }
    }

    override func mouseExited(with event: NSEvent) {
        // Clear hover state when mouse leaves scene (but keep tap-isolated peer's highlight).
        if let hovered = hoveredNode, hovered !== highlightedNode {
            hovered.setHighlighted(false)
        }
        hoveredNode = nil
        NSCursor.arrow.set()
    }

    override func scrollWheel(with event: NSEvent) {
        // Zoom with scroll wheel
        guard let camera = cameraNode else { return }

        // deltaY > 0 = scroll up = zoom out
        // deltaY < 0 = scroll down = zoom in
        let zoomDelta: CGFloat = event.deltaY > 0 ? 0.05 : -0.05
        let newScale = max(0.5, min(2.0, camera.xScale + zoomDelta))

        // Apply zoom smoothly
        let scaleAction = SKAction.scale(to: newScale, duration: 0.1)
        scaleAction.timingMode = .easeOut
        camera.run(scaleAction, withKey: "scrollZoom")

        // Notify via callback to update zoom UI. `mouseScrolled` runs on the main
        // thread and the scene is @MainActor, so call directly — no GCD hop needed.
        onZoomChanged?(newScale)
    }
    #else

    // MARK: - Touch Handling (iOS / iPadOS)

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        let touchedNodes = nodes(at: location)

        isUserInteracting = true
        pointerDownLocation = location
        didDragSincePointerDown = false

        // Highlight is applied on touchesEnded (after we know it was a tap, not a
        // drag) so that dragging a peer doesn't accidentally toggle its persistent
        // highlight state.
        if let peerNode = touchedNodes.first(where: { $0 is PeerNode }) as? PeerNode {
            selectedNode = peerNode
            isDraggingNode = true
        } else {
            isPanning = true
            lastPanLocation = location
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        if hypot(location.x - pointerDownLocation.x, location.y - pointerDownLocation.y)
            > tapMovementThreshold
        {
            didDragSincePointerDown = true
        }

        if isDraggingNode, let node = selectedNode {
            node.position = location
            updateConnectionsForNode(node)
        } else if isPanning {
            let previous = touch.previousLocation(in: self)
            let delta = CGPoint(x: location.x - previous.x, y: location.y - previous.y)
            cameraNode.position.x -= delta.x
            cameraNode.position.y -= delta.y
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if !didDragSincePointerDown {
            if let peer = selectedNode {
                toggleHighlight(for: peer)
            } else {
                clearHighlight()
            }
        }
        endInteraction()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        endInteraction()
    }
    #endif

    // MARK: - Shared Interaction End

    private func endInteraction() {
        // NOTE: the per-tap highlight handling moved out of here — it's now applied in
        // `mouseUp`/`touchesEnded` *before* this cleanup, via `toggleHighlight(for:)` or
        // `clearHighlight()`. This method only handles drag/pan/interaction-state reset.
        selectedNode = nil
        isDraggingNode = false
        isPanning = false
        isUserInteracting = false
        didDragSincePointerDown = false

        if needsLayoutAfterInteraction {
            needsLayoutAfterInteraction = false
            Log.debug("User interaction ended, running deferred layout animation")
            recalculateLayout()
        }
    }

    // MARK: - Tap-to-isolate Highlight

    /// Toggle the persistent highlight for [peer]. Tapping a different peer switches the
    /// highlight; tapping the same peer twice clears it. Tapping empty canvas in the
    /// gesture handler calls [clearHighlight] directly.
    private func toggleHighlight(for peer: PeerNode) {
        if highlightedNode === peer {
            clearHighlight()
        } else {
            // Switching from one peer to another: tear down the old focus first so the
            // new applyFocus call starts from a clean restored state.
            if highlightedNode != nil {
                clearHighlight()
            }
            highlightedNode = peer
            applyFocus()
        }
    }

    /// Remove the persistent highlight if any: drop the line+peer highlight on the
    /// previously selected peer and fade every node and edge back to alpha 1.0.
    private func clearHighlight() {
        guard let node = highlightedNode else { return }
        node.setHighlighted(false)
        highlightConnectionsForPeer(node.peerKey, highlighted: false)
        highlightedNode = nil
        restoreAllAlpha()
    }

    /// Apply the focus visualization for [highlightedNode]: scale up + glow on incident
    /// edges, dim non-incident edges to 0.2 alpha, dim non-neighbourhood peers to 0.35.
    /// Direct port of the Android tap-to-isolate UX.
    private func applyFocus() {
        guard let node = highlightedNode else { return }
        let peerKey = node.peerKey

        node.setHighlighted(true)
        highlightConnectionsForPeer(peerKey, highlighted: true)

        // Build the neighbourhood: the selected peer plus every peer at the other end
        // of an incident connection.
        var neighbourhood: Set<String> = [peerKey]
        for (_, line) in connectionLines {
            if line.fromPeerKey == peerKey {
                neighbourhood.insert(line.toPeerKey)
            } else if line.toPeerKey == peerKey {
                neighbourhood.insert(line.fromPeerKey)
            }
        }

        // Dim non-incident edges. Use a stable key so reapply-after-topology-change
        // overrides the previous focus action instead of stacking with it.
        for (_, line) in connectionLines {
            let isIncident = line.fromPeerKey == peerKey || line.toPeerKey == peerKey
            let target: CGFloat = isIncident ? 1.0 : focusDimEdgeAlpha
            line.run(
                SKAction.fadeAlpha(to: target, duration: focusFadeDuration),
                withKey: "focusFade"
            )
        }

        // Dim non-neighbourhood peers.
        for (key, peerNode) in peerNodes {
            let target: CGFloat = neighbourhood.contains(key) ? 1.0 : focusDimPeerAlpha
            peerNode.run(
                SKAction.fadeAlpha(to: target, duration: focusFadeDuration),
                withKey: "focusFade"
            )
        }
    }

    /// Restore every node and edge to full alpha. Called by [clearHighlight].
    private func restoreAllAlpha() {
        for (_, line) in connectionLines {
            line.run(
                SKAction.fadeAlpha(to: 1.0, duration: focusFadeDuration),
                withKey: "focusFade"
            )
        }
        for (_, peerNode) in peerNodes {
            peerNode.run(
                SKAction.fadeAlpha(to: 1.0, duration: focusFadeDuration),
                withKey: "focusFade"
            )
        }
    }

    /// Re-evaluate focus after a topology change: if the highlighted peer is still in
    /// the scene, reapply (so new peers/edges inherit the dim); otherwise clear it
    /// (the user's selected peer left the mesh).
    private func refreshFocusAfterTopologyChange() {
        guard let highlighted = highlightedNode else { return }
        if peerNodes.values.contains(where: { $0 === highlighted }) {
            applyFocus()
        } else {
            clearHighlight()
        }
    }

    // MARK: - Reset View

    /// Reset the camera to identity (origin + 100% zoom) and snap every peer back to its
    /// layout-computed position. Called from the reset button in the SwiftUI overlay
    /// when a user has panned/zoomed the graph off-screen or dragged peers around and
    /// needs to get back to a clean view. Mirrors the Android viewer's reset button.
    func resetCameraAndRelayout() {
        let resetCamera = SKAction.group([
            SKAction.move(to: centerPosition, duration: 0.3),
            SKAction.scale(to: 1.0, duration: 0.3)
        ])
        resetCamera.timingMode = .easeInEaseOut
        cameraNode.run(resetCamera, withKey: "resetCamera")
        // Tell observers (the SwiftUI overlay) the zoom level is now 100% so the "%"
        // indicator next to the +/- buttons stays in sync with the camera state.
        onZoomChanged?(1.0)
        // Re-snap peers to their layout-target positions in case the user had dragged
        // any of them around.
        recalculateLayout()
    }

    // MARK: - Zoom (called by UIViewRepresentable pinch gesture on iPad)

    /// Adjust zoom using a pinch gesture scale factor (incremental delta).
    /// - Parameter pinchScale: The current pinch gesture scale (>1 = zoom in, <1 = zoom out).
    func adjustZoom(by pinchScale: CGFloat) {
        guard let camera = cameraNode else { return }
        // Pinch scale > 1 = spread fingers = zoom in = camera scale decreases
        let newScale = max(0.5, min(2.0, camera.xScale / pinchScale))
        let scaleAction = SKAction.scale(to: newScale, duration: 0.1)
        scaleAction.timingMode = .easeOut
        camera.run(scaleAction, withKey: "pinchZoom")
        // Already on the main actor (the scene is @MainActor) — call directly.
        onZoomChanged?(newScale)
    }

    // MARK: - Helper Methods

    private func highlightConnectionsForPeer(_ peerKey: String, highlighted: Bool) {
        for (_, line) in connectionLines {
            if line.fromPeerKey == peerKey || line.toPeerKey == peerKey {
                line.setHighlighted(highlighted)
            }
        }
    }

    /// Get all peer keys currently in the scene
    func getPeerKeys() -> [String] {
        Array(peerNodes.keys)
    }

    /// Get the position of a peer node
    func getPeerPosition(key: String) -> CGPoint? {
        peerNodes[key]?.position
    }

    /// Enable mouse tracking for hover effects (macOS only)
    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)

        #if os(macOS)
        // Ensure view tracks mouse movement for hover effects. Remove the
        // previous tracking area(s) first — otherwise every resize stacks a new
        // one, each retaining the SKView, leaking memory and multiplying events.
        if let view {
            for area in view.trackingAreas {
                view.removeTrackingArea(area)
            }
            let trackingArea = NSTrackingArea(
                rect: view.bounds,
                options: [.activeInActiveApp, .mouseMoved, .mouseEnteredAndExited],
                owner: view,
                userInfo: nil
            )
            view.addTrackingArea(trackingArea)
        }
        #endif
    }
}

// MARK: - Layout Algorithm Extension

extension PresenceNetworkScene {
    /// Get the ring assignment for a peer (used for connection routing optimization)
    func getRingForPeer(_ peerKey: String) -> Int? {
        for (ring, peers) in currentRingAssignments where peers.contains(peerKey) {
            return ring
        }
        return nil
    }

    /// Get all peers in a specific ring
    func getPeersInRing(_ ring: Int) -> [String] {
        currentRingAssignments[ring] ?? []
    }
}
