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

    /// Whether the floating-squares background is visible and animating
    /// (the VS Code extension's background-effects toggle).
    var backgroundEffectsEnabled = true {
        didSet {
            backgroundLayer?.isEnabled = backgroundEffectsEnabled
        }
    }

    /// When true, only draw connection lines that involve the local peer directly
    var showDirectConnectedOnly = true {
        didSet {
            guard showDirectConnectedOnly != oldValue else { return }
            // A mode change can require layout even when the peer/connection key
            // sets are identical (radiusScale changes) — the extension's
            // `layoutDirty` flag (scene.ts). Consumed by the next
            // `updatePresenceGraph`, so the new mode's layout runs exactly once
            // even when the snapshots are unchanged.
            layoutDirty = true
            // Entering Direct (compact) mode with an inherited full-mesh zoom can
            // leave the small ring lost in empty space — fit it on the next layout.
            // The fit only ever zooms OUT, never over the user's chosen zoom-in
            // (VS Code extension scene.ts parity).
            if showDirectConnectedOnly {
                fitDirectLayoutOnNextRecalculate = true
            }
            // A mode toggle always discards focus, selection, and hover — the
            // visible graph (and so the selected peer's neighbourhood) is
            // changing (extension `setShowDirectConnectedOnly` parity:
            // clearFocusView + setHovered(undefined); both clear paths restore
            // dimmed alphas in this same pass). Skips the layout restore: the
            // mode toggle's own graph push runs the single layout for the new
            // mode (the extension's one-layout-per-toggle invariant).
            clearFocusMode(restoreLayout: false)
            clearHighlight()
            clearHover()
        }
    }

    /// Callbacks
    /// Called when user changes zoom level via scroll wheel or gestures
    var onZoomChanged: ((CGFloat) -> Void)?

    /// Called when a peer is tapped while the focused view is active. In focus mode a tap
    /// means "show me this peer" — the host presents a detail card. The meanings this
    /// displaced remain reachable: exit focus via the banner ✕ or an empty-canvas tap,
    /// and refocus via the card's own labelled action.
    var onPeerDetailRequested: ((String) -> Void)?

    /// Called when a tap should dismiss any open detail card (empty canvas, or leaving
    /// focus). Kept separate from `onPeerDetailRequested` so the host owns card state and
    /// the scene stays a pure reporter of gestures.
    var onDetailDismissRequested: (() -> Void)?

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

    /// Peer keys from the latest presence push (plus the cloud node when
    /// connected). `peerNodes` keeps removed nodes alive for their 0.3 s
    /// fade-out, so focus liveness must be answered from this model snapshot
    /// instead — otherwise focus re-enters on a dying node (the extension
    /// removes peers synchronously and clears focus in the same pass,
    /// scene.ts `applyInput`).
    private var currentModelPeerKeys: Set<String> = []

    /// Force-layout flag (the extension's `layoutDirty`): set by the
    /// Direct/Expanded mode toggle, which changes `radiusScale` without
    /// necessarily changing any peer or connection keys. Makes the next
    /// `updatePresenceGraph` run layout exactly once even when the snapshots
    /// are unchanged, consuming `fitDirectLayoutOnNextRecalculate` in that
    /// same pass so it can't linger. Internal getter for the scene tests
    /// (the mode-toggle-forces-exactly-one-layout-pass invariant).
    private(set) var layoutDirty = false

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

    /// Focus mode (Expanded/full-mesh view only) — the VS Code extension's
    /// focused-neighbourhood view. Tapping a remote peer with Direct OFF re-lays-out
    /// that peer at the centre with its direct neighbours on one orbit; the rest of
    /// the mesh stays in place as dimmed context (alphas in PresenceFocusPlanner).
    /// Exit via the banner button, re-tapping the focused peer, or tapping empty
    /// canvas. A mode toggle always discards focus.
    private(set) var focusedPeerKey: String?
    /// (focusedKey, focusedDisplayName) — a nil key means focus exited. Feeds the
    /// SwiftUI banner overlay.
    var onFocusChanged: ((String?, String?) -> Void)?
    private var focusNeighbourhood: Set<String> = []
    private var preFocusCameraScale: CGFloat?
    private var preFocusCameraPosition: CGPoint?
    private let focusTransitionDuration: TimeInterval = 0.3

    // Idle freeze (VS Code extension parity): the animated background pauses after
    // 3 s without user input or presence pushes, and resumes on the next either.
    private var lastActivityAt: TimeInterval = 0
    private let idleFreezeDelay: TimeInterval = 3.0

    // Layout
    private let centerPosition = CGPoint.zero
    private var layoutEngine = NetworkLayoutEngine()
    private var currentRingAssignments: [Int: [String]] = [:]
    /// Ring spread multiplier for full-mesh (Direct OFF) mode — the VS Code
    /// extension's EXPANDED_RADIUS_SCALE.
    private let expandedRadiusScale: CGFloat = 1.75
    /// Set when entering Direct mode; consumed by the next layout to fit the
    /// compact ring in the viewport (zoom-out only).
    private var fitDirectLayoutOnNextRecalculate = false

    // MARK: - Scene Lifecycle

    override func didMove(to view: SKView) {
        super.didMove(to: view)

        // Make scene background transparent (like JavaScript version)
        backgroundColor = .clear

        setupCamera()
        setupLayers()
        setupBackground()
        // `backgroundEffectsEnabled` is assigned before presentation (scene
        // creation), when the didSet still no-ops on the nil layer — apply the
        // stored value now that `setupBackground` has created the layer.
        backgroundLayer?.isEnabled = backgroundEffectsEnabled

        // Apply initial zoom level from configuration
        cameraNode.setScale(initialZoomLevel)

        // Idle-freeze watchdog (1 Hz check; cheap — no per-frame cost).
        lastActivityAt = CACurrentMediaTime()
        run(
            SKAction.repeatForever(SKAction.sequence([
                SKAction.wait(forDuration: 1.0),
                SKAction.run { [weak self] in self?.checkIdleFreeze() }
            ])),
            withKey: "idleFreezeWatchdog"
        )

        isReady = true
    }

    /// Any user input or presence push counts as activity and unfreezes the
    /// background layer (extension idle-freeze parity).
    private func noteActivity() {
        lastActivityAt = CACurrentMediaTime()
        if backgroundLayer?.isFrozen == true {
            backgroundLayer?.isFrozen = false
        }
    }

    private func checkIdleFreeze() {
        guard backgroundEffectsEnabled else { return }
        let shouldFreeze = CACurrentMediaTime() - lastActivityAt > idleFreezeDelay
        if shouldFreeze != (backgroundLayer?.isFrozen ?? false) {
            backgroundLayer?.isFrozen = shouldFreeze
        }
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
        noteActivity() // presence pushes count as activity for the idle freeze
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

        // Snapshot the model's current peer keys for focus liveness before any
        // add/remove animation starts (see the property's doc comment).
        var modelPeerKeys = newPeerKeys
        if hasCloudConnection {
            modelPeerKeys.insert(cloudNodeKey)
        }
        currentModelPeerKeys = modelPeerKeys

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

        if peersChanged || connectionsChanged || layoutDirty {
            layoutDirty = false
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

        // Collect peer-to-peer edges from the local peer AND all remote peers via the
        // shared aggregator (single source for change detection and the draw loop below).
        // The local peer's own connection list matters: Ditto usually reports an
        // undirected edge from both endpoints, but the local side is authoritative for
        // edges attached to this process — a transport (notably multicast) is lost when
        // only the local side advertises the edge.
        let localPeerKey = localPeer.peerKeyString
        let edges = PresenceEdgeAggregator.aggregate(
            localPeer: localPeer,
            remotePeers: remotePeers,
            showDirectConnectedOnly: showDirectConnectedOnly
        )
        expectedConnectionIds.formUnion(edges.map(\.connectionId))

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

        // Group the aggregated edges by peer pair (to detect bidirectional connections).
        // Drawing edges between the real participants of each connection means multihop
        // peers (e.g. iPhone→DT0-4196→Mac) appear linked to their actual neighbor, not
        // falsely drawn as if they connect directly to the local device.
        var peerPairConnections: [String: [PeerConnectionInfo]] = [:]
        for edge in edges {
            if peerPairConnections[edge.pairKey] == nil {
                peerPairConnections[edge.pairKey] = []
            }

            peerPairConnections[edge.pairKey]?.append(PeerConnectionInfo(
                connectionId: edge.connectionId,
                from: edge.from,
                to: edge.to,
                type: edge.type,
                isCloud: false
            ))
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

        // Calculate BFS-based ring layout. Expanded (full-mesh) mode spreads the
        // rings wider and packs crowded BFS layers across multiple visual rings;
        // measured pill widths keep long labels from overlapping.
        let layoutResult = layoutEngine.calculateLayout(
            localPeerKey: localKey,
            allPeers: Array(peerNodes.keys),
            connections: connectionInfo,
            radiusScale: showDirectConnectedOnly ? 1 : expandedRadiusScale,
            peerFootprints: peerNodes.mapValues { $0.getSpriteSize().width }
        )

        // Store ring assignments for connection routing optimization (Phase 3, Task 8)
        currentRingAssignments = layoutResult.ringAssignments

        // Entering Direct mode fits the (smaller) compact layout to the viewport.
        if fitDirectLayoutOnNextRecalculate {
            fitDirectLayoutOnNextRecalculate = false
            fitZoomToLayout(layoutResult)
        }

        // Animate all peers (including cloud) to their calculated positions WITH line updates
        let animationDuration: TimeInterval = 0.5

        for (peerKey, targetPosition) in layoutResult.positions {
            guard let peerNode = peerNodes[peerKey] else { continue }

            // Focus mode owns the neighbourhood's positions — the mesh layout pass
            // only moves the (dimmed) context nodes; `refreshFocusAfterTopologyChange`
            // re-lays out the orbit afterwards.
            if focusedPeerKey != nil, focusNeighbourhood.contains(peerKey) {
                continue
            }

            // Animate to new position. A stale focusMove (0.3 s) must not fight
            // this pass: under SpriteKit's keyed actions both would run, and the
            // LONGER one wins — kill the loser so the newest pass owns position.
            peerNode.removeAction(forKey: "focusMove")
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

    /// The scene-unit extent visible through a view of `viewSize` at camera
    /// scale 1.0. The scene is a fixed 1000×800 with `scaleMode = .aspectFill`,
    /// so SpriteKit scales it by s = max(viewW/1000, viewH/800) to fill the
    /// view — the visible scene-unit extent is `viewSize / s`, smaller than the
    /// raw view size whenever s > 1. Both fit-zoom computations must divide by
    /// s or they under-zoom and the layout overflows.
    private func visibleSceneSize(for viewSize: CGSize) -> CGSize {
        let s = max(viewSize.width / size.width, viewSize.height / size.height)
        guard s > 0, s.isFinite else { return viewSize }
        return CGSize(width: viewSize.width / s, height: viewSize.height / s)
    }

    /// Zooms the camera OUT (never in) until the layout fits the viewport.
    ///
    /// Mirrors the VS Code extension's `fitZoomToLayout` (scene.ts): entering
    /// Direct mode inherits whatever zoom the full-mesh view had, which can leave
    /// the compact ring tiny in a sea of empty canvas. The fit only applies when
    /// the layout overflows at the current scale, and never zooms in past the
    /// user's chosen level. Note SKCamera scale semantics: a LARGER scale shows
    /// MORE of the scene (zoomed out).
    private func fitZoomToLayout(_ layoutResult: NetworkLayoutEngine.LayoutResult) {
        guard let view else { return }

        // Per-node extents measured from the CAMERA position, not the origin —
        // a panned camera must still frame the whole layout (the extension fits
        // `|position + camera|` per node, scene.ts `fitZoomToLayout`).
        let cameraPosition = cameraNode.position
        var maxX: CGFloat = 0
        var maxY: CGFloat = 0
        for (peerKey, position) in layoutResult.positions {
            let nodeSize = peerNodes[peerKey]?.getSpriteSize() ?? CGSize(width: 60, height: 22.5)
            maxX = max(maxX, abs(position.x - cameraPosition.x) + nodeSize.width / 2)
            maxY = max(maxY, abs(position.y - cameraPosition.y) + nodeSize.height / 2)
        }
        guard maxX > 0, maxY > 0 else { return }

        // Margin: 20pt breathing room per edge, so the outermost labels aren't
        // clipped by the viewport edge.
        let viewSize = visibleSceneSize(for: view.bounds.size)
        guard viewSize.width > 0, viewSize.height > 0 else { return }
        let availableWidth = max(1, viewSize.width / 2 - 20)
        let availableHeight = max(1, viewSize.height / 2 - 20)

        let fitScale = max(maxX / availableWidth, maxY / availableHeight)
        let current = cameraNode.xScale
        // Zoom-out only, capped at the app's zoom-out limit (the same 4.0 cap the
        // toolbar buttons enforce).
        let target = min(fitScale, 4.0)
        guard target > current else { return }

        let zoomAction = SKAction.scale(to: target, duration: 0.3)
        zoomAction.timingMode = .easeInEaseOut
        cameraNode.run(zoomAction)
        onZoomChanged?(target)
    }

    // MARK: - Animations

    private func animatePeerAppearance(node: PeerNode) {
        // Initial state: invisible, small, at center
        node.alpha = 0.0
        node.setScale(0.5)
        node.position = centerPosition

        // Target state: the CURRENT resting alpha (not blindly 1.0 — a peer
        // joining while focus/selection is active must arrive dimmed, because
        // this 0.4 s fade would otherwise outlive the 0.2–0.3 s dim fades and
        // win), normal size, at final position.
        let fadeIn = SKAction.fadeAlpha(to: restingAlpha(forPeerKey: node.peerKey), duration: 0.4)
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
        // Start with alpha 0, fade in — to the CURRENT resting alpha, never
        // blindly to 1.0: a connection rebuild during focus/selection recreates
        // every line, and this 0.4 s fade-in would otherwise outlive the
        // 0.2–0.3 s dim fades and leave context lines fully opaque.
        line.alpha = 0.0

        let fadeIn = SKAction.fadeAlpha(to: restingAlpha(for: line), duration: 0.4)
        fadeIn.timingMode = .easeInEaseOut

        line.run(fadeIn, withKey: "lineDrawAnimation")
    }

    /// The resting alpha for a line under the current focus/selection state.
    /// The dim state is authoritative: freshly created lines fade in to THIS
    /// value, never blindly to 1.0 (see `animateLineDrawing`).
    private func restingAlpha(for line: ConnectionLine) -> CGFloat {
        if let focusedKey = focusedPeerKey {
            let touchesFocus = line.fromPeerKey == focusedKey || line.toPeerKey == focusedKey
            return touchesFocus ? 1.0 : PresenceFocusPlanner.contextLineAlpha
        }
        if let highlighted = highlightedNode {
            let isIncident = line.fromPeerKey == highlighted.peerKey
                || line.toPeerKey == highlighted.peerKey
            return isIncident ? 1.0 : focusDimEdgeAlpha
        }
        return 1.0
    }

    /// The resting alpha for a peer pill — same authority as
    /// `restingAlpha(for:)`, applied by the peer-appear fade.
    private func restingAlpha(forPeerKey peerKey: String) -> CGFloat {
        if focusedPeerKey != nil {
            return focusNeighbourhood.contains(peerKey) ? 1.0 : PresenceFocusPlanner.contextPeerAlpha
        }
        if let highlighted = highlightedNode {
            return highlightNeighbourhood(of: highlighted.peerKey).contains(peerKey)
                ? 1.0
                : focusDimPeerAlpha
        }
        return 1.0
    }

    /// The selected peer plus every peer at the other end of an incident line —
    /// the tap-to-isolate neighbourhood.
    private func highlightNeighbourhood(of peerKey: String) -> Set<String> {
        var neighbourhood: Set<String> = [peerKey]
        for (_, line) in connectionLines {
            if line.fromPeerKey == peerKey {
                neighbourhood.insert(line.toPeerKey)
            } else if line.toPeerKey == peerKey {
                neighbourhood.insert(line.fromPeerKey)
            }
        }
        return neighbourhood
    }

    // MARK: - Mouse/Touch Handling

    #if os(macOS)
    override func mouseDown(with event: NSEvent) {
        noteActivity()
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
        // Tap (no drag) → route to focus mode (Expanded) or tap-to-isolate (Direct),
        // or clear focus/highlight if the tap landed on empty canvas.
        if !didDragSincePointerDown {
            if let peer = selectedNode {
                handlePeerTap(peer)
            } else {
                handleCanvasTap()
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
        noteActivity()
        guard let camera = cameraNode else { return }

        // deltaY > 0 = scroll up = zoom out
        // deltaY < 0 = scroll down = zoom in
        // Range: camera scale 0.5–4.0 (= the VS Code extension's 2.0–0.25
        // magnification range; large meshes need the deep zoom-out).
        let zoomDelta: CGFloat = event.deltaY > 0 ? 0.05 : -0.05
        let newScale = max(0.5, min(4.0, camera.xScale + zoomDelta))

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
        noteActivity()
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
                handlePeerTap(peer)
            } else {
                handleCanvasTap()
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
            // Same ghost-tap guard as `handlePeerTap`: never select a peer the
            // model has already dropped (its node is mid fade-out).
            guard currentModelPeerKeys.contains(peer.peerKey) else { return }
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

    /// Clear transient hover emphasis (the extension's `setHovered(undefined)`):
    /// restores the previously-hovered peer unless it's the persistent selection.
    private func clearHover() {
        if let hovered = hoveredNode, hovered !== highlightedNode {
            hovered.setHighlighted(false)
        }
        hoveredNode = nil
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
        let neighbourhood = highlightNeighbourhood(of: peerKey)

        // Dim non-incident edges. Use a stable key so reapply-after-topology-change
        // overrides the previous focus action instead of stacking with it. Kill any
        // still-running creation fade first — the 0.4 s lineDrawAnimation would
        // outlive this 0.2 s dim and win (the dim state is authoritative).
        for (_, line) in connectionLines {
            let isIncident = line.fromPeerKey == peerKey || line.toPeerKey == peerKey
            let target: CGFloat = isIncident ? 1.0 : focusDimEdgeAlpha
            line.removeAction(forKey: "lineDrawAnimation")
            line.run(
                SKAction.fadeAlpha(to: target, duration: focusFadeDuration),
                withKey: "focusFade"
            )
        }

        // Dim non-neighbourhood peers (same creation-fade race closed here).
        for (key, peerNode) in peerNodes {
            let target: CGFloat = neighbourhood.contains(key) ? 1.0 : focusDimPeerAlpha
            peerNode.removeAction(forKey: "appearAnimation")
            peerNode.run(
                SKAction.fadeAlpha(to: target, duration: focusFadeDuration),
                withKey: "focusFade"
            )
        }
    }

    /// Restore every node and edge to full alpha. Called by [clearHighlight].
    private func restoreAllAlpha() {
        // Kill any still-running creation fades first: they would outlive this
        // 0.2 s restore and re-dim (or re-hide) a node the user just released.
        for (_, line) in connectionLines {
            line.removeAction(forKey: "lineDrawAnimation")
            line.run(
                SKAction.fadeAlpha(to: 1.0, duration: focusFadeDuration),
                withKey: "focusFade"
            )
        }
        for (_, peerNode) in peerNodes {
            peerNode.removeAction(forKey: "appearAnimation")
            peerNode.run(
                SKAction.fadeAlpha(to: 1.0, duration: focusFadeDuration),
                withKey: "focusFade"
            )
        }
    }

    /// Re-evaluate focus after a topology change: if the highlighted peer is still in
    /// the scene, reapply (so new peers/edges inherit the dim); otherwise clear it
    /// (the user's selected peer left the mesh).
    ///
    /// Liveness is checked against `currentModelPeerKeys` (the latest presence
    /// push), not `peerNodes`: removed nodes stay in `peerNodes` for their 0.3 s
    /// fade-out, which would re-enter focus on a dying node and leave focus
    /// dangling until the next push (extension scene.ts `applyInput` parity —
    /// peers are removed synchronously and focus clears in the same pass).
    private func refreshFocusAfterTopologyChange() {
        // Focus mode first: the focused peer leaving the mesh exits focus; a changed
        // neighbourhood re-lays out the orbit. (The main layout pass already restored
        // context positions, so the exit path skips its own restore.)
        if let focusedKey = focusedPeerKey {
            if currentModelPeerKeys.contains(focusedKey) {
                enterFocusMode(for: focusedKey)
            } else {
                clearFocusMode(restoreLayout: false)
            }
        }
        guard let highlighted = highlightedNode else { return }
        if currentModelPeerKeys.contains(highlighted.peerKey) {
            applyFocus()
        } else {
            clearHighlight()
        }
    }

    // MARK: - Focus Mode (Expanded/full-mesh only)

    /// Route a tap on a peer: Direct mode keeps the tap-to-isolate dimming;
    /// Expanded mode enters/toggles the focused-neighbourhood view. The local peer
    /// is never focusable — in Direct mode every line touches it, so focusing it
    /// would exempt the whole graph from dimming (extension `selectPeer` parity).
    ///
    /// Internal (not private) so the scene unit tests can drive the tap-routing
    /// table directly.
    func handlePeerTap(_ peer: PeerNode) {
        let key = peer.peerKey
        // Ignore taps on nodes the model has already dropped: removed peers stay
        // in `peerNodes` for their 0.3 s fade-out (sliding toward centre), and
        // focusing/selecting one would be a ghost — focus liveness is answered
        // from the model snapshot (`currentModelPeerKeys`), never the node tree.
        guard currentModelPeerKeys.contains(key) else { return }
        if showDirectConnectedOnly {
            guard key != localPeerKey else {
                handleCanvasTap()
                return
            }
            toggleHighlight(for: peer)
            return
        }
        if focusedPeerKey != nil {
            // In focus mode a tap ALWAYS means "show me this peer" — it opens (or closes)
            // that peer's detail card, for every peer including the focused one and the
            // local device. Tap previously meant three different things here (re-tap
            // exits, orbit peer refocuses, dimmed peer exits), which is unlearnable, and
            // the card is what people come to focus mode for. All three displaced
            // meanings are still reachable: the banner ✕ and an empty-canvas tap exit
            // focus, and the card carries a labelled "Focus this peer" action.
            onPeerDetailRequested?(key)
            return
        }
        guard key != localPeerKey else {
            handleCanvasTap()
            return
        }
        enterFocusMode(for: key)
    }

    /// Tapping empty canvas exits focus (or clears the Direct-mode selection).
    private func handleCanvasTap() {
        // An open card is dismissed first, and focus is kept: the user is closing an
        // inspector, not backing out of the peer they are investigating.
        if let onDetailDismissRequested, hasOpenDetailCard {
            onDetailDismissRequested()
            return
        }
        if focusedPeerKey != nil {
            clearFocusMode()
        } else {
            clearHighlight()
        }
    }

    /// Set by the host while a detail card is on screen, so an empty-canvas tap can
    /// dismiss the card rather than exiting focus.
    var hasOpenDetailCard = false

    /// Enter (or refresh) the focused-neighbourhood view for `key`.
    ///
    /// The focus layout reuses the shared engine with the focused peer as centre —
    /// its crowding floor plus the measured pill footprints make the orbit
    /// label-aware (superseding the extension's `expandFocusedRingForLabels`).
    private func enterFocusMode(for key: String) {
        guard !showDirectConnectedOnly,
              let focusedNode = peerNodes[key],
              key != localPeerKey,
              // Liveness comes from the model snapshot, not `peerNodes`: a
              // departed peer's node lingers for its fade-out and must not be
              // (re-)focusable — that would be a ghost focus.
              currentModelPeerKeys.contains(key) else { return }

        // Focus replaces any selection highlight; refocusing starts from full alpha.
        if highlightedNode != nil {
            clearHighlight()
        }
        restoreAllAlpha()

        let currentEdges = connectionLines.map { connectionId, line in
            PresenceEdge(
                connectionId: connectionId,
                pairKey: "",
                from: line.fromPeerKey,
                to: line.toPeerKey,
                type: line.connectionType
            )
        }
        let neighbours = PresenceFocusPlanner.neighbourKeys(of: key, edges: currentEdges)
        let focusKeys = [key] + neighbours
        let focusEdges = currentEdges
            .filter { $0.from == key || $0.to == key }
            .map { NetworkLayoutEngine.ConnectionInfo(fromPeer: $0.from, toPeer: $0.to) }
        let footprints = peerNodes.mapValues { $0.getSpriteSize().width }

        let focusLayout = layoutEngine.calculateLayout(
            localPeerKey: key,
            allPeers: focusKeys,
            connections: focusEdges,
            radiusScale: 1,
            peerFootprints: footprints
        )

        focusedPeerKey = key
        focusNeighbourhood = Set(focusKeys)

        // Move only the neighbourhood; the rest of the mesh stays put as context.
        for (peerKey, target) in focusLayout.positions {
            guard let node = peerNodes[peerKey] else { continue }
            // A stale layoutMove (0.5 s) would outlive this 0.3 s focus move and
            // win — a topology-push neighbour added by the mesh pass would end up
            // off-orbit. Kill the loser so the focus pass owns the position.
            node.removeAction(forKey: "layoutMove")
            let move = SKAction.move(to: target, duration: focusTransitionDuration)
            move.timingMode = .easeInEaseOut
            node.run(move, withKey: "focusMove")
        }
        // Keep the incident edges attached to the moving orbit.
        run(SKAction.customAction(withDuration: focusTransitionDuration) { [weak self] _, _ in
            self?.updateAllConnectionPaths()
        }, withKey: "focusLineUpdate")

        // Dim the context mesh. Kill any still-running creation fades first —
        // a line/peer created by the same push's rebuild would otherwise keep
        // fading in past these 0.3 s dim fades and end fully opaque.
        for (peerKey, node) in peerNodes {
            let target: CGFloat = focusNeighbourhood.contains(peerKey)
                ? 1.0
                : PresenceFocusPlanner.contextPeerAlpha
            node.removeAction(forKey: "appearAnimation")
            node.run(
                SKAction.fadeAlpha(to: target, duration: focusTransitionDuration),
                withKey: "focusFade"
            )
        }
        for (_, line) in connectionLines {
            let touchesFocus = line.fromPeerKey == key || line.toPeerKey == key
            let target: CGFloat = touchesFocus ? 1.0 : PresenceFocusPlanner.contextLineAlpha
            line.removeAction(forKey: "lineDrawAnimation")
            line.run(
                SKAction.fadeAlpha(to: target, duration: focusTransitionDuration),
                withKey: "focusFade"
            )
        }

        // Focus zoom: magnify to a useful close-up (1.25× default → camera scale
        // 0.8), never exceeding the fit for the complete neighbourhood. Stored for
        // restore on exit — but only on first entry, not on a refresh re-entry.
        if preFocusCameraScale == nil {
            preFocusCameraScale = cameraNode.xScale
            preFocusCameraPosition = cameraNode.position
        }
        let fitScale = PresenceFocusPlanner.fitScale(
            layoutRadius: focusLayout.ringRadii.values.max() ?? 0,
            maxPillWidth: peerNodes.values.map { $0.getSpriteSize().width }.max() ?? 60,
            viewSize: visibleSceneSize(for: view?.bounds.size ?? .zero),
            padding: 88
        )
        let targetScale = PresenceFocusPlanner.focusCameraScale(
            fitScale: fitScale,
            currentScale: cameraNode.xScale
        )
        let zoomGroup = SKAction.group([
            SKAction.scale(to: targetScale, duration: focusTransitionDuration),
            // The focused peer sits at the layout origin — centre the camera there.
            SKAction.move(to: centerPosition, duration: focusTransitionDuration)
        ])
        zoomGroup.timingMode = .easeInEaseOut
        cameraNode.run(zoomGroup, withKey: "focusZoom")
        onZoomChanged?(targetScale)
        onFocusChanged?(key, focusedNode.deviceName)
    }

    /// Exit the focused-neighbourhood view and (by default) restore the full-mesh
    /// layout plus the pre-focus camera. Pass `restoreLayout: false` when the caller
    /// is about to push a fresh graph state that re-lays out anyway (mode toggle,
    /// topology change), so the layout runs exactly once.
    private func clearFocusMode(restoreLayout: Bool = true) {
        // Always notify, even with nothing to clear: the hoisted banner name
        // (`focusedPeerName`) survives scene teardown on a tab switch, and the
        // banner's ✕ must still clear it when the fresh scene has no focus to
        // exit. Only the scene-side restore is guarded.
        guard focusedPeerKey != nil else {
            onFocusChanged?(nil, nil)
            return
        }
        focusedPeerKey = nil
        focusNeighbourhood = []
        restoreAllAlpha()

        let targetScale = preFocusCameraScale ?? 1.0
        let targetPosition = preFocusCameraPosition ?? centerPosition
        preFocusCameraScale = nil
        preFocusCameraPosition = nil
        cameraNode.removeAction(forKey: "focusZoom")
        let restore = SKAction.group([
            SKAction.scale(to: targetScale, duration: focusTransitionDuration),
            SKAction.move(to: targetPosition, duration: focusTransitionDuration)
        ])
        restore.timingMode = .easeInEaseOut
        cameraNode.run(restore, withKey: "focusZoom")
        onZoomChanged?(targetScale)
        onFocusChanged?(nil, nil)

        if restoreLayout {
            recalculateLayout()
        }
    }

    /// Public exit for the banner's ✕ button.
    func exitFocusMode() {
        clearFocusMode()
    }

    /// Re-enter focus after the scene was recreated — the Peers ↔ Viewer tab
    /// switch tears the scene down while the hoisted focus key survives on the
    /// view model (Android `presenceFocusedPeerId` parity).
    ///
    /// Call after a graph push. Re-enters when the peer is still in the current
    /// model and the mode is Expanded; otherwise clears the hoisted banner
    /// state via `onFocusChanged`. No-ops while the scene is not ready (the
    /// next push retries) or while a focus is already active. `preFocusCamera*`
    /// intentionally stays scene-local: the restore zooms from the current
    /// camera state.
    func restoreFocusAfterRebuild(for key: String) {
        guard isReady, focusedPeerKey == nil else { return }
        guard !showDirectConnectedOnly, currentModelPeerKeys.contains(key) else {
            // Peer left the mesh (or Direct mode, where focus doesn't exist):
            // drop the hoist.
            onFocusChanged?(nil, nil)
            return
        }
        enterFocusMode(for: key)
    }

    // MARK: - Reset View

    /// Reset the camera to identity (origin + 100% zoom) and snap every peer back to its
    /// layout-computed position. Called from the reset button in the SwiftUI overlay
    /// when a user has panned/zoomed the graph off-screen or dragged peers around and
    /// needs to get back to a clean view. Mirrors the Android viewer's reset button.
    func resetCameraAndRelayout() {
        // Within focus mode the reset only restores 100% magnification (the
        // neighbourhood stays centred) — mirroring the extension's
        // `resetViewToLocal`, which resets `focusViewZoom` and nothing else.
        guard focusedPeerKey == nil else {
            let zoom = SKAction.scale(to: 1.0, duration: 0.3)
            zoom.timingMode = .easeInEaseOut
            cameraNode.run(zoom, withKey: "focusZoom")
            cameraNode.run(SKAction.move(to: centerPosition, duration: 0.3), withKey: "focusPan")
            onZoomChanged?(1.0)
            return
        }
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
        noteActivity()
        guard let camera = cameraNode else { return }
        // Pinch scale > 1 = spread fingers = zoom in = camera scale decreases
        // (range 0.5–4.0 — see scrollWheel for the mapping note).
        let newScale = max(0.5, min(4.0, camera.xScale / pinchScale))
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
