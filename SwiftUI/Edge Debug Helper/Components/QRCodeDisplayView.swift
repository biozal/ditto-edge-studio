import SwiftUI

struct QRCodeDisplayView: View {
    let config: DittoConfigForDatabase
    let favorites: [FavoriteQueryItem]
    @State private var includeFavorites: Bool
    @Environment(\.dismiss) private var dismiss

    init(config: DittoConfigForDatabase, favorites: [FavoriteQueryItem]) {
        self.config = config
        self.favorites = favorites
        _includeFavorites = State(initialValue: !favorites.isEmpty)
    }

    private var qrImage: Image? {
        QRCodeGenerator.generate(from: config, favorites: includeFavorites ? favorites : [])
    }

    var body: some View {
        VStack(spacing: 24) {
            Text(config.name)
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
                VStack(spacing: 8) {
                    Text("Unable to generate QR code")
                        .foregroundColor(.secondary)
                    if includeFavorites && !favorites.isEmpty {
                        Text("Too much data to encode — try disabling favorites")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(width: 250, height: 250)
            }

            if !favorites.isEmpty {
                Toggle(
                    "Include \(favorites.count) favorite\(favorites.count == 1 ? "" : "s")",
                    isOn: $includeFavorites
                )
                .toggleStyle(.switch)
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
