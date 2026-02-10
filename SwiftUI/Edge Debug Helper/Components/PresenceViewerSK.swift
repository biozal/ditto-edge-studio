import SwiftUI
import SpriteKit

/// A prototype SwiftUI view that demonstrates SpriteKit integration
/// Displays a simple "Hello World" scene using SpriteKit
struct PresenceViewerSK: View {
    @State private var scene: SKScene?

    var body: some View {
        VStack {
            if let scene = scene {
                SpriteView(scene: scene)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()
            } else {
                ProgressView("Loading SpriteKit Scene...")
            }
        }
        .onAppear {
            createScene()
        }
        .onDisappear {
            cleanupScene()
        }
    }

    /// Creates and configures the SpriteKit scene
    private func createScene() {
        let newScene = HelloWorldScene()

        // Configure scene size to match view
        // Using a large size ensures good quality on any display
        newScene.size = CGSize(width: 800, height: 600)

        // Scale mode determines how the scene fits in the view
        // .aspectFill ensures the scene fills the view while maintaining aspect ratio
        newScene.scaleMode = SKSceneScaleMode.aspectFill

        scene = newScene
    }

    /// Cleanup SpriteKit resources when view disappears
    /// This prevents memory leaks and unnecessary GPU usage
    private func cleanupScene() {
        scene?.removeAllChildren()
        scene?.removeAllActions()
        scene?.removeFromParent()
        scene = nil
    }
}

#Preview {
    PresenceViewerSK()
        .frame(width: 800, height: 600)
}
