import CoreGraphics
import Testing

import DittoSwift

@testable import Ditto_Edge_Studio

// MARK: - PresenceFocusPlanner Tests
//
// The pure decisions behind focus mode (Expanded/full-mesh view): which peers
// form the focused neighbourhood, and the camera scale the focus view zooms to.
// Mirrors the VS Code extension's `scene.ts` (`neighboursOf`,
// `clampZoom(min(max(zoom, FOCUS_ZOOM), fitZoom))`).

@Suite("PresenceFocusPlanner Tests")
struct PresenceFocusPlannerTests {
    private func edge(_ from: String, _ to: String, _ type: DittoConnectionType = .p2pWiFi) -> PresenceEdge {
        PresenceEdge(
            connectionId: "\([from, to].sorted().joined(separator: "_"))_\(type)",
            pairKey: [from, to].sorted().joined(separator: "_"),
            from: from,
            to: to,
            type: type
        )
    }

    @Test("neighbourKeys collects both edge directions, excluding self", .tags(.fast))
    func neighbourKeysBothDirections() {
        // ARRANGE
        let edges = [
            edge("A", "local"), edge("A", "B"), edge("B", "C"), edge("A", "A"),
        ]

        // ACT
        let neighbours = PresenceFocusPlanner.neighbourKeys(of: "A", edges: edges)

        // ASSERT — B and local; the self-loop A↔A contributes A but self is never
        // a neighbour of itself in a focus orbit.
        #expect(neighbours == ["B", "local"].sorted())
    }

    @Test("neighbourKeys of an isolated peer is empty", .tags(.fast))
    func neighbourKeysEmpty() {
        #expect(PresenceFocusPlanner.neighbourKeys(of: "ghost", edges: [edge("A", "B")]).isEmpty)
    }

    @Test("focus camera scale: small neighbourhood zooms in to 1.25× (scale 0.8)", .tags(.fast))
    func focusScaleSmallNeighbourhood() {
        // ARRANGE — small orbit: content = 300+80+176 = 556 → fit = 556/800 = 0.695
        // (under the 1.25× target scale of 0.8 on both axes).
        let fit = PresenceFocusPlanner.fitScale(
            layoutRadius: 150,
            maxPillWidth: 80,
            viewSize: CGSize(width: 1000, height: 800),
            padding: 88
        )
        #expect(fit < 0.8)

        // ACT
        let scale = PresenceFocusPlanner.focusCameraScale(fitScale: fit, currentScale: 1.0)

        // ASSERT — the 1.25× close-up applies
        #expect(scale == 0.8)
    }

    @Test("focus camera scale: a large neighbourhood never exceeds the fit", .tags(.fast))
    func focusScaleLargeNeighbourhoodFits() {
        // ARRANGE — content = 800+80+176 = 1056 → fit = max(1.056, 1.32) = 1.32,
        // inside the app's [0.5, 4.0] camera range and above the 1.25× target.
        let fit = PresenceFocusPlanner.fitScale(
            layoutRadius: 400,
            maxPillWidth: 80,
            viewSize: CGSize(width: 1000, height: 800),
            padding: 88
        )
        #expect(fit > 0.8 && fit <= 2.0)

        // ACT
        let scale = PresenceFocusPlanner.focusCameraScale(fitScale: fit, currentScale: 1.0)

        // ASSERT — fit wins over the 1.25× target
        #expect(scale == fit)
    }

    @Test("focus camera scale: a zoomed-in user is pulled out to the fit", .tags(.fast))
    func focusScaleZoomedInUser() {
        // ARRANGE — user magnified to 2× (scale 0.5), neighbourhood needs 1.2 to fit.
        let scale = PresenceFocusPlanner.focusCameraScale(fitScale: 1.2, currentScale: 0.5)

        // ASSERT — max(1.2, min(0.5, 0.8)) = 1.2 (zooms out to fit)
        #expect(scale == 1.2)
    }

    @Test("focus camera scale: never leaves the app's [0.5, 4.0] camera range", .tags(.fast))
    func focusScaleClamped() {
        #expect(PresenceFocusPlanner.focusCameraScale(fitScale: 0.1, currentScale: 0.1) == 0.5)
        #expect(PresenceFocusPlanner.focusCameraScale(fitScale: 9.9, currentScale: 4.0) == 4.0)
    }

    @Test("fitScale: degenerate inputs fall back to 1.0", .tags(.fast))
    func fitScaleDegenerate() {
        #expect(
            PresenceFocusPlanner.fitScale(
                layoutRadius: 0, maxPillWidth: 60, viewSize: CGSize(width: 100, height: 100), padding: 64
            ) == 1
        )
        #expect(
            PresenceFocusPlanner.fitScale(
                layoutRadius: 100, maxPillWidth: 60, viewSize: .zero, padding: 64
            ) == 1
        )
    }
}
