import SwiftUI

/// Single rounded box for the Plan tree view. Distinct from
/// `ProfileOperatorCard` (used by Card mode): smaller, fixed-width,
/// and color-coded by hotspot status so an operator burning a
/// disproportionate share of the plan's operator work pops visually.
///
/// Visual hierarchy (top-to-bottom inside the box):
///   1. **Operator name** (bold, monospaced) — `"scan"`, `"limit"`,
///      `"sequence"`, …
///   2. **Key attribute** (subtle) — best-effort distinguishing
///      attribute: `collection` for scans, `limit` for limits, etc.
///      Hidden for operators without one.
///   3. **Exec time** — the operator's own `execNs` (CPU work),
///      rendered through `ProfileTimeFormatter`, with a `(N.N%)`
///      suffix showing this node's share of the **plan's total
///      `execNs`** on every box.
///
///      Why `execNs` and why a plan-total denominator:
///        - We deliberately do *not* sum `exec + recv + send`. In a
///          pipelined plan a parent's `recv` overlaps with its child's
///          `exec`/`send`, so the sum double-counts wall-clock and
///          makes per-node percentages exceed 100% across siblings.
///        - We also deliberately do *not* divide by `elapsedNs`. The
///          request's elapsed time includes parse, plan, I/O waits,
///          and SDK overhead that the operators don't report exec for
///          — dividing by it gives correct-but-tiny percentages that
///          add up to ~10% across the visible boxes and tell the user
///          nothing about which operator dominated.
///        - `execNs / planTotalExecNs` answers the question the user
///          actually wants: "of the CPU work in this plan, what
///          fraction lived in this operator?" — and the values sum to
///          exactly 100% across the tree by construction.
///      If users want the full exec/recv/send breakdown they switch
///      to Card view, which renders all three as separate badges.
///   4. **In/out doc counts** — `"N in / M out"`, with both halves
///      hidden if the operator emits neither.
///
/// Colors:
///   - **Default**: muted green — matches the reference layout in
///     `screens/couchbase-plan.png` and signals "normal".
///   - **Hotspot**: orange when this operator's share of
///     `planTotalExecNs` exceeds `hotspotThreshold` (50%). Same
///     denominator as the percent badge so the colour and the badge
///     always tell the same story. See
///     `plans/dql-profile-feature.md` "Bottleneck threshold".
struct PlanNodeBox: View {
    let node: QueryProfileOperator
    /// Sum of `execNs` across *every* operator in the plan tree.
    /// Computed once by `ProfilePlanTreeView` and threaded down so
    /// every box uses the same denominator and the badges add to
    /// exactly 100%.
    let planTotalExecNs: Int64

    /// Operator's exec share of the plan total > 50% → flag as a
    /// bottleneck. Threshold lives here so the orange tint and the
    /// percent badge agree.
    static let hotspotThreshold = 0.5

    private var isHotspot: Bool {
        guard let execNs = node.stats?.execNs, planTotalExecNs > 0 else { return false }
        return Double(execNs) / Double(planTotalExecNs) >= Self.hotspotThreshold
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
        Self.timeLabel(execNs: node.stats?.execNs, planTotalExecNs: planTotalExecNs)
    }

    /// Static, pure helper so we can unit-test the percentage logic
    /// without instantiating a SwiftUI `View`. Returns the formatted
    /// "X µs  (Y.Y%)" string the Plan view box uses.
    ///
    /// - **Time shown is `execNs` only.** Summing `exec + recv + send`
    ///   would double-count wall-clock across pipeline siblings (a
    ///   parent's `recv` overlaps with its child's `exec`/`send`).
    /// - **Denominator is `planTotalExecNs`**, the sum of `execNs`
    ///   across every operator in the plan. That makes the badge a
    ///   *share of plan operator work* — values across the tree sum
    ///   to exactly 100%, which is the invariant
    ///   `PlanNodeBoxTests` locks down. Dividing by `elapsedNs`
    ///   instead would produce honest-but-tiny percentages that don't
    ///   sum to anything meaningful (parse/plan/I-O wait time isn't
    ///   in any operator's `exec`).
    /// - **Percentage threshold is 0** so every reporting operator
    ///   gets a badge — users compare badges across siblings to spot
    ///   the bottleneck.
    /// - Returns `nil` if `execNs` is missing — the box silently
    ///   omits the time line in that case.
    /// - Returns the formatted time without a percent suffix when
    ///   `planTotalExecNs <= 0` (defensive — a malformed envelope
    ///   shouldn't crash the view).
    static func timeLabel(execNs: Int64?, planTotalExecNs: Int64) -> String? {
        guard let execNs else { return nil }
        var label = ProfileTimeFormatter.format(ns: execNs)
        if let pct = ProfileTimeFormatter.percentOfTotal(
            ns: execNs,
            totalNs: planTotalExecNs,
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

// MARK: - Plan-total computation

extension QueryProfileOperator {
    /// Sum of `execNs` across this operator and every descendant in
    /// its subtree. Intentionally named "subtree" rather than
    /// "plan-total" because the value is only the **plan total** when
    /// called on the root operator — calling it on a non-root node
    /// silently returns a smaller total that would break the
    /// `PlanNodeBox` badge invariant (per-node shares no longer sum
    /// to 100% across the rendered tree).
    ///
    /// Callers wanting the plan total should call this on
    /// `profile.plan` exactly once and thread the result down through
    /// the View hierarchy — see `ProfileViewerView`.
    ///
    /// Operators without exec phase times contribute 0 — they appear
    /// in the tree but aren't part of the work-pie.
    var subtreeExecNs: Int64 {
        let here = stats?.execNs ?? 0
        return children.reduce(here) { acc, child in
            acc + child.subtreeExecNs
        }
    }
}
