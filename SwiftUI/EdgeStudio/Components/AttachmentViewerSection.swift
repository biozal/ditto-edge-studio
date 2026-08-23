import SwiftUI

#if os(macOS)
import AppKit

typealias PlatformImage = NSImage
#else
import UIKit

typealias PlatformImage = UIImage
#endif

struct AttachmentViewerSection: View {
    let attachments: [AttachmentInfo]
    let loadedImages: [String: Data] // keyed by attachment id, raw image data
    let loadingIds: Set<String>
    let errorMessages: [String: String]
    let onFetchAttachment: (AttachmentInfo) -> Void

    var body: some View {
        if !attachments.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label("Attachments (\(attachments.count))", systemImage: "paperclip")
                    .font(.headline)
                    .padding(.top, 8)

                ForEach(attachments) { attachment in
                    attachmentRow(attachment)
                }
            }
        }
    }

    private func attachmentRow(_ attachment: AttachmentInfo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(attachment.fieldName)
                        .font(.subheadline.bold())
                    HStack(spacing: 8) {
                        if let name = attachment.fileName {
                            Text(name).font(.caption).foregroundStyle(.secondary)
                        }
                        Text(attachment.formattedSize).font(.caption).foregroundStyle(.secondary)
                        if let mime = attachment.mimeType {
                            Text(mime).font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                }
                Spacer()
                if loadingIds.contains(attachment.id) {
                    ProgressView().controlSize(.small)
                } else {
                    Button(attachment.isImage ? "View" : "Open") {
                        onFetchAttachment(attachment)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            // Inline image preview
            if let imageData = loadedImages[attachment.id],
               let platformImage = PlatformImage(data: imageData)
            {
                #if os(macOS)
                Image(nsImage: platformImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                #else
                Image(uiImage: platformImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                #endif
            }

            if let error = errorMessages[attachment.id] {
                Text(error).font(.caption).foregroundStyle(.red)
            }

            Divider()
        }
        .padding(.vertical, 4)
    }
}
