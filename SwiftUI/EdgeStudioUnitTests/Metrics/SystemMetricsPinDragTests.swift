import Foundation
import SwiftUI
import Testing
@testable import Ditto_Edge_Studio

/// Covers `SystemMetricsPinOrdering.dropIndex`, which resolves where a pinned-row
/// drag would land.
///
/// Two defects motivated these. A drag from the bottom of the list stalled part
/// way and could not be resumed without releasing the row and grabbing it again —
/// the live re-order moved the dragged row's view out from under its own gesture.
/// And ordinary hand tremor made the insertion point flick back and forth.
@Suite("SystemMetrics pin drag tests")
struct SystemMetricsPinDragTests {
    /// Replays a drag one update at a time, exactly as the view does: the slot
    /// resolved on the previous update feeds the next.
    private func replay(_ translations: [CGFloat], heights: [CGFloat], startIndex: Int) -> (slot: Int, changes: Int) {
        var slot = startIndex
        var changes = 0
        for translation in translations {
            let next = SystemMetricsPinOrdering.dropIndex(
                startIndex: startIndex,
                translation: translation,
                heights: heights,
                current: slot
            )
            if next != slot {
                changes += 1
            }
            slot = next
        }
        return (slot, changes)
    }

    /// A steady drag with hand tremor superimposed on every update. Deterministic,
    /// so a failure is reproducible.
    private func drag(to distance: CGFloat, frames: Int, tremor: CGFloat) -> [CGFloat] {
        var translations: [CGFloat] = []
        var seed: Double = 987_654
        for frame in 0 ..< frames {
            seed = (seed * 1_103_515_245 + 12345).truncatingRemainder(dividingBy: 2_147_483_648)
            let noise = CGFloat(seed / 2_147_483_648 - 0.5) * 2 * tremor
            translations.append(distance * CGFloat(frame) / CGFloat(frames) + noise)
        }
        return translations
    }

    private let sevenRows = [CGFloat](repeating: 40, count: 7)

    // MARK: - Reaching the ends of the list

    @Test
    func `a drag from the bottom reaches the top in one gesture`() {
        // The reported failure: seven rows, dragging the last one all the way up.
        // The centres are 240pt apart, so the drag has to clear that to land in
        // slot 0 — the row is physically dragged to the top of the list.
        let result = replay(
            drag(to: -250, frames: 300, tremor: 1),
            heights: sevenRows,
            startIndex: 6
        )
        #expect(result.slot == 0)
    }

    @Test
    func `a drag from the top reaches the bottom in one gesture`() {
        let result = replay(
            drag(to: 250, frames: 300, tremor: 1),
            heights: sevenRows,
            startIndex: 0
        )
        #expect(result.slot == 6)
    }

    @Test
    func `a single large jump still lands on the right slot`() {
        // Gesture updates can skip several rows at once; the slot must not
        // advance by only one per update.
        let slot = SystemMetricsPinOrdering.dropIndex(
            startIndex: 6, translation: -250, heights: sevenRows, current: 6
        )
        #expect(slot == 0)
    }

