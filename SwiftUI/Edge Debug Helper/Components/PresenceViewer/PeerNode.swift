//
//  PeerNode.swift
//  Edge Debug Helper
//
//  Created by Claude on 2026-02-10.
//  Phase 2: Scene Architecture - Peer Node with Simple Pill Shape
//

import AppKit
import SpriteKit

/// Peer node in the presence network diagram using simple pill/capsule shape.
/// Similar to JavaScript implementation with colored pills and readable text.
class PeerNode: SKNode {
    // MARK: - Properties

    let peerKey: String
    let deviceName: String
    let isLocal: Bool
    let deviceType: DeviceType

    private var pillShape: SKShapeNode!
    var labelNode: SKLabelNode!

    // MARK: - Constants

    private let pillHeight: CGFloat = 22.5 // Scaled down 50% total (40 * 0.75 * 0.75)
    private let pillPadding: CGFloat = 11.25 // Scaled down 50% total (20 * 0.75 * 0.75)
    private let fontSize: CGFloat = 9 // Scaled down 50% total (16 * 0.75 * 0.75)

    // MARK: - Device Type Enum

    enum DeviceType {
        case phone
        case laptop
        case cloud
        case server

        /// Detect device type from device name string
        static func detect(from deviceName: String) -> DeviceType {
            let lowerName = deviceName.lowercased()

            if lowerName.contains("iphone") || lowerName.contains("ipad") ||
                lowerName.contains("pixel") || lowerName.contains("galaxy") ||
                lowerName.contains("mobile") || lowerName.contains("android")
            {
                return .phone
            } else if lowerName.contains("macbook") || lowerName.contains("imac") ||
                lowerName.contains("mac mini") || lowerName.contains("mac studio") ||
                lowerName.contains("windows") || lowerName.contains("surface") ||
                lowerName.contains("laptop")
            {
                return .laptop
            } else if lowerName.contains("cloud") || lowerName.contains("ditto") {
                return .cloud
            } else {
                return .server
            }
        }
    }

    // MARK: - Initialization

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

        name = "PeerNode_\(peerKey)"

        setupPillShape()
        setupLabel()
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup Methods

    private func setupPillShape() {
        // Determine text to measure (use "Me" for local peer)
        let displayText = isLocal ? "Me" : deviceName

        // Measure text width
        let tempLabel = SKLabelNode(text: displayText)
        tempLabel.fontName = "Helvetica-Bold"
        tempLabel.fontSize = fontSize
        let textWidth = tempLabel.frame.width

        // Calculate pill width
        let pillWidth = textWidth + (pillPadding * 2)
        let cornerRadius = pillHeight / 2

        // Create rounded rectangle (pill shape)
        let pillPath = CGPath(
            roundedRect: CGRect(x: -pillWidth / 2, y: -pillHeight / 2, width: pillWidth, height: pillHeight),
            cornerWidth: cornerRadius,
            cornerHeight: cornerRadius,
            transform: nil
        )

        pillShape = SKShapeNode(path: pillPath)

        // Set colors based on local/remote
        if isLocal {
            // Local peer: Blue background (like "Me" in JavaScript version)
            pillShape.fillColor = NSColor.systemBlue
            pillShape.strokeColor = NSColor.systemBlue.withAlphaComponent(0.8)
        } else {
            // Remote peers: Green background (like JavaScript version)
            pillShape.fillColor = NSColor.systemGreen
            pillShape.strokeColor = NSColor.systemGreen.withAlphaComponent(0.8)
        }

        pillShape.lineWidth = 2
        pillShape.name = "pillShape"
        addChild(pillShape)
    }

    private func setupLabel() {
        // Display "Me" for local peer, full device name for remote peers
        let displayText = isLocal ? "Me" : deviceName

        labelNode = SKLabelNode(text: displayText)
        labelNode.fontName = "Helvetica-Bold"
        labelNode.fontSize = fontSize
        labelNode.fontColor = .white
        labelNode.verticalAlignmentMode = .center
        labelNode.horizontalAlignmentMode = .center
        labelNode.position = CGPoint(x: 0, y: 0) // Center of pill
        labelNode.name = "label"

        addChild(labelNode)
    }

    // MARK: - Public Methods

    /// Set the highlighted state of the peer node
    func setHighlighted(_ highlighted: Bool) {
        let targetScale: CGFloat = highlighted ? 1.1 : 1.0

        let scaleAction = SKAction.scale(to: targetScale, duration: 0.15)
        scaleAction.timingMode = .easeOut
        run(scaleAction, withKey: "highlightScale")

        // Increase opacity when highlighted
        if highlighted {
            pillShape.alpha = 1.0
        } else {
            pillShape.alpha = 0.9
        }
    }

    /// Update the device name label
    func updateDeviceName(_ newName: String) {
        if !isLocal {
            labelNode.text = newName

            // Recreate pill shape with new width
            pillShape.removeFromParent()
            setupPillShape()

            // Ensure label stays on top
            labelNode.removeFromParent()
            addChild(labelNode)
        }
    }

    /// Get the size of the pill for collision detection
    func getSpriteSize() -> CGSize {
        CGSize(width: pillShape.frame.width, height: pillHeight)
    }
}
