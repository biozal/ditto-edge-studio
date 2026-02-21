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

    // Interaction state
    private var selectedNode: PeerNode?
    private var isDraggingNode = false
    private var isPanning = false
    private var lastPanLocation: CGPoint = .zero
    private var hoveredNode: PeerNode?
    private var isUserInteracting = false // Tracks if user is actively dragging/panning
    private var needsLayoutAfterInteraction = false // Defer layout until interaction completes

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

        if peersChanged || connectionsChanged {
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

        // Collect peer-to-peer connection IDs — deduplicate by type because the SDK returns
        // one DittoConnection per directional endpoint (A→B and B→A are separate objects).
        for remotePeer in remotePeers {
            var seenTypes: Set<String> = []
            for connection in remotePeer.connectionProtocols {
                guard seenTypes.insert("\(connection.type)").inserted else { continue }
                expectedConnectionIds.insert("\(remotePeer.peerKeyString)_\(connection.type)")
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

        // Collect all peer-to-peer connections — deduplicate by type because the SDK returns
        // one DittoConnection per directional endpoint (A→B and B→A are separate objects with
        // the same type but different IDs). Keep one line per transport type per peer pair.
        for remotePeer in remotePeers {
            var seenTypes: Set<String> = []
            for connection in remotePeer.connectionProtocols {
                guard seenTypes.insert("\(connection.type)").inserted else { continue }

                let connectionId = "\(remotePeer.peerKeyString)_\(connection.type)"
                let fromKey = remotePeer.peerKeyString
                let toKey = localPeer.peerKeyString

                // Create normalized pair key (always same order)
                let pairKey = [fromKey, toKey].sorted().joined(separator: "_")

                if peerPairConnections[pairKey] == nil {
                    peerPairConnections[pairKey] = []
                }

                peerPairConnections[pairKey]?.append(PeerConnectionInfo(
                    connectionId: connectionId,
                    from: fromKey,
                    to: toKey,
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

                let line = ConnectionLine(
                    from: conn.from,
                    to: conn.to,
                    type: conn.type,
                    fromPos: fromNode.position,
                    toPos: toNode.position,
                    offset: offset,
                    isCloudConnection: conn.isCloud
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

        // Calculate BFS-based ring layout
        let layoutResult = layoutEngine.calculateLayout(
            localPeerKey: localKey,
            allPeers: peerNodes,
            connections: connectionInfo
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

        // Final update after animation completes (cleanup)
        DispatchQueue.main.asyncAfter(deadline: .now() + animationDuration + 0.1) { [weak self] in
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

        // Check if we touched a peer node (cloud is treated as a regular peer)
        if let peerNode = touchedNodes.first(where: { $0 is PeerNode }) as? PeerNode {
            selectedNode = peerNode
            isDraggingNode = true
            peerNode.setHighlighted(true)

            // Highlight connected lines (including cloud connections)
            highlightConnectionsForPeer(peerNode.peerKey, highlighted: true)
        } else {
            // Start panning the camera
            isPanning = true
            lastPanLocation = location
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let location = event.location(in: self)

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
        endInteraction()
    }

    override func mouseMoved(with event: NSEvent) {
        let location = event.location(in: self)
        let touchedNodes = nodes(at: location)

        // Find peer node under cursor
        if let peerNode = touchedNodes.first(where: { $0 is PeerNode }) as? PeerNode {
            if hoveredNode !== peerNode {
                // New node hovered
                hoveredNode?.setHighlighted(false)
                hoveredNode = peerNode
                peerNode.setHighlighted(true)

                // Update cursor
                NSCursor.pointingHand.set()
            }
        } else {
            // No peer node under cursor
            if let hovered = hoveredNode {
                hovered.setHighlighted(false)
                hoveredNode = nil
                NSCursor.arrow.set()
            }
        }
    }

    override func mouseExited(with event: NSEvent) {
        // Clear hover state when mouse leaves scene
        if let hovered = hoveredNode {
            hovered.setHighlighted(false)
            hoveredNode = nil
        }
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

        // Notify via callback to update zoom UI
        DispatchQueue.main.async { [weak self] in
            self?.onZoomChanged?(newScale)
        }
    }
    #else

    // MARK: - Touch Handling (iOS / iPadOS)

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        let touchedNodes = nodes(at: location)

        isUserInteracting = true

        if let peerNode = touchedNodes.first(where: { $0 is PeerNode }) as? PeerNode {
            selectedNode = peerNode
            isDraggingNode = true
            peerNode.setHighlighted(true)
            highlightConnectionsForPeer(peerNode.peerKey, highlighted: true)
        } else {
            isPanning = true
            lastPanLocation = location
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)

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
        endInteraction()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        endInteraction()
    }
    #endif

    // MARK: - Shared Interaction End

    private func endInteraction() {
        if let node = selectedNode {
            node.setHighlighted(false)
            highlightConnectionsForPeer(node.peerKey, highlighted: false)
        }

        selectedNode = nil
        isDraggingNode = false
        isPanning = false
        isUserInteracting = false

        if needsLayoutAfterInteraction {
            needsLayoutAfterInteraction = false
            Log.debug("User interaction ended, running deferred layout animation")
            recalculateLayout()
        }
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
        DispatchQueue.main.async { [weak self] in
            self?.onZoomChanged?(newScale)
        }
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
        // Ensure view tracks mouse movement for hover effects
        if let view {
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
