@preconcurrency import DittoSwift
import Foundation
import SpriteKit
import SwiftUI

/// SwiftUI wrapper for the Presence Network Viewer
/// Displays a dynamic network diagram of Ditto peers with connection visualization
/// Accesses DittoManager.shared singleton directly (no Ditto parameter needed)
struct PresenceViewerSK: View {
    @State private var viewModel: ViewModel
    @State private var scene: PresenceNetworkScene?

    /// `nil` → this view owns its own ViewModel (back-compat with the standalone preview).
    /// Non-`nil` → the parent provides one (so it can also drive the floating-toolbar
    /// middle-content for Direct toggle, zoom, and reset).
    init(viewModel: ViewModel? = nil) {
        _viewModel = State(initialValue: viewModel ?? ViewModel())
    }

    var body: some View {
        // Main scene view with overlays
        ZStack(alignment: .bottomLeading) {
            // SpriteKit scene
            SpriteKitSceneView(scene: $scene, viewModel: viewModel)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .focusable() // Allow view to receive keyboard and scroll events

            // Only the connection-types legend stays inside this view as a corner
            // overlay. The Direct toggle, reset button, and zoom controls used to
            // live here too but were hoisted to the parent's DetailBottomBar so they
            // sit on the floating toolbar — see `presenceViewerToolbarControls(vm:)`
            // in MainStudioView.
            //
            // Bottom padding clears the DetailBottomBar floating-toolbar overlay
            // below this view. The bar's own footprint is ~56pt (HStack contents +
            // 12pt vertical padding × 2 + glass-effect spread) plus the 12pt
            // .padding(.bottom, 12) the overlay anchor applies. 100pt leaves a
            // comfortable ~24pt visual gap between the legend's bottom edge and
            // the toolbar's top edge.
            if viewModel.controlsVisible {
                connectionLegend
                    .padding(.leading, 16)
                    .padding(.bottom, 100)
                    .transition(.opacity)
            }

            // Focus banner (top-center) — mirrors the VS Code extension's
            // "Focused on <label>" pill with an exit button. Focus mode is only
            // reachable in the full-mesh (Direct OFF) view.
            if let focusedName = viewModel.focusedPeerName {
                VStack {
                    HStack(spacing: 8) {
                        Text("Focused on **\(focusedName)**")
                            .font(.caption)
                            .foregroundStyle(.primary)
                        Button {
                            viewModel.exitFocusMode()
                        } label: {
                            FontAwesomeText(icon: ActionIcon.circleXmark, size: 13, color: .secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Exit focus")
                        .accessibilityIdentifier("FocusModeExitButton")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 12)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Detail card — centred in the viewport, above the SpriteKit scene rather
            // than inside it, so it is never scaled by the camera and never reaches the
            // layout engine's peerFootprints. Anchoring it to its peer would put it
            // wherever that peer happened to be, including hard against an edge where
            // the bottom rows — the sync rows the card exists for — are clipped.
            if let detail = viewModel.openPeerDetail {
                PeerDetailCardView(
                    detail: detail,
                    onFocusPeer: viewModel.canFocusOpenPeer ? { viewModel.focusOpenPeer() } : nil
                )
                // Tap-to-close is attached BEFORE the centring frame, so the gesture
                // covers the card's own bounds only. Attaching it after would make the
                // full-size frame swallow taps beside the card, which must still reach
                // the scene as canvas taps (dismiss, or exit focus when no card is open).
                .onTapGesture { viewModel.dismissDetail() }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.focusedPeerName)
        .animation(.easeInOut(duration: 0.15), value: viewModel.detailPeerKey)
        #if os(macOS)
            // Escape with focus on the canvas (a mouse pick moves focus onto a
            // results row, and an open detail card never had an Escape route at all).
            // The search box carries its own `.onKeyPress(.escape)` for the
            // still-typing case; both land on the same unwind order.
            .onExitCommand { viewModel.handleEscape() }
        #endif
            .onAppear {
                createScene()
            }
            .task {
                // Start presence observation tied to the view's lifetime via
                // structured concurrency, rather than an untracked Task in the
                // ViewModel's init that can race view teardown on rapid tab switches.
                await viewModel.startProductionMode()
            }
            .onDisappear {
                // Stop the presence observer here rather than relying on
                // ViewModel ARC dealloc. The VM holds a DittoObserver that
                // (via ditto.presence) retains the Ditto instance — leaving
                // it alive after database close blocks the SDK's own deinit
                // shutdown and prevents SQLite WAL from being flushed.
                viewModel.stopProductionMode()
                cleanupScene()
            }
    }

    // MARK: - Connection Legend

    /// Connection types legend showing dash patterns and colors
    private var connectionLegend: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Connection Types")
                .font(.caption)
                .fontWeight(.semibold)

            LegendRow(color: ConnectionType.bluetooth.cardColor, pattern: "● ● ●", label: "Bluetooth")
            LegendRow(color: ConnectionType.accessPoint.cardColor, pattern: "████ ████", label: "LAN")
            LegendRow(color: ConnectionType.p2pWiFi.cardColor, pattern: "██ ██ ██", label: "P2P WiFi")
            LegendRow(color: ConnectionType.webSocket.cardColor, pattern: "███·███·", label: "WebSocket")
            LegendRow(color: ConnectionType.multicast.cardColor, pattern: "· · · · · ·", label: "Multicast")
            LegendRow(color: SyncStatusInfo.cloudCardColor, pattern: "████ ○ ████", label: "Cloud")
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .cornerRadius(8)
    }

    // MARK: - Scene Management

    /// Creates and configures the SpriteKit scene
    private func createScene() {
        let newScene = PresenceNetworkScene()

        // Configure scene size (larger for better quality)
        newScene.size = CGSize(width: 1000, height: 800)
        newScene.scaleMode = .aspectFill

        // Configure initial zoom level
        newScene.initialZoomLevel = viewModel.zoomLevel

        // Apply persisted VM-level display preferences to the fresh scene
        newScene.backgroundEffectsEnabled = viewModel.backgroundEffectsEnabled

        // Set up zoom change callback
        newScene.onZoomChanged = { [weak viewModel] newZoom in
            viewModel?.updateZoomLevel(newZoom)
        }

        // Focus-mode banner state (fires on the main actor from the scene's
        // @MainActor tap/refresh paths). Both hoisted fields update together so
        // the banner and the post-rebuild focus restore never disagree.
        newScene.onFocusChanged = { [weak viewModel] key, name in
            viewModel?.focusedPeerKey = key
            viewModel?.focusedPeerName = name
            // Focus ending takes any open card with it — the card belongs to a focus
            // session, and a card anchored to one that has ended is stale.
            if key == nil {
                viewModel?.dismissDetail()
            }
        }

        // In focus mode a tap means "show me this peer".
        newScene.onPeerDetailRequested = { [weak viewModel] key in
            viewModel?.toggleDetail(for: key)
        }

        // Empty-canvas tap while a card is open dismisses the card and keeps focus.
        newScene.onDetailDismissRequested = { [weak viewModel] in
            viewModel?.dismissDetail()
        }

        // A rebuilt scene starts with no card; keep its flag in step with the VM.
        newScene.hasOpenDetailCard = viewModel.detailPeerKey != nil

        scene = newScene
        viewModel.scene = newScene

        // A rebuilt scene starts with no search dim, while the view model keeps the
        // query across the Peers ↔ Viewer switch. Re-apply it now rather than
        // waiting on the next presence push — that is up to 250 ms of undimmed
        // graph on every tab hop.
        viewModel.reapplySearchMatchesToScene()

        // Note: Camera zoom will be applied after scene is presented (in didMove(to:))
    }

    /// Cleanup SpriteKit resources when view disappears
    private func cleanupScene() {
        scene?.removeAllChildren()
        scene?.removeAllActions()
        scene?.removeFromParent()
        scene = nil
    }
}

// MARK: - Legend Row Component

/// Single row in the connection legend showing color, pattern, and label
struct LegendRow: View {
    let color: Color
    let pattern: String
    let label: String

    var body: some View {
        HStack(spacing: 8) {
            // Color indicator circle
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)

            // Dash pattern visualization
            Text(pattern)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(color)

            // Connection type label
            Text(label)
                .font(.caption)
        }
    }
}

// MARK: - SpriteKit Scene View (Platform-Specific)

#if os(macOS)
/// Custom SKView subclass that properly forwards scroll events to the scene
class ScrollableSKView: SKView {
    override var acceptsFirstResponder: Bool {
        true
    }

    override func scrollWheel(with event: NSEvent) {
        // Forward scroll events to the scene
        scene?.scrollWheel(with: event)
    }
}

/// NSViewRepresentable wrapper for SKView with scroll event handling
struct SpriteKitSceneView: NSViewRepresentable {
    @Binding var scene: PresenceNetworkScene?
    let viewModel: PresenceViewerSK.ViewModel

    func makeNSView(context: Context) -> ScrollableSKView {
        let skView = ScrollableSKView()
        skView.ignoresSiblingOrder = true
        skView.showsFPS = false // Set to true for debugging
        skView.showsNodeCount = false // Set to true for debugging
        skView.allowsTransparency = true // Allow transparent background

        if let scene {
            skView.presentScene(scene)
        }

        // Ensure view can become first responder and receive scroll events
        DispatchQueue.main.async {
            skView.window?.makeFirstResponder(skView)
        }

        return skView
    }

    func updateNSView(_ nsView: ScrollableSKView, context: Context) {
        if let scene, nsView.scene !== scene {
            nsView.presentScene(scene)
        }
    }
}

#else
// iOS / iPadOS

/// UIViewRepresentable wrapper for SKView with pinch-to-zoom support
struct SpriteKitSceneView: UIViewRepresentable {
    @Binding var scene: PresenceNetworkScene?
    let viewModel: PresenceViewerSK.ViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    func makeUIView(context: Context) -> SKView {
        let skView = SKView()
        skView.ignoresSiblingOrder = true
        skView.showsFPS = false
        skView.showsNodeCount = false
        skView.allowsTransparency = true

        if let scene {
            skView.presentScene(scene)
        }

        // Add pinch gesture for zoom
        let pinch = UIPinchGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePinch(_:))
        )
        skView.addGestureRecognizer(pinch)

        return skView
    }

    func updateUIView(_ uiView: SKView, context: Context) {
        if let scene, uiView.scene !== scene {
            uiView.presentScene(scene)
        }
        context.coordinator.scene = scene
    }

    // @MainActor: UIKit delivers gesture actions on the main thread, and the
    // handler touches main-actor-isolated UIKit/SpriteKit APIs.
    @MainActor
    class Coordinator: NSObject {
        let viewModel: PresenceViewerSK.ViewModel
        weak var scene: PresenceNetworkScene?

        init(viewModel: PresenceViewerSK.ViewModel) {
            self.viewModel = viewModel
        }

        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            guard gesture.state == .changed else { return }
            scene?.adjustZoom(by: gesture.scale)
            gesture.scale = 1.0 // Reset to get incremental deltas
        }
    }
}
#endif

