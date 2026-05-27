import SwiftUI

/// Visual top-down execution-plan tree.
///
/// Renders the root operator at the top with its children stacked
/// horizontally below. Each child recurses. Thin connector lines link
/// parent → children so the hierarchy reads at a glance even before
/// the user notices the indentation.
///
/// Data flows UP through the tree at execution time (leaves are the
/// data sources; the root assembles the final result). The badge
/// legend below the tree in `ProfileViewerView` calls this out so
/// users don't have to infer it from the layout.
struct ProfilePlanTreeView: View {
    let root: QueryProfileOperator
    let planTotalExecNs: Int64

    var body: some View {
        // Both axes scrollable so deep trees and wide fan-outs both
        // remain navigable without truncating. The outer padding
        // gives the dropshadow on the boxes room to breathe.
        ScrollView([.horizontal, .vertical]) {
            PlanNode(node: root, planTotalExecNs: planTotalExecNs)
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
        }
        .frame(minHeight: 320)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.secondary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.secondary.opacity(0.15), lineWidth: 0.5)
        )
    }
}

// MARK: - Recursive node

private struct PlanNode: View {
    let node: QueryProfileOperator
    let planTotalExecNs: Int64

    /// Length of the vertical connector segment between a parent box
    /// and its children's "rail" row. Picked to leave enough vertical
    /// breathing room without making short trees look stretched.
    private let connectorLength: CGFloat = 18

    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            PlanNodeBox(node: node, planTotalExecNs: planTotalExecNs)

            if !node.children.isEmpty {
                connectorAndChildren
            }
        }
    }

    /// The "T"-shape below a parent with children: a short vertical
    /// stem dropping from the parent, then a horizontal rail spanning
    /// the children, then short vertical stems dropping onto each
    /// child. Drawn out of Rectangle/Path primitives — no
    /// PreferenceKey geometry plumbing needed for v1, which keeps
    /// the layout deterministic.
    private var connectorAndChildren: some View {
        VStack(alignment: .center, spacing: 0) {
            // Vertical drop from the parent box.
            connectorLine
                .frame(width: 1, height: connectorLength)

            // For a single child, skip the rail entirely — a straight
            // line connects parent to lone child without the T-junction
            // visual noise.
            if node.children.count == 1 {
                PlanNode(node: node.children[0], planTotalExecNs: planTotalExecNs)
            } else {
                multipleChildren
            }
        }
    }

    /// Renders the horizontal rail + a drop into each child column.
    private var multipleChildren: some View {
        HStack(alignment: .top, spacing: 24) {
            ForEach(Array(node.children.enumerated()), id: \.element.id) { index, child in
                VStack(alignment: .center, spacing: 0) {
                    // Connector drop into this child. The first and
                    // last children get a "corner" rail piece so the
                    // horizontal bar is closed; middle children get
                    // a straight cross.
                    ChildRailSegment(
                        position: railPosition(at: index, count: node.children.count)
                    )
                    .frame(height: connectorLength)

                    PlanNode(node: child, planTotalExecNs: planTotalExecNs)
                }
            }
        }
    }

    private func railPosition(at index: Int, count: Int) -> ChildRailSegment.Position {
        switch (index, count) {
        case (0, _): return .firstChild
        case let (i, n) where i == n - 1: return .lastChild
        default: return .middleChild
        }
    }

    private var connectorLine: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.45))
    }
}

// MARK: - Rail piece

/// Shape that draws the T-rail above each child. Three variants —
/// first/middle/last — let us assemble a properly-closed bar without
/// measuring child positions: each child renders the portion of the
/// horizontal rail that lives directly above it, and the parent's
/// drop terminates at the rail's center (which lines up because
/// children are equal-spaced via HStack).
private struct ChildRailSegment: View {
    enum Position { case firstChild, middleChild, lastChild }
    let position: Position

    var body: some View {
        // Two layers: the horizontal bar (drawn as one or two
        // half-rectangles per position), and the vertical drop into
        // the child. Both use the same muted secondary color so they
        // read as one continuous line.
        GeometryReader { geo in
            let mid = geo.size.width / 2
            ZStack {
                // Horizontal bar
                Path { path in
                    switch position {
                    case .firstChild:
                        path.move(to: CGPoint(x: mid, y: 0))
                        path.addLine(to: CGPoint(x: geo.size.width, y: 0))
                    case .middleChild:
                        path.move(to: CGPoint(x: 0, y: 0))
                        path.addLine(to: CGPoint(x: geo.size.width, y: 0))
                    case .lastChild:
                        path.move(to: CGPoint(x: 0, y: 0))
                        path.addLine(to: CGPoint(x: mid, y: 0))
                    }
                }
                .stroke(Color.secondary.opacity(0.45), lineWidth: 1)

                // Vertical drop into child
                Path { path in
                    path.move(to: CGPoint(x: mid, y: 0))
                    path.addLine(to: CGPoint(x: mid, y: geo.size.height))
                }
                .stroke(Color.secondary.opacity(0.45), lineWidth: 1)
            }
        }
    }
}
