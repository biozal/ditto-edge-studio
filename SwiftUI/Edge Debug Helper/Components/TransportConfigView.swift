import SwiftUI

struct TransportConfigView: View {
    var body: some View {
        VStack(spacing: 20) {
            FontAwesomeText(icon: SystemIcon.gear, size: 64, color: .secondary)

            Text("Transport Configuration")
                .font(.title2)
                .bold()

            Text("Coming Soon")
                .font(.body)
                .foregroundColor(.secondary)

            Text("This view will allow configuration of Ditto transport settings including Bluetooth, WiFi, and WebSocket options.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
