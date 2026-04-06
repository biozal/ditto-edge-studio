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

    init() {
        _viewModel = State(initialValue: ViewModel())
    }

    var body: some View {
        // Main scene view with overlays
        ZStack(alignment: .bottomTrailing) {
            // SpriteKit scene
            SpriteKitSceneView(scene: $scene, viewModel: viewModel)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .focusable() // Allow view to receive keyboard and scroll events

            // Bottom-right controls (Direct Connected toggle + zoom controls)
            // Bottom padding clears the DetailBottomBar overlay (~56pt) that sits
            // at the bottom of the parent syncTabsDetailView.
            VStack(alignment: .trailing, spacing: 8) {
                directConnectedToggle
                zoomControls
            }
            .padding(.trailing, 16)
            .padding(.bottom, 72)

            // Connection legend overlay (bottom-left)
            VStack {
                Spacer()
                HStack {
                    connectionLegend
                        .padding(.leading, 16)
                        .padding(.bottom, 72)
                    Spacer()
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

    // MARK: - Direct Connected Toggle

    /// Toggle switch to filter peers to only directly connected ones
    private var directConnectedToggle: some View {
        Toggle("Direct Connected", isOn: Binding(
            get: { viewModel.showDirectConnectedOnly },
            set: { viewModel.showDirectConnectedOnly = $0 }
        ))
        .toggleStyle(.switch)
        .font(.caption)
        .padding(8)
        .background(.ultraThinMaterial)
        .cornerRadius(8)
        .help("Show only peers directly connected to this device")
    }

    // MARK: - Zoom Controls

    /// Zoom controls overlay with +/- buttons and level indicator
    private var zoomControls: some View {
        HStack(spacing: 8) {
            // Zoom out button (-)
            Button(action: { viewModel.zoomOut() }, label: {
                Image(systemName: "minus")
            })
            .buttonStyle(.glass)
            .clipShape(Circle())
            .disabled(viewModel.zoomLevel >= 2.0)
            .help("Zoom out (or use scroll wheel)")

            // Zoom level indicator
            Text("\(Int(viewModel.zoomLevel * 100))%")
                .font(.caption)
                .frame(width: 50)

            // Zoom in button (+)
            Button(action: { viewModel.zoomIn() }, label: {
                Image(systemName: "plus")
            })
            .buttonStyle(.glass)
            .clipShape(Circle())
            .disabled(viewModel.zoomLevel <= 0.5)
            .help("Zoom in (or use scroll wheel)")
        }
        .padding(8)
        .background(.ultraThinMaterial)
        .cornerRadius(8)
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

        // Set up zoom change callback
        newScene.onZoomChanged = { [weak viewModel] newZoom in
            viewModel?.updateZoomLevel(newZoom)
        }

        scene = newScene
        viewModel.scene = newScene

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

        // MARK: - Scene Reference

        /// Reference to the SpriteKit scene for updates
        weak var scene: PresenceNetworkScene?

        // MARK: - Private State

        /// Presence observer for real-time updates
        private var presenceObserver: DittoObserver?

        /// Raw local peer from the presence graph
        private var rawLocalPeer: PeerProtocol?

        /// All remote peers from the presence graph (unfiltered)
        private var rawRemotePeers: [PeerProtocol] = []

        // MARK: - Initialization

        init() {
            Task {
                await startProductionMode()
            }
        }

        // MARK: - Production Mode (Real Ditto Presence)

        /// Start observing real Ditto presence graph
        func startProductionMode() async {
            guard let ditto = await DittoManager.shared.dittoSelectedApp else {
                Log.warning("PresenceViewerViewModel: No Ditto instance available")
                return
            }

            presenceObserver = ditto.presence.observe { [weak self] presenceGraph in
                // Ditto presence callbacks fire on a background thread — hop to main before
                // touching @MainActor state or any SpriteKit node tree APIs.
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }

                    rawLocalPeer = presenceGraph.localPeer
                    rawRemotePeers = Array(presenceGraph.remotePeers)

                    updateSceneWithCurrentFilter()
                }
            }
        }

        /// Stop observing Ditto presence graph
        func stopProductionMode() {
            presenceObserver?.stop()
            presenceObserver = nil
        }

        // MARK: - Filtering

        /// Returns only peers directly connected to the local peer
        private func directlyConnectedPeers(
            from peers: [PeerProtocol],
            localPeerKey: String
        ) -> [PeerProtocol] {
            peers.filter { peer in
                peer.connectionProtocols.contains {
                    $0.peerKeyString1 == localPeerKey || $0.peerKeyString2 == localPeerKey
                }
            }
        }

        /// Push the current filtered graph state to the scene
        func updateSceneWithCurrentFilter() {
            guard let localPeer = rawLocalPeer, let scene else { return }

            let peersToShow: [PeerProtocol] = if showDirectConnectedOnly {
                directlyConnectedPeers(
                    from: rawRemotePeers,
                    localPeerKey: localPeer.peerKeyString
                )
            } else {
                rawRemotePeers
            }

            // Sync the filter flag to the scene so it can suppress remote-to-remote edges
            scene.showDirectConnectedOnly = showDirectConnectedOnly
            scene.updatePresenceGraph(localPeer: localPeer, remotePeers: peersToShow)
        }

        // MARK: - Zoom Control

        /// Zoom in (decrease scale value)
        func zoomIn() {
            let newZoom = max(0.5, zoomLevel - 0.1)
            updateZoomLevel(newZoom)
        }

        /// Zoom out (increase scale value)
        func zoomOut() {
            let newZoom = min(2.0, zoomLevel + 0.1)
            updateZoomLevel(newZoom)
        }

        /// Update zoom level and apply to scene camera
        /// - Parameter level: New zoom level (0.5 to 2.0)
        func updateZoomLevel(_ level: CGFloat) {
            zoomLevel = level
            scene?.camera?.setScale(level)
        }

        // MARK: - Cleanup

        // Note: Cleanup happens automatically when ViewModel is deallocated
        // - DittoObserver cleans up when released
    }
}

// MARK: - Preview

#Preview {
    PresenceViewerSK()
        .frame(width: 1000, height: 800)
}