// MARK: - ViewModel

extension PresenceViewerSK {
    /// ViewModel for PresenceViewerSK
    /// Manages presence graph observation and scene state
    /// Accesses DittoManager.shared singleton directly (no Ditto parameter needed)
    @MainActor
    @Observable
    class ViewModel {
        // MARK: - Published State

        /// When true, only peers directly connected to this device are shown
        var showDirectConnectedOnly = true {
            didSet {
                updateSceneWithCurrentFilter()
            }
        }

        /// Current zoom level (0.5 = 50%, 1.0 = 100%, 2.0 = 200%)
        var zoomLevel: CGFloat = 1.0

        /// Display name of the focused peer (focus mode, full-mesh view only).
        /// Drives the top banner; nil when no peer is focused.
        var focusedPeerName: String?

        /// Key of the focused peer, hoisted so an active focus session survives
        /// the Peers ↔ Viewer tab switch (the scene is recreated on return; this
        /// VM is not — MainStudioView holds it as @State). Mirrors Android's
        /// `MainStudioViewModel.presenceFocusedPeerId`. Always updated together
        /// with `focusedPeerName` via the scene's `onFocusChanged`.
        var focusedPeerKey: String?

        /// The peer whose detail card is open, or nil. Accordion semantics: opening one
        /// closes the other, because two centred overlays would occlude each other.
        /// Hoisted like `focusedPeerKey` so a card survives a scene rebuild.
        var detailPeerKey: String?

