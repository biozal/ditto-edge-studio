import SwiftUI

struct QRCodeDisplayView: View {
    let config: DittoConfigForDatabase
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            Text(config.name)
                .font(.title2)
                .fontWeight(.semibold)

            if let image = QRCodeGenerator.generate(from: config) {
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

            Button("Done") {
                dismiss()
            }
            .buttonStyle(.bordered)
        }
        .padding(32)
    }
}
