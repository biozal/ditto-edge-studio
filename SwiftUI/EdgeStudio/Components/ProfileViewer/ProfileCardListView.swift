import SwiftUI

/// Recursive nested-card rendering of an execution plan.
///
/// Each operator becomes a `ProfileOperatorCard`. Children are
/// indented and stacked below their parent — matching the visual
/// idiom of the reference at `screens/profile-viewer.png` where the
/// outer `sequence` card *contains* its `scan` and `finalProjection`
/// children. The indent step is small (12pt) so a deeply-nested
/// plan still fits inside a reasonable pane width.
struct ProfileCardListView: View {
    let root: QueryProfileOperator

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardNode(node: root)
        }
    }
}

private struct CardNode: View {
    let node: QueryProfileOperator

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ProfileOperatorCard(node: node)

            if !node.children.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(node.children) { child in
                        CardNode(node: child)
                    }
                }
                .padding(.leading, 12)
            }
        }
    }
}
