import SwiftUI

struct LocalPeerInfoCard: View {
    let deviceName: String
    let sdkLanguage: String
    let sdkPlatform: String
    let sdkVersion: String
    @Environment(\.colorScheme) var colorScheme

    private var gradientColors: [Color] {
        colorScheme == .dark
            ? [Color.Ditto.trafficBlack, Color.Ditto.jetBlack]
            : [Color.Ditto.trafficWhite, Color.Ditto.papyrusWhite]
    }

    private var shadowOpacity: Double {
        colorScheme == .dark ? 0.40 : 0.15
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with icon and title
            HStack {
                FontAwesomeText(icon: UIIcon.circleNodes, size: 16, color: .primary)
                Text("Local Peer")
                    .font(.headline)
                    .bold()
                    .foregroundColor(.primary)
            }

            Rectangle()
                .fill(Color.primary.opacity(0.15))
                .frame(height: 1)

            // Four labeled info rows
            InfoRow(label: "Device Name", value: deviceName)
            InfoRow(label: "SDK Language", value: sdkLanguage)
            InfoRow(label: "SDK Platform", value: sdkPlatform)
            InfoRow(label: "SDK Version", value: sdkVersion)

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(minHeight: 280, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(LinearGradient(
                    colors: gradientColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .shadow(color: Color.black.opacity(shadowOpacity), radius: 6, x: 0, y: 3)
        )
    }
}

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .foregroundColor(.primary)
        }
    }
}

#Preview {
    LocalPeerInfoCard(
        deviceName: "MacBook Pro",
        sdkLanguage: "Swift",
        sdkPlatform: "macOS",
        sdkVersion: "4.8.0"
    )
    .frame(width: 300)
    .padding()
}
