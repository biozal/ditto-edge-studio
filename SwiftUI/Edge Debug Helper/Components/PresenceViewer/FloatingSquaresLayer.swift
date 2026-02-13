import SpriteKit

/// Manages a layer of animated floating squares for background decoration
/// Inspired by the ditto.com website design with subtle data block visualization
class FloatingSquaresLayer {

    private var squares: [SKSpriteNode] = []
    private var parentScene: SKScene?

    /// Sets up the floating squares layer
    /// - Parameters:
    ///   - scene: The parent SKScene to add squares to
    ///   - count: Number of squares to create (default: 105 for dense star field)
    func setup(in scene: SKScene, count: Int = 105) {
        parentScene = scene

        for _ in 0..<count {
            let square = createSquare(sceneSize: scene.size)
            squares.append(square)
        }
    }

    /// Adds all squares to the scene
    func addToScene(_ scene: SKScene) {
        for square in squares {
            scene.addChild(square)
        }
    }

    /// Removes all squares from the scene
    func removeFromScene() {
        for square in squares {
            square.removeAllActions()
            square.removeFromParent()
        }
        squares.removeAll()
        parentScene = nil
    }

    // MARK: - Private Methods

    /// Creates a single floating diamond with consistent size
    /// - Parameter sceneSize: The size of the parent scene for positioning
    /// - Returns: Configured SKShapeNode representing a floating diamond
    private func createSquare(sceneSize: CGSize) -> SKSpriteNode {
        // Fixed 4×4 diamond size for consistent star field
        let diamondSize: CGFloat = 4

        // Semi-transparent grays/blues
        let colors: [SKColor] = [
            SKColor(white: 0.5, alpha: 0.3),
            SKColor(white: 0.6, alpha: 0.35),
            SKColor(white: 0.7, alpha: 0.4),
            SKColor(red: 0.4, green: 0.5, blue: 0.6, alpha: 0.35),
            SKColor(red: 0.5, green: 0.6, blue: 0.7, alpha: 0.4),
            SKColor(red: 0.3, green: 0.4, blue: 0.5, alpha: 0.45)
        ]

        // Create diamond path (rotated square)
        let diamondPath = CGMutablePath()
        let halfSize = diamondSize / 2

        // Start at top point
        diamondPath.move(to: CGPoint(x: 0, y: halfSize))
        // Right point
        diamondPath.addLine(to: CGPoint(x: halfSize, y: 0))
        // Bottom point
        diamondPath.addLine(to: CGPoint(x: 0, y: -halfSize))
        // Left point
        diamondPath.addLine(to: CGPoint(x: -halfSize, y: 0))
        // Close path
        diamondPath.closeSubpath()

        // Create shape node for diamond
        let diamond = SKShapeNode(path: diamondPath)
        diamond.fillColor = colors.randomElement()!
        diamond.strokeColor = .clear
        diamond.lineWidth = 0

        // Wrap in sprite node for consistent animation behavior
        let square = SKSpriteNode()
        square.addChild(diamond)

        // Random position within a smaller range to keep stars near the diagram
        // Scene is centered at 0,0, so constrain to ±600 range (1200x1200 total area)
        let maxRange: CGFloat = 600
        square.position = CGPoint(
            x: CGFloat.random(in: -maxRange...maxRange),
            y: CGFloat.random(in: -maxRange...maxRange)
        )

        // Deep background layer
        square.zPosition = -100

        // Apply random animation type
        let animationType = Int.random(in: 0..<100)

        switch animationType {
        case 0..<80:  // 80% Drifters (20% more movement)
            applyDriftAnimation(to: square, sceneSize: sceneSize)
        case 80..<90:  // 10% Pulsers
            applyPulseAnimation(to: square)
        default:  // 10% Spinners
            applySpinAnimation(to: square)
        }

        return square
    }

    /// Applies slow continuous drift animation
    /// - Parameters:
    ///   - square: The square to animate
    ///   - sceneSize: The size of the parent scene for movement bounds
    private func applyDriftAnimation(to square: SKSpriteNode, sceneSize: CGSize) {
        let duration = TimeInterval.random(in: 8...12)

        // Random drift within bounds
        let deltaX = CGFloat.random(in: -50...50)
        let deltaY = CGFloat.random(in: -40...40)

        // Calculate new position, wrapping if needed
        var newX = square.position.x + deltaX
        var newY = square.position.y + deltaY

        // Wrap around within ±600 range (centered at 0,0)
        let maxRange: CGFloat = 600
        if newX < -maxRange { newX += (maxRange * 2) }
        if newX > maxRange { newX -= (maxRange * 2) }
        if newY < -maxRange { newY += (maxRange * 2) }
        if newY > maxRange { newY -= (maxRange * 2) }

        let move = SKAction.move(to: CGPoint(x: newX, y: newY), duration: duration)
        move.timingMode = .easeInEaseOut

        let sequence = SKAction.sequence([
            move,
            SKAction.run { [weak self, weak square] in
                guard let self = self,
                      let square = square,
                      let sceneSize = self.parentScene?.size else { return }
                self.applyDriftAnimation(to: square, sceneSize: sceneSize)
            }
        ])

        square.run(sequence)
    }

    /// Applies scale and fade pulse animation
    /// - Parameter square: The square to animate
    private func applyPulseAnimation(to square: SKSpriteNode) {
        let duration = TimeInterval.random(in: 3...5)

        let scaleUp = SKAction.scale(to: 1.2, duration: duration / 2)
        scaleUp.timingMode = .easeInEaseOut

        let scaleDown = SKAction.scale(to: 1.0, duration: duration / 2)
        scaleDown.timingMode = .easeInEaseOut

        let fadeOut = SKAction.fadeAlpha(to: 0.5, duration: duration / 2)
        fadeOut.timingMode = .easeInEaseOut

        let fadeIn = SKAction.fadeAlpha(to: 1.0, duration: duration / 2)
        fadeIn.timingMode = .easeInEaseOut

        let pulseOut = SKAction.group([scaleUp, fadeOut])
        let pulseIn = SKAction.group([scaleDown, fadeIn])

        let sequence = SKAction.sequence([pulseOut, pulseIn])
        let repeatForever = SKAction.repeatForever(sequence)

        square.run(repeatForever)
    }

    /// Applies slow rotation animation
    /// - Parameter square: The square to animate
    private func applySpinAnimation(to square: SKSpriteNode) {
        let duration = TimeInterval.random(in: 20...30)

        let rotate = SKAction.rotate(byAngle: .pi * 2, duration: duration)
        let repeatForever = SKAction.repeatForever(rotate)

        square.run(repeatForever)
    }
}
