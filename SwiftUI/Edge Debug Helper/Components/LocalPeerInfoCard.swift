import SwiftUI

// RAL 9017 Traffic Black — Ditto brand color
private let dittoBlack = Color(red: 42 / 255, green: 41 / 255, blue: 42 / 255)
private let dittoBlackLight = Color(red: 65 / 255, green: 64 / 255, blue: 65 / 255)

struct LocalPeerInfoCard: View {
    let deviceName: String
    let sdkLanguage: String
    let sdkPlatform: String
    let sdkVersion: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with icon and title
            HStack {
                FontAwesomeText(icon: UIIcon.circleNodes, size: 16, color: .white.opacity(0.80))
                Text("Local Peer")
                    .font(.headline)
                    .bold()
                    .foregroundColor(.white)
            }

            Rectangle()
                .fill(Color.white.opacity(0.20))
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
                    colors: [dittoBlackLight, dittoBlack],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .shadow(color: Color.black.opacity(0.40), radius: 6, x: 0, y: 3)
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
                .foregroundColor(.white.opacity(0.60))
            Spacer()
            Text(value)
                .font(.caption)
                .foregroundColor(.white)
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
