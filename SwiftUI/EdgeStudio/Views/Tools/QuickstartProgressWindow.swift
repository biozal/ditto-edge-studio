import SwiftUI

struct QuickstartProgressWindow: View {
    let service: QuickstartDownloadService
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Downloading Quickstarts")
                .font(.headline)

            ProgressView(value: service.downloadProgress)
                .progressViewStyle(.linear)

            Text(service.statusMessage)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(2)

            if service.hasError {
                Text(service.errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(3)

                HStack {
                    Spacer()
                    Button("OK") { onCancel() }
                        .keyboardShortcut(.defaultAction)
                }
            } else if service.isDownloading {
                HStack {
                    Spacer()
                    Button("Cancel") { onCancel() }
                        .keyboardShortcut(.cancelAction)
                }
            }
        }
        .padding(24)
        .frame(width: 400)
    }
}
