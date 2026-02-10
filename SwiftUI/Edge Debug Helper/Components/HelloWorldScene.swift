import SpriteKit

/// A simple SpriteKit scene that displays "Hello World" in 8-bit pixel font style
class HelloWorldScene: SKScene {

    override func didMove(to view: SKView) {
        // Set background color to a retro dark blue
        backgroundColor = SKColor(red: 0.1, green: 0.1, blue: 0.2, alpha: 1.0)

        // Create the "Hello World" label with 8-bit styling
        let helloLabel = SKLabelNode(fontNamed: "Courier-Bold")  // Courier is a monospace font that gives 8-bit feel
        helloLabel.text = "HELLO WORLD"
        helloLabel.fontSize = 48
        helloLabel.fontColor = SKColor(red: 0.0, green: 1.0, blue: 0.5, alpha: 1.0)  // Bright green (retro terminal color)
        helloLabel.position = CGPoint(x: size.width / 2, y: size.height / 2)
        addChild(helloLabel)

        // Add a subtle pulsing animation for retro effect
        let fadeOut = SKAction.fadeAlpha(to: 0.7, duration: 1.0)
        let fadeIn = SKAction.fadeAlpha(to: 1.0, duration: 1.0)
        let pulse = SKAction.sequence([fadeOut, fadeIn])
        let repeatPulse = SKAction.repeatForever(pulse)
        helloLabel.run(repeatPulse)

        // Add pixel-style particles for extra retro flair
        addPixelParticles()
    }

    /// Adds some pixel-style particles floating in the background
    private func addPixelParticles() {
        // Create small pixel squares that float around
        let pixelColors: [SKColor] = [
            SKColor(red: 0.0, green: 1.0, blue: 0.5, alpha: 0.3),  // Green
            SKColor(red: 0.0, green: 0.5, blue: 1.0, alpha: 0.3),  // Blue
            SKColor(red: 1.0, green: 0.8, blue: 0.0, alpha: 0.3)   // Yellow
        ]

        for _ in 0..<20 {
            let pixel = SKSpriteNode(color: pixelColors.randomElement()!, size: CGSize(width: 4, height: 4))
            pixel.position = CGPoint(
                x: CGFloat.random(in: 0...size.width),
                y: CGFloat.random(in: 0...size.height)
            )
            addChild(pixel)

            // Animate the pixel floating
            let moveUp = SKAction.moveBy(x: CGFloat.random(in: -20...20), y: 50, duration: 3.0)
            let fadeOut = SKAction.fadeOut(withDuration: 3.0)
            let remove = SKAction.removeFromParent()
            let sequence = SKAction.sequence([SKAction.group([moveUp, fadeOut]), remove])

            // Keep spawning new pixels
            let wait = SKAction.wait(forDuration: Double.random(in: 0...3))
            let spawn = SKAction.run { [weak self] in
                self?.spawnPixel(color: pixelColors.randomElement()!)
            }
            let spawnSequence = SKAction.sequence([wait, spawn])

            pixel.run(sequence)
            run(SKAction.repeatForever(spawnSequence))
        }
    }

    /// Spawns a single pixel particle
    private func spawnPixel(color: SKColor) {
        let pixel = SKSpriteNode(color: color, size: CGSize(width: 4, height: 4))
        pixel.position = CGPoint(
            x: CGFloat.random(in: 0...size.width),
            y: -10  // Start below screen
        )
        addChild(pixel)

        // Animate the pixel floating up
        let moveUp = SKAction.moveBy(x: CGFloat.random(in: -20...20), y: size.height + 20, duration: 5.0)
        let fadeOut = SKAction.fadeOut(withDuration: 5.0)
        let remove = SKAction.removeFromParent()
        let sequence = SKAction.sequence([SKAction.group([moveUp, fadeOut]), remove])
        pixel.run(sequence)
    }
}