        /// Sync rows for the open card, keyed by peer key. Refreshed alongside each
        /// presence push. Only directly connected peers ever appear:
        /// `system:data_sync_info` is a local table computed from where this device
        /// actually receives data, so it has no row for an indirect peer or for
        /// ourselves — which is exactly what the card's three-way sync section reports.
        private(set) var syncStatusByPeerKey: [String: SyncStatusInfo] = [:]

        /// Detail for the open card, or nil when no card is open (or its peer has left
        /// the mesh — a card anchored to a peer that is gone must not survive).
        var openPeerDetail: PresencePeerDetail? {
            guard let key = detailPeerKey, let localPeer = rawLocalPeer else { return nil }
            let isLocal = key == localPeer.peerKeyString
            guard let peer = isLocal ? localPeer : rawRemotePeers.first(where: { $0.peerKeyString == key }) else {
                return nil
            }
            let directKeys = PresenceEdgeAggregator.directVisiblePeerKeys(
                localPeer: localPeer,
                remotePeers: rawRemotePeers
            )
            return PresencePeerDetail(
                peer: peer,
                isLocal: isLocal,
                isDirectlyConnected: directKeys.contains(key),
                syncStatus: syncStatusByPeerKey[key]
            )
        }

        /// Whether the open card's peer can be focused from here — not already focused,
        /// and not the local device (which is never a valid focus target).
        var canFocusOpenPeer: Bool {
            guard let key = detailPeerKey, let localPeer = rawLocalPeer else { return false }
            return key != focusedPeerKey && key != localPeer.peerKeyString
        }

