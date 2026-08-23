import SwiftUI

/// Profile header, matched to the VS Code extension's profile page: a bold title on
/// the left, the dimmed `captured <ISO8601>` timestamp on the right, and the query
/// text below — syntax-highlighted, with no enclosing box.
///
/// The query text is the `displayQueryText` form (PROFILE prefix
/// stripped) — users want to see what they typed, not what we sent
/// to Ditto. Selectable so copy-to-clipboard still works.
struct ProfileQueryHeaderCard: View {
    let profile: QueryProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Execution Profile")
                    .font(.title3.weight(.bold))
                Spacer()
                Text("captured \(isoTimestamp)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(DQLSyntaxHighlighter.highlight(profile.displayQueryText))
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("ProfileQueryHeader")
    }

    /// UTC ISO-8601 with milliseconds, matching the VS Code page's
    /// `captured 2026-08-19T22:45:53.747Z`. We don't use
    /// `profile.times.startISO` because that's the server-side
    /// instant — if the server clock drifts from the client's it can
    /// surprise the user. `capturedAt` is set by `QueryProfileParser`
    /// when it parsed the envelope, which is close enough to "when I
    /// ran the query" for the header.
    private static let capturedAtFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private var isoTimestamp: String {
        Self.capturedAtFormatter.string(from: profile.capturedAt)
    }
}
