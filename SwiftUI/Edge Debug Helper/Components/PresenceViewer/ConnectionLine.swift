//
//  ConnectionLine.swift
//  Edge Debug Helper
//
//  Created by Claude on 2026-02-10.
//  Phase 2: Scene Architecture - Connection Line Rendering
//

import AppKit
import DittoSwift
import SpriteKit

/// Renders connection lines between peer nodes with accessibility-first dash patterns
class ConnectionLine: SKNode {
    // MARK: - Properties

    let fromPeerKey: String
    let toPeerKey: String
    let connectionType: DittoConnectionType
    let isCloudConnection: Bool // Special flag for cloud connections

    private var shapeNode: SKShapeNode!
    private var dashPattern: [CGFloat]
    private var lineColor: NSColor
    private var cloudCircles: [SKShapeNode] = []

    // MARK: - Initialization

    private var lineOffset: CGFloat = 0

    init(
        from: String,
        to: String,
        type: DittoConnectionType,
        fromPos: CGPoint,
        toPos: CGPoint,
        offset: CGFloat = 0,
        isCloudConnection: Bool = false
    ) {
        fromPeerKey = from
        toPeerKey = to
        connectionType = type
        lineOffset = offset
        self.isCloudConnection = isCloudConnection

        // Set color and dash pattern based on connection type
        if isCloudConnection {
            // Cloud connections are always purple with special pattern
            lineColor = .systemPurple
            dashPattern = [8, 4] // Medium dashes for cloud
        } else {
            switch type {
            case .bluetooth:
                lineColor = .systemBlue
                dashPattern = [3, 2] // Small dashes

            case .accessPoint: // LAN
                lineColor = .systemGreen
                dashPattern = [16, 3] // Very long dashes (distinct from P2P)

            case .p2pWiFi:
                lineColor = .systemPink
                dashPattern = [6, 3] // Shorter dashes (distinct from LAN)

            case .webSocket:
                lineColor = .systemOrange
                dashPattern = [10, 3, 2, 3] // Dash-dot pattern

            @unknown default:
                // Default/unknown connection type
                lineColor = .systemGray
                dashPattern = [6, 3]
            }
        }

        super.init()

        name = "ConnectionLine_\(from)_\(to)_\(type)"

        createLine(from: fromPos, to: toPos)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Line Creation

    private func createLine(from: CGPoint, to: CGPoint) {
        // Create path
        let path = createCurvedPath(from: from, to: to)

        // Create shape node with dashed path
        shapeNode = SKShapeNode(path: path)
        shapeNode.strokeColor = lineColor.withAlphaComponent(0.7)
        shapeNode.lineWidth = 2.0
        shapeNode.lineCap = .round
        shapeNode.lineJoin = .round
        shapeNode.name = "shapePath"

        addChild(shapeNode)

        // Add cloud pattern (circles along line) for cloud connections
        if isCloudConnection {
            addCloudPattern(from: from, to: to)
        }
    }

    private func createCurvedPath(from: CGPoint, to: CGPoint) -> CGPath {
        let path = CGMutablePath()

        let dx = to.x - from.x
        let dy = to.y - from.y
        let distance = sqrt(dx * dx + dy * dy)

        // Handle zero-distance case (both points at same location)
        // This can happen when nodes are first created at (0,0) before layout
        if distance < 0.1 {
            // Draw a simple point - will be invisible but prevents NaN errors
            path.move(to: from)
            path.addLine(to: from)
            return path
        }

        // Apply line offset perpendicular to the line
        var fromPoint = from
        var toPoint = to

        if lineOffset != 0 {
            let offsetX = -dy / distance * lineOffset
            let offsetY = dx / distance * lineOffset

            fromPoint = CGPoint(x: from.x + offsetX, y: from.y + offsetY)
            toPoint = CGPoint(x: to.x + offsetX, y: to.y + offsetY)
        }

        // Calculate control point for quadratic curve
        // Control point is offset perpendicular to the line
        let midX = (fromPoint.x + toPoint.x) / 2
        let midY = (fromPoint.y + toPoint.y) / 2

        // Curve amount based on distance (more curve for longer lines)
        let curveAmount = min(distance * 0.15, 60.0)

        // Perpendicular offset for curve
        let perpX = -dy / distance * curveAmount
        let perpY = dx / distance * curveAmount

        let controlPoint = CGPoint(x: midX + perpX, y: midY + perpY)

        // Create quadratic curve
        path.move(to: fromPoint)
        path.addQuadCurve(to: toPoint, control: controlPoint)

        // Apply dash pattern
        return path.copy(dashingWithPhase: 0, lengths: dashPattern)
    }

    // MARK: - Public Methods

    /// Update the line path when peer positions change
    func updatePath(fromPos: CGPoint, toPos: CGPoint) {
        let newPath = createCurvedPath(from: fromPos, to: toPos)
        shapeNode.path = newPath

        // Update cloud circles if they exist
        updateCloudCircles(from: fromPos, to: toPos)
    }

    /// Set the highlighted state of the connection line
    func setHighlighted(_ highlighted: Bool) {
        if highlighted {
            shapeNode.strokeColor = lineColor.withAlphaComponent(1.0)
            shapeNode.lineWidth = 3.0

            // Add glow effect
            let glow = SKAction.sequence([
                SKAction.fadeAlpha(to: 1.0, duration: 0.2),
                SKAction.fadeAlpha(to: 0.8, duration: 0.2)
            ])
            shapeNode.run(SKAction.repeatForever(glow), withKey: "highlightGlow")
        } else {
            shapeNode.removeAction(forKey: "highlightGlow")
            shapeNode.strokeColor = lineColor.withAlphaComponent(0.7)
            shapeNode.lineWidth = 2.0
        }
    }

    /// Add cloud pattern (circles along the line) for cloud connections
    func addCloudPattern(from: CGPoint, to: CGPoint) {
        // Clear existing circles
        cloudCircles.forEach { $0.removeFromParent() }
        cloudCircles.removeAll()

        // Calculate number of circles based on distance
        let dx = to.x - from.x
        let dy = to.y - from.y
        let distance = sqrt(dx * dx + dy * dy)
        let circleSpacing: CGFloat = 40.0
        let numCircles = Int(distance / circleSpacing)

        guard numCircles > 0 else { return }

        // Sample points along the curve
        for i in 1 ..< numCircles {
            let t = CGFloat(i) / CGFloat(numCircles)
            let point = sampleCurve(from: from, to: to, t: t)

            // Create small circle
            let circle = SKShapeNode(circleOfRadius: 3)
            circle.fillColor = lineColor
            circle.strokeColor = .clear
            circle.position = point
            circle.alpha = 0.8
            circle.name = "cloudCircle"

            addChild(circle)
            cloudCircles.append(circle)
        }
    }

    private func updateCloudCircles(from: CGPoint, to: CGPoint) {
        guard !cloudCircles.isEmpty else { return }

        let numCircles = cloudCircles.count

        for (index, circle) in cloudCircles.enumerated() {
            let t = CGFloat(index + 1) / CGFloat(numCircles + 1)
            let point = sampleCurve(from: from, to: to, t: t)
            circle.position = point
        }
    }

    private func sampleCurve(from: CGPoint, to: CGPoint, t: CGFloat) -> CGPoint {
        // Sample quadratic Bezier curve at parameter t
        let midX = (from.x + to.x) / 2
        let midY = (from.y + to.y) / 2

        let dx = to.x - from.x
        let dy = to.y - from.y
        let distance = sqrt(dx * dx + dy * dy)

        // Handle zero-distance case
        if distance < 0.1 {
            return from
        }

        let curveAmount = min(distance * 0.15, 60.0)
        let perpX = -dy / distance * curveAmount
        let perpY = dx / distance * curveAmount

        let controlPoint = CGPoint(x: midX + perpX, y: midY + perpY)

        // Quadratic Bezier formula: B(t) = (1-t)²P0 + 2(1-t)tP1 + t²P2
        let oneMinusT = 1 - t
        let x = oneMinusT * oneMinusT * from.x + 2 * oneMinusT * t * controlPoint.x + t * t * to.x
        let y = oneMinusT * oneMinusT * from.y + 2 * oneMinusT * t * controlPoint.y + t * t * to.y

        return CGPoint(x: x, y: y)
    }

    /// Get the connection type for this line
    func getConnectionType() -> DittoConnectionType {
        connectionType
    }

    /// Get the line color
    func getColor() -> NSColor {
        lineColor
    }
}