        // MARK: - Peer Search

        /// Query typed into the search box in the Presence tab bar.
        ///
        /// Owned here rather than in the view so it survives the Peers ↔ Viewer
        /// tab switch — that switch tears the scene down and builds a fresh one,
        /// and the query has to be re-applied to it (extension parity: the box is
        /// parent-owned for exactly this reason).
        var searchQuery = "" {
            didSet {
                guard searchQuery != oldValue else { return }
                pushSearchMatchesToScene()
            }
        }

        /// Whether the box holds a real query (whitespace alone does not count).
        var searchIsActive: Bool {
            PresencePeerSearch.isActive(query: searchQuery)
        }

        /// Rows for the results card. Empty while `searchIsActive` is true means
        /// "no peers match" — a distinct state from "not searching".
        var searchMatches: [PresencePeerSearchMatch] {
            PresencePeerSearch.matches(in: searchCandidates, query: searchQuery)
        }

        /// Rebuilt on each (throttled) presence push rather than per keystroke:
        /// at 100+ peers this is the only part of matching worth not repeating.
        private var searchCandidates: [PresencePeerSearchMatch] = []

        /// Armed by a search pick made while Direct is ON — the peer is not in the
        /// scene yet, so the focus has to wait for the rebuilt full-mesh push
        /// (extension `pendingFocusKey`).
        private var pendingFocusPeerKey: String?

        /// Focus a search hit exactly as clicking its pill in the full mesh would.
        ///
        /// With Direct ON the peer may not be in the scene at all (that is the
        /// whole point of searching for it), so this flips Direct off and defers
        /// the focus to the rebuilt graph.
        func focusSearchResult(_ key: String) {
            // The local peer is listed in the card but never focusable.
            guard key != rawLocalPeer?.peerKeyString else { return }
            if showDirectConnectedOnly {
                pendingFocusPeerKey = key
                showDirectConnectedOnly = false // didSet → updateSceneWithCurrentFilter()
                return
            }
            // A card belongs to the focus session that was open when it was
            // raised; changing (or leaving) focus takes it along. `focusPeer`
            // toggles focus OFF when the pick is the already-focused peer, so
            // this cleanup has to run on both branches.
            detailPeerKey = nil
            scene?.hasOpenDetailCard = false
            scene?.focusPeer(key)
        }

