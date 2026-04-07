import SwiftUI

struct DeleteAttachmentSheet: View {
    let documentId: String
    let collection: String
    let attachments: [AttachmentInfo]
    let onConfirm: ([AttachmentInfo]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selections: [String: Bool] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Delete Attachment Fields")
                .font(.headline)

            Group {
                LabeledContent("Collection", value: collection)
                LabeledContent("Document ID", value: documentId)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Divider()

            Text("Select fields to delete:")
                .font(.subheadline)
                .fontWeight(.semibold)

            List {
                ForEach(attachments) { attachment in
                    Toggle(isOn: binding(for: attachment.fieldName)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(attachment.fieldName)
                                .fontWeight(.semibold)
                            Text([attachment.fileName, attachment.formattedSize, attachment.mimeType]
                                .compactMap(\.self)
                                .joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .listStyle(.plain)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                Button("Delete", role: .destructive) {
                    let selected = attachments.filter { selections[$0.fieldName] == true }
                    onConfirm(selected)
                    dismiss()
                }
                .disabled(!selections.values.contains(true))
            }
        }
        .padding()
        .frame(minWidth: 380, minHeight: 300)
        .onAppear {
            for att in attachments {
                selections[att.fieldName] = false
            }
        }
    }

    private func binding(for fieldName: String) -> Binding<Bool> {
        Binding(
            get: { selections[fieldName] ?? false },
            set: { selections[fieldName] = $0 }
        )
    }
}
