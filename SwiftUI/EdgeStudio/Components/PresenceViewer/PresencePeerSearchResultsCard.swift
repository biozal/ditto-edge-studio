import SwiftUI

// MARK: - Results card

/// The list of peers matching the query, shown below the search box.
///
/// Split out from `PresencePeerSearchField` (and mirroring Android's
/// `PresencePeerSearchResults`) so the rows can be rendered from a preview without
/// a Ditto instance, a scene, or a live presence graph behind them.
struct PresencePeerSearchResultsCard: View {
    let query: String
    let matches: [PresencePeerSearchMatch]
    let onPick: (String) -> Void

    @State private var hoveredKey: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if matches.isEmpty {
                // A zero-hit query is not "no search": the graph is fully dimmed
                // behind this card, and saying so is the useful feedback.
                Text("No peers match \u{201C}\(query.trimmingCharacters(in: .whitespacesAndNewlines))\u{201D}")
                    .font(.caption)
                    .italic()
                    .foregroundStyle(.secondary)
                    .padding(8)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(matches) { match in
                            row(match)
                        }
                    }
                    .padding(4)
                }
                // `fixedSize` OUTSIDE the frame, and both are needed: a ScrollView
                // is greedy and takes every point of height it is offered, so
                // `.frame(maxHeight:)` alone left a card with three hits padded out
                // with 100+ pt of dead space. `fixedSize` proposes nil height, the
                // ScrollView answers with its content's, and the frame caps that at
                // the point the list starts scrolling instead.
                .frame(maxHeight: 224)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(width: 320)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary)
        }
        .shadow(radius: 8, y: 4)
        .accessibilityIdentifier("PresencePeerSearchResults")
    }

    @ViewBuilder
    private func row(_ match: PresencePeerSearchMatch) -> some View {
        if match.isLocal {
            // Listed so a full-opacity "Me" makes sense while the rest of the
            // graph dims — but not a button: the scene rejects focusing the local
            // peer (every line touches it in Direct mode, so focusing it would
            // exempt the whole graph from dimming).
            rowContent(match, tag: "(this device)")
                .help("The local device cannot be focused")
                .accessibilityIdentifier("PresenceSearchResult_\(match.key)")
        } else {
            Button {
                onPick(match.key)
            } label: {
                rowContent(match, tag: nil)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(
                hoveredKey == match.key ? Color.primary.opacity(0.08) : .clear,
                in: RoundedRectangle(cornerRadius: 4)
            )
            .onHover { hoveredKey = $0 ? match.key : (hoveredKey == match.key ? nil : hoveredKey) }
            .help("Focus \(match.displayName) in the mesh")
            .accessibilityIdentifier("PresenceSearchResult_\(match.key)")
        }
    }

    private func rowContent(_ match: PresencePeerSearchMatch, tag: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            HStack(spacing: 4) {
                Text(match.displayName)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let tag {
                    Text(tag)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Text(PresencePeerSearch.truncatedKey(match.key))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }
}

// MARK: - Previews

#Preview("Results — hits") {
    PresencePeerSearchResultsCard(
        query: "pi",
        matches: [
            PresencePeerSearchMatch(key: "8f2a1c9e4b7d3a6f5e0c2b8d", name: "Pixel Tablet", isLocal: false),
            PresencePeerSearchMatch(key: "c41d9e77", name: "Pixel 10a", isLocal: false),
            PresencePeerSearchMatch(key: "a0b1", name: "", isLocal: false),
            PresencePeerSearchMatch(key: "ditto-cloud-node", name: "Ditto Cloud", isLocal: false),
            PresencePeerSearchMatch(key: "0f1e2d3c4b5a69788796a5b4c3d2e1f0", name: "My Pixel Fold", isLocal: true)
        ],
        onPick: { _ in }
    )
    .padding(40)
}

#Preview("Results — no hits") {
    PresencePeerSearchResultsCard(query: "nothing-like-this", matches: [], onPick: { _ in })
        .padding(40)
}
