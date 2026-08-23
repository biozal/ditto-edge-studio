import SwiftUI

/// Subtle footer below the operator cards: profile UUID, app ID,
/// state. Mirrors the reference at `screens/profile-viewer.png`
/// where the same trailing strip appears as small grey text.
///
/// Selectable so a user copying these into a bug report doesn't need
/// to retype the GUIDs.
struct ProfileFooterStrip: View {
    let profile: QueryProfile

    var body: some View {
        HStack(spacing: 8) {
            field(label: "profile", value: profile.id)
            divider
            field(label: "db", value: profile.appId)
            divider
            field(label: "state", value: profile.state)
            Spacer(minLength: 0)
        }
        .font(.caption2.monospaced())
        .foregroundStyle(.secondary)
        .textSelection(.enabled)
    }

    private var divider: some View {
        Text("·").foregroundStyle(.tertiary)
    }

    private func field(label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text("\(label):")
                .foregroundStyle(.tertiary)
            Text(value.isEmpty ? "—" : value)
        }
    }
}
