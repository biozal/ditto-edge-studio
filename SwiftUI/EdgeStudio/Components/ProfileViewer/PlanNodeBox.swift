import SwiftUI

/// Single rounded box for the Plan tree view. Distinct from
/// `ProfileOperatorCard` (used by Card mode): smaller, fixed-width,
/// and color-coded by hotspot status so an operator burning a
/// disproportionate share of the request's elapsed time pops visually.
///
/// Visual hierarchy (top-to-bottom inside the box):
///   1. **Operator name** (bold, monospaced) — `"scan"`, `"limit"`,
///      `"sequence"`, …
///   2. **Key attribute** (subtle) — best-effort distinguishing
///      attribute: `collection` for scans, `limit` for limits, etc.
///      Hidden for operators without one.
///   3. **Total time** — `exec + recv + send` rendered through
///      `ProfileTimeFormatter`, with an optional `(N.N%)` suffix
///      when the node represents ≥ 5% of the total elapsed time.
///   4. **In/out doc counts** — `"N in / M out"`, with both halves
///      hidden if the operator emits neither.
///
/// Colors:
///   - **Default**: muted green — matches the reference layout in
///     `screens/couchbase-plan.png` and signals "normal".
///   - **Hotspot**: orange when this operator's `exec` exceeds
///     `hotspotThreshold` (50%) of the request's total `elapsedNs`.
///     Same threshold that powers the percent badge — see
///     `plans/dql-profile-feature.md` "Bottleneck threshold".
struct PlanNodeBox: View {
    let node: QueryProfileOperator
    let totalElapsedNs: Int64

    /// Operator's exec time represents > 50% of total elapsed → flag
    /// as a bottleneck. Threshold lives here so the orange tint and
    /// the percent badge agree.
    static let hotspotThreshold = 0.5

    private var isHotspot: Bool {
        guard let execNs = node.stats?.execNs, totalElapsedNs > 0 else { return false }
        return Double(execNs) / Double(totalElapsedNs) >= Self.hotspotThreshold
    }

    private var fillColor: Color {
        isHotspot ? Color.orange.opacity(0.18) : Color.green.opacity(0.16)
    }

    private var borderColor: Color {
        isHotspot ? Color.orange.opacity(0.5) : Color.green.opacity(0.45)
    }

    /// Best-effort identifying attribute for the node title row.
    /// We surface the first attribute that names *what* the operator
    /// works on rather than internal config (`descriptor` /
    /// `datasource` add noise without help). Falls back to nil — the
    /// box just omits the subtitle line.
    private var keyAttribute: String? {
        let preferred = ["collection", "alias", "limit", "field", "table"]
        for key in preferred {
            if let attr = node.attributes.first(where: { $0.key == key }) {
                return attr.value
            }
        }
        return nil
    }

    /// Sum of the non-overlapping phases. Ditto's per-operator
    /// `exec`/`recv`/`send` are disjoint phases on the operator's
    /// own thread — adding them gives the wall-time the operator
    /// occupied without double-counting.
    private var totalNs: Int64? {
        guard let stats = node.stats else { return nil }
        let parts: [Int64] = [stats.execNs, stats.recvNs, stats.sendNs].compactMap(\.self)
        guard !parts.isEmpty else { return nil }
        return parts.reduce(0, +)
    }

    private var timeLabel: String? {
        guard let totalNs else { return nil }
        var label = ProfileTimeFormatter.format(ns: totalNs)
        if let pct = ProfileTimeFormatter.percentOfTotal(ns: totalNs, totalNs: totalElapsedNs) {
            label += "  (\(pct))"
        }
        return label
    }

    private var ioLabel: String? {
        let input = node.stats?.documentsIn
        let output = node.stats?.documentsOut
        switch (input, output) {
        case let (input?, output?):
            return "\(ProfileFormat.documents(input)) in / \(ProfileFormat.documents(output)) out"
        case (nil, let output?):
            return "\(ProfileFormat.documents(output)) out"
        case (let input?, nil):
            return "\(ProfileFormat.documents(input)) in"
        default:
            return nil
        }
    }

    var body: some View {
        VStack(alignment: .center, spacing: 4) {
            Text(node.name)
                .font(.subheadline.weight(.semibold).monospaced())
                .foregroundStyle(.primary)
            if let keyAttribute {
                Text(keyAttribute)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let timeLabel {
                Text(timeLabel)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.primary.opacity(0.85))
            }
            if let ioLabel {
                Text(ioLabel)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: 160)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(fillColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(borderColor, lineWidth: 1)
        )
        // Subtle elevation cue — matches the "card with depth" feel
        // of the reference Couchbase screenshot without going overboard
        // with shadow that would clash against dark mode.
        .shadow(color: Color.black.opacity(0.08), radius: 2, x: 0, y: 1)
    }
}
