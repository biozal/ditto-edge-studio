import SwiftUI

struct LocalPeerInfoCard: View {
    let deviceName: String
    let sdkLanguage: String
    let sdkPlatform: String
    let sdkVersion: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with icon and title
            HStack {
                FontAwesomeText(icon: UIIcon.circleNodes, size: 16, color: .blue)
                Text("Local Peer")
                    .font(.headline)
                    .bold()
            }

            Divider()

            // Four labeled info rows
            InfoRow(label: "Device Name", value: deviceName)
            InfoRow(label: "SDK Language", value: sdkLanguage)
            InfoRow(label: "SDK Platform", value: sdkPlatform)
            InfoRow(label: "SDK Version", value: sdkVersion)

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(minHeight: 280, alignment: .top)
        .liquidGlassCard()
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
