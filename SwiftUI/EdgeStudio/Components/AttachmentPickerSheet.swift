import SwiftUI
import UniformTypeIdentifiers

struct AttachmentPickerSheet: View {
    let documentId: String
    let collection: String
    let executeMode: String
    let onConfirm: (URL, String, [String: String]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var fieldName = ""
    @State private var selectedFileURL: URL?
    @State private var selectedFileName = "No file selected"
    @State private var selectedFileSize: Int64 = 0
    @State private var selectedMimeType = ""
    @State private var showingFilePicker = false
    @State private var showingSizeWarning = false

    // Size limits
    private let localSoftLimit: Int64 = 10 * 1024 * 1024 // 10MB
    private let httpHardLimit: Int64 = 20 * 1024 * 1024 // 20MB

    private let allowedTypes: [UTType] = {
        var types: [UTType] = [
            .image, .png, .jpeg, .gif,
            .plainText, .utf8PlainText, .text,
            .audio, .mp3, .wav, .aiff,
            .json, .xml, .commaSeparatedText
        ]
        if #available(macOS 14.0, iOS 17.0, *) {
            types.append(.webP)
            types.append(.heic)
        }
        return types
    }()

    private var isOverHardLimit: Bool {
        selectedFileSize > httpHardLimit
    }

    private var isOverSoftLimit: Bool {
        selectedFileSize > localSoftLimit && selectedFileSize <= httpHardLimit
    }

    private var canAttach: Bool {
        selectedFileURL != nil
            && !fieldName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isOverHardLimit
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Attachment")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .center)

            LabeledContent("Collection") {
                Text(collection)
                    .foregroundColor(.secondary)
            }

            LabeledContent("Document ID") {
                Text(documentId)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Divider()

            TextField("Field name (required)", text: $fieldName)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Choose File...") {
                    showingFilePicker = true
                }

                Text(selectedFileName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundColor(selectedFileURL == nil ? .secondary : .primary)

                Spacer()

                if selectedFileSize > 0 {
                    Text(formattedFileSize(selectedFileSize))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if isOverHardLimit {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text("File exceeds the 20 MB HTTP limit and cannot be attached.")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            } else if isOverSoftLimit {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("File exceeds 10 MB. Large attachments may affect sync performance.")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }

            Divider()

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)

                Spacer()

                Button("Attach") {
                    if isOverSoftLimit {
                        showingSizeWarning = true
                    } else {
                        confirmAttachment()
                    }
                }
                .keyboardShortcut(.return)
                .disabled(!canAttach)
            }
        }
        .padding(20)
        .frame(minWidth: 400)
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: allowedTypes,
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case let .success(files):
                if let file = files.first {
                    selectFile(file)
                }
            case let .failure(error):
                Log.error("File picker error: \(error.localizedDescription)")
            }
        }
        .alert("Large File", isPresented: $showingSizeWarning) {
            Button("Cancel", role: .cancel) {}
            Button("Continue Anyway") {
                confirmAttachment()
            }
        } message: {
            Text("This file is over 10 MB. Large attachments may affect sync performance. Do you want to continue?")
        }
    }

    // MARK: - Private Methods

    private func selectFile(_ url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            Log.error("Failed to access security-scoped resource: \(url.lastPathComponent)")
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        selectedFileURL = url
        selectedFileName = url.lastPathComponent

        // Get file size
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            selectedFileSize = attributes[.size] as? Int64 ?? 0
        } catch {
            Log.error("Failed to get file attributes: \(error.localizedDescription)")
            selectedFileSize = 0
        }

        // Detect MIME type from UTType
        if let utType = UTType(filenameExtension: url.pathExtension) {
            selectedMimeType = utType.preferredMIMEType ?? "application/octet-stream"
        } else {
            selectedMimeType = "application/octet-stream"
        }
    }

    private func confirmAttachment() {
        guard let fileURL = selectedFileURL else { return }

        var metadata: [String: String] = [:]
        metadata["name"] = selectedFileName
        metadata["mimeType"] = selectedMimeType

        onConfirm(fileURL, fieldName.trimmingCharacters(in: .whitespacesAndNewlines), metadata)
        dismiss()
    }

    private func formattedFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
