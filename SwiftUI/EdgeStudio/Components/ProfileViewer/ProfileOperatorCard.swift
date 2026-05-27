import SwiftUI

/// One operator in the execution plan, rendered as a rounded card.
///
/// Layout (matches `screens/profile-viewer.png` reference):
///   - Header row: operator name (bold, monospaced) on the left,
///     `ProfileStatsBadges` (colored pills) on the right.
///   - Optional attributes block: key/value rows for operator-specific
///     fields (`collection`, `alias`, `datasource`, `limit`,
///     `descriptor`, …). Hidden when the operator has no attributes
///     (e.g. a bare `sequence` parent).
///
/// Children are NOT drawn here — `ProfileCardListView` handles
/// recursion so this card stays a single self-contained unit.
struct ProfileOperatorCard: View {
    let node: QueryProfileOperator

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(node.name)
                    .font(.body.weight(.semibold).monospaced())
                ProfileStatsBadges(stats: node.stats)
                Spacer(minLength: 0)
            }

            if !node.attributes.isEmpty {
                attributesGrid
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.secondary.opacity(0.20), lineWidth: 0.5)
        )
    }

    /// Two-column key/value list. Keys take a fixed leading column so
    /// values align across rows; values are monospaced for readability
    /// (some attributes are JSON-encoded objects).
    private var attributesGrid: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(node.attributes, id: \.key) { attr in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(attr.key)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .frame(width: 110, alignment: .leading)
                    Text(attr.value)
                        .font(.caption.monospaced())
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.leading, 4)
    }
}
