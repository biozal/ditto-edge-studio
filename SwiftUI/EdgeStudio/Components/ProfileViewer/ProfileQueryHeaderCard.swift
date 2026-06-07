import SwiftUI

/// Top card showing the user's query text in a monospaced box, plus
/// a small "captured at" timestamp.
///
/// The query text is the `displayQueryText` form (PROFILE prefix
/// stripped) — users want to see what they typed, not what we sent
/// to Ditto. Selectable so copy-to-clipboard still works.
struct ProfileQueryHeaderCard: View {
    let profile: QueryProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("EXECUTION PROFILE")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("captured \(localTimestamp)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(profile.displayQueryText)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.secondary.opacity(0.08))
                )
        }
    }

    /// Local wall-clock instant of the parse. We don't use
    /// `profile.times.startISO` because that's the server-side
    /// instant — if the server clock drifts from the client's it can
    /// surprise the user. `capturedAt` is set by `QueryProfileParser`
    /// when it parsed the envelope, which is close enough to "when I
    /// ran the query" for the header.
    private static let capturedAtFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    private var localTimestamp: String {
        Self.capturedAtFormatter.string(from: profile.capturedAt)
    }
}