    @Test
    func `landing exactly on a centre does not cross it`() {
        // Documents the boundary: the crossing is strict, so travelling exactly
        // the 240pt between row 6's centre and row 0's stops one slot short.
        #expect(SystemMetricsPinOrdering.dropIndex(
            startIndex: 6, translation: -240, heights: sevenRows, current: 6
        ) == 1)
    }

    @Test
    func `the slot never leaves the list`() {
        // Overshooting past either end is normal — the finger keeps going.
        #expect(SystemMetricsPinOrdering.dropIndex(
            startIndex: 6, translation: -10000, heights: sevenRows, current: 6
        ) == 0)
        #expect(SystemMetricsPinOrdering.dropIndex(
            startIndex: 0, translation: 10000, heights: sevenRows, current: 0
        ) == 6)
    }

    // MARK: - Where the crossings sit

    @Test
    func `the slot changes when the dragged centre passes the next row's`() {
        // 40pt rows: the next row's centre is 40pt away.
        #expect(SystemMetricsPinOrdering.dropIndex(
            startIndex: 0, translation: 39, heights: sevenRows, current: 0
        ) == 0)
        #expect(SystemMetricsPinOrdering.dropIndex(
            startIndex: 0, translation: 41, heights: sevenRows, current: 0
        ) == 1)
    }

    @Test
    func `mixed row heights use their own centres`() {
        // An expanded detail panel makes row 1 much taller: its centre sits
        // 30/2 + 90/2 = 60pt below row 0's.
        let heights: [CGFloat] = [30, 90, 30]
        #expect(SystemMetricsPinOrdering.dropIndex(
            startIndex: 0, translation: 59, heights: heights, current: 0
        ) == 0)
        #expect(SystemMetricsPinOrdering.dropIndex(
            startIndex: 0, translation: 61, heights: heights, current: 0
        ) == 1)
    }

    @Test
    func `an unmeasured row leaves the slot alone`() {
        // Heights arrive from a GeometryReader, so they are zero for a frame or
        // two. Resolving against a zero-height layout would teleport the row.
        let heights: [CGFloat] = [40, 0, 40]
        #expect(SystemMetricsPinOrdering.dropIndex(
            startIndex: 0, translation: 500, heights: heights, current: 0
        ) == 0)
    }

    // MARK: - Holding steady

    @Test(arguments: [CGFloat(1), 2, 4, 8])
    func `tremor never flicks the insertion point back and forth`(tremor: CGFloat) {
        // Three rows down, then held there while the hand shakes. The slot should
        // settle and stay put: at most one change per row crossed.
        let result = replay(
            drag(to: 120, frames: 300, tremor: tremor) + [CGFloat](repeating: 120, count: 200)
                .enumerated().map { index, base in
                    base + (index % 2 == 0 ? tremor : -tremor)
                },
            heights: sevenRows,
            startIndex: 0
        )
        #expect(result.slot == 3)
        #expect(result.changes <= 3)
    }

    @Test
    func `a drag that goes nowhere changes nothing`() {
        let result = replay(
            drag(to: 0, frames: 300, tremor: 8),
            heights: sevenRows,
            startIndex: 3
        )
        #expect(result.slot == 3)
        #expect(result.changes == 0)
    }

    // MARK: - The gap the dragged row will drop into

    @Test
    func `rows the drag has passed slide up to open the gap`() {
        // Row 1 dragged down to slot 3: rows 2 and 3 move up by one row, the rest
        // stay put. Row 1 itself rides the pointer, so it reports no gap offset.
        let offsets = (0 ..< 5).map {
            SystemMetricsPinOrdering.gapOffset(index: $0, startIndex: 1, dropIndex: 3, draggedHeight: 40)
        }
        #expect(offsets == [0, 0, -40, -40, 0])
    }

    @Test
    func `rows the drag has passed slide down when moving up the list`() {
        let offsets = (0 ..< 5).map {
            SystemMetricsPinOrdering.gapOffset(index: $0, startIndex: 3, dropIndex: 1, draggedHeight: 40)
        }
        #expect(offsets == [0, 40, 40, 0, 0])
    }

    @Test
    func `nothing shifts while the drop slot is where the row started`() {
        let offsets = (0 ..< 5).map {
            SystemMetricsPinOrdering.gapOffset(index: $0, startIndex: 2, dropIndex: 2, draggedHeight: 40)
        }
        #expect(offsets.allSatisfy { $0 == 0 })
    }

    // MARK: - The coordinate space

    @Test
    func `the drag is measured in a space that does not move with the row`() {
        // Not a style preference — a correctness guard, and the one defect here
        // that no amount of pure-logic testing would have caught.
        //
        // The row is displaced by `.offset(y: translation)` using the value this
        // gesture reports. `DragGesture.translation` is `location - startLocation`
        // measured in the named space, so naming `.local` — the moving row's own
        // space — makes the measurement feed back on itself:
        //
        //     translation = pointerMovement - offset
        //                 = pointerMovement - translation
        //     translation = pointerMovement / 2
        //
        // The row then tracks at half the pointer's speed and stalls at an
        // equilibrium, which is exactly how this was reported: "can't drag more
        // than half way up, then it stutters and doesn't move past it."
        //
        // See docs/PINNED_REORDER.md.
        #expect(PinnedRowReorder.dragCoordinateSpace == .global)
        #expect(PinnedRowReorder.dragCoordinateSpace != .local)
    }
}
