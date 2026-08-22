import SwiftUI

/// Horizontal strip of stat chips summarising an operator's `#stats` block.
///
/// Colors and chip style match the VS Code extension's profile page:
/// solid filled rounded chips with white text — `in` blue, `out` green,
/// `exec` red, `send` dark grey — while `recv` is plain text, not a chip.
/// Keeping the colors stable across views lets users build muscle memory.
///
/// A chip is suppressed entirely when its underlying stat is nil:
/// not every operator emits every field (a `scan` has no
/// `documentsIn`; a `limit` may have no `recv` phase time). Hiding
/// vs. showing `—` keeps the row visually quiet.
struct ProfileStatsBadges: View {
    let stats: QueryProfileStats?

    var body: some View {
        HStack(spacing: 8) {
            if let documentsIn = stats?.documentsIn {
                StatChip(label: "in:", value: ProfileFormat.documents(documentsIn), fill: ProfileSyntaxColors.chipIn)
            }
            if let documentsOut = stats?.documentsOut {
                StatChip(label: "out:", value: ProfileFormat.documents(documentsOut), fill: ProfileSyntaxColors.chipOut)
            }
            if let execNs = stats?.execNs {
                StatChip(label: "exec", value: ProfileTimeFormatter.format(ns: execNs), fill: ProfileSyntaxColors.chipExec)
            }
            if let recvNs = stats?.recvNs {
                // Plain text, matching the VS Code page — recv is waiting time, not
                // operator work, so it doesn't get a chip.
                Text("recv \(ProfileTimeFormatter.format(ns: recvNs))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.primary)
            }
            if let sendNs = stats?.sendNs {
                StatChip(label: "send", value: ProfileTimeFormatter.format(ns: sendNs), fill: ProfileSyntaxColors.chipSend)
            }
        }
    }
}

/// Single solid chip, e.g. `out: 23,539` — dimmed white label, bold white value,
/// saturated fill. Readable in both light and dark mode by construction.
private struct StatChip: View {
    let label: String
    let value: String
    let fill: Color

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))
            Text(value)
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(fill)
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
