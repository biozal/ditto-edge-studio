import SwiftUI

struct SubscriptionQRDisplayView: View {
    let subscriptions: [SubscriptionQRItem]
    @Environment(\.dismiss) private var dismiss

    private var qrImage: Image? {
        guard let payload = QRCodeGenerator.encodeSubscriptions(subscriptions),
              let data = payload.data(using: .utf8) else { return nil }
        return QRCodeGenerator.generateQRImage(from: data)
    }

    /// Displayed edge length of the QR code.
    ///
    /// Doubled from 250. The whole point of the code is being scanned by
    /// another device's camera, and a bigger target is easier for a low-end
    /// sensor to lock onto — the macOS window is where this is presented from,
    /// so it can afford the space. iPadOS sheets are narrower, so it takes a
    /// smaller value there rather than overflowing the form sheet.
    private var qrSide: CGFloat {
        #if os(macOS)
        500
        #else
        380
        #endif
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
                    .frame(width: qrSide, height: qrSide)
                    // White margin around the code, and the corner radius moved
                    // onto that margin rather than onto the code itself.
                    // `cornerRadius` applied directly to the image was rounding
                    // away the corners of the QR's quiet zone — the mandatory
                    // blank border a scanner uses to find the symbol. The
                    // generator only emits a 3-module zone (spec asks for 4), so
                    // there was nothing spare to clip.
                    .padding(16)
                    .background(Color.white)
                    .cornerRadius(8)
            } else {
                Text("Unable to generate QR code")
                    .foregroundStyle(.secondary)
                    .frame(width: qrSide, height: qrSide)
            }

            Text("Scan with Edge Studio on another device")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Done") { dismiss() }
                .buttonStyle(.bordered)
        }
        .padding(32)
    }
}
