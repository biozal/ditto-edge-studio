import SwiftUI

/// Six-cell stats strip at the top of the Profile view: ELAPSED,
/// PARSE, PLAN, RESULT COUNT, FEATUREFLAGS, QUERYTYPE.
///
/// Matches the layout in `screens/profile-viewer.png`. Cells are
/// uppercase labels with the value beneath — same visual idiom as
/// Apple's macOS Activity Monitor / Network preference panes.
struct ProfileSummaryStrip: View {
    let profile: QueryProfile

    var body: some View {
        // LazyVGrid so the cells wrap to multiple rows in narrow
        // panes (iPadOS portrait, narrow window) instead of being
        // clipped or scrolling horizontally.
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 130), spacing: 8)],
            alignment: .leading,
            spacing: 8
        ) {
            cell(label: "ELAPSED", value: ProfileTimeFormatter.format(ns: profile.times.elapsedNs))
            cell(label: "PARSE", value: ProfileTimeFormatter.format(ns: profile.times.parseNs))
            cell(label: "PLAN", value: ProfileTimeFormatter.format(ns: profile.times.planNs))
            cell(label: "RESULT COUNT", value: ProfileFormat.documents(profile.resultCount))
            cell(label: "FEATUREFLAGS", value: profile.featureFlags.isEmpty ? "—" : profile.featureFlags)
            cell(label: "QUERYTYPE", value: profile.queryType.isEmpty ? "—" : profile.queryType)
        }
    }

    private func cell(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(.primary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 0.5)
        )
    }
}