        /// Enter/Return in the box focuses the first focusable hit — the
        /// "find a peer without touching the mouse" path.
        func focusFirstSearchResult() {
            guard let first = searchMatches.first(where: { !$0.isLocal }) else { return }
            focusSearchResult(first.key)
        }

        /// Clear the query and restore full opacity. The focus view (if any) is
        /// deliberately left alone.
        func clearSearch() {
            searchQuery = ""
        }

        /// Escape unwinds the **innermost** context first: an open detail card,
        /// then the search query. The focus view survives both — backing out of a
        /// card is not backing out of the peer you are investigating.
        ///
        /// Returns whether anything was consumed, so a key handler can report
        /// `.ignored` and let Escape do its normal job when there is nothing to
        /// unwind.
        @discardableResult
        func handleEscape() -> Bool {
            if detailPeerKey != nil {
                dismissDetail()
                return true
            }
            if searchIsActive {
                clearSearch()
                return true
            }
            return false
        }

        /// Push the current match set to the scene.
        ///
        /// `nil` when the box is empty; an **empty set** when the query has no
        /// hits, which dims the whole graph. Those two are different states and
        /// conflating them is the defect this method exists to avoid.
        /// Re-apply the live query to a freshly built scene. Same push, exposed for
        /// the view's `createScene()` — the scene dies on every tab switch, the
        /// query does not.
        func reapplySearchMatchesToScene() {
            pushSearchMatchesToScene()
        }

        private func pushSearchMatchesToScene() {
            scene?.setSearchMatches(
                searchIsActive ? Set(searchMatches.map(\.key)) : nil
            )
        }

        /// Whether the graph controls (legend, Direct toggle, zoom cluster) are
        /// visible. The eye button and reset control always remain — the VS Code
        /// extension's controls-visibility toggle. Lives on the VM so it survives
        /// tab switches (the VM is hoisted to MainStudioView).
        var controlsVisible = true

        /// Whether the floating-squares background renders + animates. SwiftUI-only
        /// (the Android viewer has no background particles by design).
        var backgroundEffectsEnabled = true {
            didSet {
                scene?.backgroundEffectsEnabled = backgroundEffectsEnabled
            }
        }

        // MARK: - Scene Reference

        /// Reference to the SpriteKit scene for updates
        weak var scene: PresenceNetworkScene?

        // MARK: - Private State

        /// Presence observer for real-time updates
        private var presenceObserver: DittoObserver?

        /// Pending throttled scene update. Presence pushes are throttled to one
        /// scene update per 250 ms fixed window (the VS Code extension's
        /// presence coalesce) so connect/disconnect flapping can't thrash
        /// layout animations. The Direct toggle path
        /// (`updateSceneWithCurrentFilter` from `didSet`) stays immediate.
        private var presencePushTask: Task<Void, Never>?

        /// Raw local peer from the presence graph
        private var rawLocalPeer: PeerProtocol?

        /// All remote peers from the presence graph (unfiltered)
        private var rawRemotePeers: [PeerProtocol] = []

        // MARK: - Initialization

        init() {}

        // MARK: - Production Mode (Real Ditto Presence)

        /// Start observing real Ditto presence graph
        func startProductionMode() async {
            // The enclosing `.task {}` is cancelled when the view disappears.
            // Check before and after the await so a rapid appear→disappear can't
            // register an observer that `stopProductionMode()` already ran past.
            guard !Task.isCancelled else { return }
            guard let ditto = await DittoManager.shared.dittoSelectedApp else {
                Log.warning("PresenceViewerViewModel: No Ditto instance available")
                return
            }
            guard !Task.isCancelled else { return }

            presenceObserver = ditto.presence.observe { [weak self] presenceGraph in
                // Ditto presence callbacks fire on a background thread — hop to main before
                // touching @MainActor state or any SpriteKit node tree APIs.
                let localPeer = presenceGraph.localPeer
                let remotePeers = Array(presenceGraph.remotePeers)
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    rawLocalPeer = localPeer
                    rawRemotePeers = remotePeers
                    // Fixed-window throttle (the extension's presence coalesce,
                    // DittoManager.ts): the first push in a window arms a 250 ms
                    // flush; later pushes only replace the stored graph above;
                    // the flush applies the latest at window end. A
                    // cancel-and-re-sleep debounce would starve the graph under
                    // sustained <250 ms churn. The scene's own topology
                    // snapshots still gate rebuilds on actual changes.
                    if presencePushTask == nil {
                        presencePushTask = Task { @MainActor [weak self] in
                            try? await Task.sleep(for: .milliseconds(250))
                            guard let self else { return }
                            presencePushTask = nil
                            guard !Task.isCancelled else { return }
                            updateSceneWithCurrentFilter()
                            // Sync rows ride the same 250 ms window as the graph push,
                            // so an open card's commit id stays current without adding a
                            // second cadence. Only ever populated for direct peers.
                            await refreshSyncStatus()
                        }
                    }
                }
            }
        }

