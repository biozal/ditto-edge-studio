import SwiftUI

/// Horizontal strip of small coloured pills summarising an operator's
/// `#stats` block: `in`, `out`, `exec`, `recv`, `send`. Used in the
/// header row of each `ProfileOperatorCard`.
///
/// Color assignments match the reference screenshot at
/// `screens/profile-viewer.png` and the legend at the bottom of that
/// page — keeping the colors stable across views lets users build
/// muscle memory ("orange = slow operator").
///
/// A badge is suppressed entirely when its underlying stat is nil:
/// not every operator emits every field (a `scan` has no
/// `documentsIn`; a `limit` may have no `recv` phase time). Hiding
/// vs. showing `—` keeps the row visually quiet.
struct ProfileStatsBadges: View {
    let stats: QueryProfileStats?

    var body: some View {
        HStack(spacing: 6) {
            if let documentsIn = stats?.documentsIn {
                Badge(label: "in", value: ProfileFormat.documents(documentsIn), color: .blue)
            }
            if let documentsOut = stats?.documentsOut {
                Badge(label: "out", value: ProfileFormat.documents(documentsOut), color: .green)
            }
            if let execNs = stats?.execNs {
                Badge(label: "exec", value: ProfileTimeFormatter.format(ns: execNs), color: .red)
            }
            if let recvNs = stats?.recvNs {
                Badge(label: "recv", value: ProfileTimeFormatter.format(ns: recvNs), color: .orange)
            }
            if let sendNs = stats?.sendNs {
                Badge(label: "send", value: ProfileTimeFormatter.format(ns: sendNs), color: .purple)
            }
        }
    }
}

/// Single coloured pill. The label/value are joined visually like
/// `out: 23,539` and the whole pill takes the colour of the stat.
private struct Badge: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(color)
            Text(value)
                .font(.caption.monospacedDigit())
                .foregroundStyle(color.opacity(0.95))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(color.opacity(0.15))
        )
        .overlay(
            Capsule()
                .strokeBorder(color.opacity(0.35), lineWidth: 0.5)
        )
    }
}

/// Light helper for thousands-grouped document counts. Lives next to
/// the badges since this is the only place we render `Int` counts in
/// the profile UI; if more callers want it later, move to Utilities.
enum ProfileFormat {
    private static let documentsFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.usesGroupingSeparator = true
        return f
    }()

    static func documents(_ count: Int) -> String {
        documentsFormatter.string(from: NSNumber(value: count)) ?? "\(count)"
    }
}
