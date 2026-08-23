import SwiftUI

/// One operator in the execution plan, rendered as a rounded card —
/// matched to the VS Code extension's profile page.
///
/// Layout:
///   - Header row: operator name (bold, monospaced) followed by the
///     solid `ProfileStatsBadges` chips.
///   - Optional attributes block: key/value rows for operator-specific
///     fields (`collection`, `alias`, `datasource`, `limit`, …). Keys are
///     dimmed, values bold. Values that are JSON documents (e.g.
///     `descriptor`) render as a syntax-highlighted code block.
///
/// Children are NOT drawn here — `ProfileCardListView` handles
/// recursion so this card stays a single self-contained unit.
struct ProfileOperatorCard: View {
    let node: QueryProfileOperator

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(node.name)
                    .font(.body.weight(.bold).monospaced())
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
                .fill(Color.secondary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 0.5)
        )
    }

    /// Two-column key/value list. Keys take a fixed leading column so
    /// values align across rows; values are bold and monospaced. A value
    /// that parses as a JSON object/array renders as a highlighted code
    /// block instead of a single-line blob.
    private var attributesGrid: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(node.attributes, id: \.key) { attr in
                HStack(alignment: .top, spacing: 12) {
                    Text(attr.key)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .frame(width: 110, alignment: .leading)
                    if let json = Self.prettyPrintedJSON(attr.value) {
                        Text(JSONSyntaxHighlighter.highlight(json))
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.secondary.opacity(0.10))
                            )
                    } else {
                        Text(attr.value)
                            .font(.caption.weight(.semibold).monospaced())
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .padding(.leading, 4)
    }

    /// Pretty-prints `value` when it is a JSON object or array; nil otherwise.
    static func prettyPrintedJSON(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{") || trimmed.hasPrefix("["),
              let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(
                  withJSONObject: object,
                  options: [.prettyPrinted, .sortedKeys]
              ),
              let string = String(bytes: pretty, encoding: .utf8) else { return nil }
        return string
    }
}