        /// Stop observing Ditto presence graph
        func stopProductionMode() {
            presenceObserver?.stop()
            presenceObserver = nil
            presencePushTask?.cancel()
            presencePushTask = nil
        }

        // MARK: - Filtering

        /// Push the current filtered graph state to the scene
        func updateSceneWithCurrentFilter() {
            // Rebuilt before the guard below, so a query typed before the scene
            // exists still has candidates.
            //
            // The set is the FULL MESH, never the Direct-mode projection: a
            // multi-hop peer has to be findable while Direct is on, because picking
            // it is exactly how the user jumps the graph over to it.
            //
            // But it is the full mesh *as the scene will actually render it* —
            // `meshVisiblePeerKeys`, the same filter `peersToShow` uses below — not
            // the raw peer list. `PresenceEdgeAggregator` drops edgeless "orphan"
            // peers (a peer discovered over BLE/mDNS before a session exists, or
            // caught in the sync stop→start window), and they never become nodes.
            // Listing them made rows that flip Direct off and then silently fail to
            // focus, because the peer is not in the scene at all.
            searchCandidates = if let localPeer = rawLocalPeer {
                PresencePeerSearch.candidates(
                    localPeer: localPeer,
                    remotePeers: {
                        let visible = PresenceEdgeAggregator.meshVisiblePeerKeys(
                            localPeer: localPeer,
                            remotePeers: rawRemotePeers
                        )
                        return rawRemotePeers.filter { visible.contains($0.peerKeyString) }
                    }()
                )
            } else {
                []
            }

            guard let localPeer = rawLocalPeer, let scene else { return }

            // Both modes derive the visible set from the aggregated edges, which
            // include the local peer's own advertised connections — never from
            // each remote peer's connection list alone, which would hide a peer
            // whose edge only the local side advertises (the multicast
            // asymmetry). Expanded mode additionally drops orphan peers (those
            // in no edge at all) so the sync stop→start window doesn't render
            // floating pills (extension peer-info.ts pass 2). The local peer is
            // always shown.
            let visibleKeys: Set<String> = if showDirectConnectedOnly {
                PresenceEdgeAggregator.directVisiblePeerKeys(
                    localPeer: localPeer,
                    remotePeers: rawRemotePeers
                )
            } else {
                PresenceEdgeAggregator.meshVisiblePeerKeys(
                    localPeer: localPeer,
                    remotePeers: rawRemotePeers
                )
            }
            let peersToShow = rawRemotePeers.filter { visibleKeys.contains($0.peerKeyString) }

            // Sync the filter flag to the scene so it can suppress remote-to-remote edges
            scene.showDirectConnectedOnly = showDirectConnectedOnly
            scene.updatePresenceGraph(localPeer: localPeer, remotePeers: peersToShow)

            // Focus survives the Peers ↔ Viewer tab switch: the scene was torn
            // down and recreated, so re-enter the hoisted focus once the fresh
            // scene has graph state — or clear the hoist (via onFocusChanged)
            // when the peer is gone / Direct mode is on (Android A4 parity).
            if let focusedKey = focusedPeerKey, scene.focusedPeerKey == nil {
                scene.restoreFocusAfterRebuild(for: focusedKey)
            }

            // A search pick that had to flip Direct off lands here, once the
            // rebuilt full-mesh push guarantees the peer is in the scene. Cleared
            // unconditionally: a peer that left the mesh in the meantime must not
            // leave the request armed for the next unrelated push.
            if let pending = pendingFocusPeerKey {
                pendingFocusPeerKey = nil
                detailPeerKey = nil
                scene.hasOpenDetailCard = false
                scene.focusPeer(pending)
            }

            // The scene is rebuilt on every Peers ↔ Viewer switch while this view
            // model is not — re-apply the live query to the fresh scene, or its
            // dimming would silently disappear on the round trip.
            pushSearchMatchesToScene()
        }

