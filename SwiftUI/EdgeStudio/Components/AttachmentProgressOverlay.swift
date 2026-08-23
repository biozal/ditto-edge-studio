import SwiftUI

struct AttachmentProgressOverlay: View {
    let isActive: Bool
    let message: String
    let fractionCompleted: Double

    var body: some View {
        if isActive {
            HStack(spacing: 12) {
                ProgressView(value: fractionCompleted)
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 200)

                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
    }
}
