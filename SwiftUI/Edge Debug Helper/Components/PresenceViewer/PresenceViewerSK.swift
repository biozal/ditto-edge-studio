import SwiftUI
import SpriteKit
import DittoSwift

/// SwiftUI wrapper for the Presence Network Viewer
/// Displays a dynamic network diagram of Ditto peers with connection visualization
/// Accesses DittoManager.shared singleton directly (no Ditto parameter needed)
struct PresenceViewerSK: View {
    @State private var viewModel: PresenceViewerViewModel
    @State private var scene: PresenceNetworkScene?

    init() {
        _viewModel = State(initialValue: PresenceViewerViewModel())
    }

    var body: some View {
        VStack(spacing: 0) {
            // Test mode toggle bar
            testModeToggle

            // Main scene view with overlays
            ZStack(alignment: .bottomTrailing) {
                // SpriteKit scene
                SpriteKitSceneView(scene: $scene, viewModel: viewModel)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Zoom controls overlay (bottom-right)
                zoomControls
                    .padding(16)

                // Connection legend overlay (bottom-left)
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

    /// Test mode toggle bar at top of view
    private var testModeToggle: some View {
        HStack {
            Spacer()

            Toggle("Test Mode", isOn: Binding(
                get: { viewModel.isTestMode },
                set: { viewModel.isTestMode = $0 }
            ))
            .toggleStyle(.switch)
            .help("Enable test mode to use mock data with 30 simulated devices")

            if viewModel.isTestMode {
                Text("Using Mock Data")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

    /// Zoom controls overlay with +/- buttons and level indicator
    private var zoomControls: some View {
        HStack(spacing: 8) {
            // Zoom out button (-)
            Button(action: { viewModel.zoomOut() }) {
                FontAwesomeText(icon: ActionIcon.minus, size: 14)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.zoomLevel >= 2.0)
            .help("Zoom out (or use scroll wheel)")

            // Zoom level indicator
            Text("\(Int(viewModel.zoomLevel * 100))%")
                .font(.caption)
                .frame(width: 50)

            // Zoom in button (+)
            Button(action: { viewModel.zoomIn() }) {
                FontAwesomeText(icon: ActionIcon.plus, size: 14)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.bordered)
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

    /// Creates and configures the SpriteKit scene
    private func createScene() {
        let newScene = PresenceNetworkScene()

        // Configure scene size (larger for better quality)
        newScene.size = CGSize(width: 1000, height: 800)
        newScene.scaleMode = .aspectFill

        // Connect scene and ViewModel (bidirectional communication)
        newScene.viewModel = viewModel

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

// MARK: - SpriteKit Scene View (NSViewRepresentable)

/// NSViewRepresentable wrapper for SKView
struct SpriteKitSceneView: NSViewRepresentable {
    @Binding var scene: PresenceNetworkScene?
    let viewModel: PresenceViewerViewModel

    func makeNSView(context: Context) -> SKView {
        let skView = SKView()
        skView.ignoresSiblingOrder = true
        skView.showsFPS = false // Set to true for debugging
        skView.showsNodeCount = false // Set to true for debugging
        skView.allowsTransparency = true // Allow transparent background

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

// MARK: - Preview

#Preview {
    PresenceViewerSK()
        .frame(width: 1000, height: 800)
}