        // MARK: - Zoom Control

        /// Zoom in (decrease scale value)
        func zoomIn() {
            let newZoom = max(0.5, zoomLevel - 0.1)
            updateZoomLevel(newZoom)
        }

        /// Zoom out (increase scale value)
        func zoomOut() {
            // 4.0 camera scale = the VS Code extension's 0.25 minimum magnification —
            // the deep zoom-out a large full-mesh layout needs.
            let newZoom = min(4.0, zoomLevel + 0.1)
            updateZoomLevel(newZoom)
        }

        /// Update zoom level and apply to scene camera
        /// - Parameter level: New zoom level (0.5 to 2.0)
        func updateZoomLevel(_ level: CGFloat) {
            zoomLevel = level
            scene?.camera?.setScale(level)
        }

        /// Reset the camera to origin at 100% zoom and snap dragged peers back to their
        /// layout-computed positions. Backs the reset button in the overlay.
        func recenterView() {
            scene?.resetCameraAndRelayout()
            // Local zoom mirror — the scene also fires onZoomChanged(1.0), but updating
            // here makes the % readout flip instantly even if the SK animation lags.
            zoomLevel = 1.0
        }

        /// Exit focus mode (the banner's ✕ button). Any open card goes with it — it is
        /// anchored to a focus session that no longer exists.
        func exitFocusMode() {
            detailPeerKey = nil
            scene?.hasOpenDetailCard = false
            scene?.exitFocusMode()
        }

        /// Toggle the detail card for `key` (accordion: same peer closes, another swaps).
        func toggleDetail(for key: String) {
            detailPeerKey = (detailPeerKey == key) ? nil : key
            scene?.hasOpenDetailCard = detailPeerKey != nil
        }

        /// Dismiss the open card without leaving focus.
        func dismissDetail() {
            detailPeerKey = nil
            scene?.hasOpenDetailCard = false
        }

        /// Focus the peer whose card is open (the card's labelled action), replacing the
        /// traversal that tapping an orbit peer used to provide.
        func focusOpenPeer() {
            guard let key = detailPeerKey else { return }
            dismissDetail()
            // `focusPeer`, NOT `restoreFocusAfterRebuild`. The latter's first guard is
            // `focusedPeerKey == nil`, and this card can only be open while a focus is
            // active (`handlePeerTap` raises it only inside `if focusedPeerKey != nil`)
            // — so that guard could never pass and this labelled action closed the card
            // without ever focusing anything. `focusPeer` is the path that can replace
            // an active focus.
            scene?.focusPeer(key)
        }

        /// Refresh the sync rows. Degrades to an empty lookup rather than failing the
        /// card: the presence-graph half is still worth showing when sync is stopped.
        func refreshSyncStatus() async {
            guard let ditto = await DittoManager.shared.dittoSelectedApp else { return }
            var lookup: [String: SyncStatusInfo] = [:]
            do {
                let results = try await ditto.store.execute(query: "SELECT * FROM system:data_sync_info")
                for item in results.items {
                    let dict = item.value.compactMapValues { $0 }
                    guard let peerKey = dict["_id"] as? String else { continue }
                    lookup[peerKey] = SyncStatusInfo(from: dict)
                }
            } catch {
                Log.debug("Presence detail card: system:data_sync_info unavailable — \(error.localizedDescription)")
            }
            syncStatusByPeerKey = lookup
        }

        // MARK: - Cleanup

        // Note: Cleanup happens automatically when ViewModel is deallocated
        // - DittoObserver cleans up when released
    }
}

