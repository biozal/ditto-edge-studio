import SwiftUI

struct SubscriptionQRDisplayView: View {
    let subscriptions: [SubscriptionQRItem]
    @Environment(\.dismiss) private var dismiss

    private var qrImage: Image? {
        guard let payload = QRCodeGenerator.encodeSubscriptions(subscriptions),
              let data = payload.data(using: .utf8) else { return nil }
        return QRCodeGenerator.generateQRImage(from: data)
    }

    var body: some View {
        VStack(spacing: 24) {
            Text("Subscriptions (\(subscriptions.count))")
                .font(.title2)
                .fontWeight(.semibold)

            if let image = qrImage {
                image
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(minWidth: 250, minHeight: 250)
                    .cornerRadius(8)
            } else {
                Text("Unable to generate QR code")
                    .foregroundColor(.secondary)
                    .frame(width: 250, height: 250)
            }

            Text("Scan with Edge Studio on another device")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button("Done") { dismiss() }
                .buttonStyle(.bordered)
        }
        .padding(32)
    }
}
