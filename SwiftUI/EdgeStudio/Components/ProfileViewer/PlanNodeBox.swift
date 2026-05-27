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
///   3. **Exec time** — the operator's own `execNs` (CPU work),
///      rendered through `ProfileTimeFormatter`, with a `(N.N%)`
///      suffix showing `execNs / elapsedNs` on every box. We
///      deliberately do *not* sum `exec + recv + send`
///      here: in a pipelined execution model the parent's `recv`
///      overlaps with the child's `exec/send`, so summing them
///      double-counts the same wall clock and makes per-node
///      percentages exceed 100% across siblings. `exec` alone is the
///      non-overlapping CPU work — the same number the hotspot check
///      uses below, so the orange tint and the percent badge always
///      agree. If users want the full exec/recv/send breakdown they
///      can switch to Card view, which renders all three as separate
///      badges.
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

    private var timeLabel: String? {
        Self.timeLabel(execNs: node.stats?.execNs, totalElapsedNs: totalElapsedNs)
    }

    /// Static, pure helper so we can unit-test the percentage logic
    /// without instantiating a SwiftUI `View`. Returns the formatted
    /// "X µs  (Y.Y%)" string the Plan view box uses.
    ///
    /// - **Time shown is `execNs` only.** Summing `exec + recv + send`
    ///   would double-count wall-clock across pipeline siblings (a
    ///   parent's `recv` overlaps with its child's `exec`/`send`) and
    ///   produces percentages that exceed 100% — the bug this helper
    ///   was extracted to lock down.
    /// - **Percentage threshold is 0** here on purpose. The
    ///   `ProfileTimeFormatter.percentOfTotal` default of 5% was
    ///   chosen back when the displayed time summed all three phases
    ///   and small operators looked like noise. With `exec`-only the
    ///   small percentages are exactly what users want to see (it's
    ///   how they distinguish a real-but-tiny operator from a node
    ///   whose time is mostly spent waiting on a child).
    /// - Returns `nil` if `execNs` is missing — the box silently
    ///   omits the time line in that case.
    static func timeLabel(execNs: Int64?, totalElapsedNs: Int64) -> String? {
        guard let execNs else { return nil }
        var label = ProfileTimeFormatter.format(ns: execNs)
        if let pct = ProfileTimeFormatter.percentOfTotal(
            ns: execNs,
            totalNs: totalElapsedNs,
            threshold: 0
        ) {
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