// MARK: - Floating Toolbar Controls

/// Drop-in middle-content for `DetailBottomBar` when the Presence Viewer tab is active.
/// Houses what used to be the bottom-right overlay (Direct toggle, reset, ± zoom)
/// inline with the rest of the toolbar so the canvas is unobstructed.
///
/// Caller pattern (inside `MainStudioView.syncTabsDetailView`):
/// ```
/// DetailBottomBar(connections: ...) {
///     if selectedSyncTab == 1 {
///         PresenceViewerToolbarControls(viewModel: presenceViewerVM)
///     }
/// }
/// ```
struct PresenceViewerToolbarControls: View {
    @Bindable var viewModel: PresenceViewerSK.ViewModel

    var body: some View {
        HStack(spacing: 12) {
            if viewModel.controlsVisible {
                // Direct toggle — same short label as Android.
                Toggle("Direct", isOn: $viewModel.showDirectConnectedOnly)
                    .toggleStyle(.switch)
                    .font(.caption)
                    .fixedSize()
                    .help("Show only peers directly connected to this device")

                Divider()
                    .frame(height: 18)
            }

            // Reset (recenter + 100% zoom) — always visible (extension parity).
            Button(action: { viewModel.recenterView() }, label: {
                Image(systemName: "scope")
                    .font(.system(size: 14))
                    .frame(minWidth: 32, minHeight: 32)
                    .contentShape(Rectangle())
            })
            .buttonStyle(.plain)
            .accessibilityLabel("Reset view")
            .help("Reset view — recenter and zoom to 100%")

            if viewModel.controlsVisible {
                // Zoom out.
                Button(action: { viewModel.zoomOut() }, label: {
                    Image(systemName: "minus")
                        .font(.system(size: 14))
                        .frame(minWidth: 32, minHeight: 32)
                        .contentShape(Rectangle())
                })
                .buttonStyle(.plain)
                .disabled(viewModel.zoomLevel >= 4.0)
                .accessibilityLabel("Zoom out")
                .help("Zoom out (or use scroll wheel)")

                // Zoom level readout.
                Text("\(Int(viewModel.zoomLevel * 100))%")
                    .font(.system(size: 12, design: .monospaced))
                    .frame(width: 40, alignment: .center)
                    .accessibilityLabel("Zoom level \(Int(viewModel.zoomLevel * 100)) percent")

                // Zoom in.
                Button(action: { viewModel.zoomIn() }, label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14))
                        .frame(minWidth: 32, minHeight: 32)
                        .contentShape(Rectangle())
                })
                .buttonStyle(.plain)
                .disabled(viewModel.zoomLevel <= 0.5)
                .accessibilityLabel("Zoom in")
                .help("Zoom in (or use scroll wheel)")
            }

            Divider()
                .frame(height: 18)

            // Background effects toggle (SwiftUI-only — the Android viewer has no
            // particles by design).
            Button(action: { viewModel.backgroundEffectsEnabled.toggle() }, label: {
                Image(systemName: viewModel.backgroundEffectsEnabled ? "sparkles" : "sparkle")
                    .font(.system(size: 14))
                    .frame(minWidth: 32, minHeight: 32)
                    .contentShape(Rectangle())
            })
            .buttonStyle(.plain)
            .accessibilityLabel("Toggle background effects")
            .help(viewModel.backgroundEffectsEnabled ? "Hide background effects" : "Show background effects")

            // Controls-visibility (eye) toggle — always visible (extension parity):
            // hides/shows the legend + Direct toggle + zoom cluster.
            Button(action: { viewModel.controlsVisible.toggle() }, label: {
                Image(systemName: viewModel.controlsVisible ? "eye" : "eye.slash")
                    .font(.system(size: 14))
                    .frame(minWidth: 32, minHeight: 32)
                    .contentShape(Rectangle())
            })
            .buttonStyle(.plain)
            .accessibilityLabel("Toggle controls visibility")
            .help(viewModel.controlsVisible ? "Hide graph controls" : "Show graph controls")
        }
    }
}

// MARK: - Preview

#Preview {
    PresenceViewerSK()
        .frame(width: 1000, height: 800)
}
