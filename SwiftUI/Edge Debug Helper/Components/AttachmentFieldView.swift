//
//  AttachmentFieldView.swift
//  Edge Studio
//
//  Created by Claude Code on 10/2/25.
//

import SwiftUI
import DittoSwift
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

struct AttachmentFieldView: View {
    let fieldName: String
    let token: [String: Any]?
    let metadata: AttachmentMetadata?
    let autoFetch: Bool

    @State private var isFetching = false
    @State private var fetchProgress: Double = 0
    @State private var fetchedData: Data?
    @State private var fetchError: String?
    @State private var isDeleted = false
    @State private var isCheckingLocal = true
    @State private var isAvailableLocally = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                // Key column
                Text(fieldName)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .frame(width: 150, alignment: .leading)

                // Type column
                Text("Attachment")
                    .font(.system(.caption2, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.2))
                    .cornerRadius(4)
                    .frame(width: 80, alignment: .leading)

                // Value column - attachment content
                VStack(alignment: .leading, spacing: 8) {
                    if let metadata = metadata {
                        Text(metadata.sizeFormatted)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if let error = fetchError {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    } else if isDeleted {
                        HStack {
                            Image(systemName: "trash.fill")
                                .foregroundColor(.secondary)
                            Text("Attachment has been deleted")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else if let data = fetchedData {
                        AttachmentPreviewInline(data: data, metadata: metadata)
                    } else if isFetching {
                        VStack(spacing: 8) {
                            ProgressView(value: fetchProgress, total: 1.0)
                                .progressViewStyle(.linear)
                            Text("Fetching... \(Int(fetchProgress * 100))%")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else if isCheckingLocal {
                        HStack {
                            ProgressView()
                                .controlSize(.small)
                            Text("Checking availability...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        HStack {
                            if isAvailableLocally {
                                Image(systemName: "checkmark.circle")
                                    .foregroundColor(.green)
                                Text("Available locally")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            } else {
                                Image(systemName: "xmark.circle")
                                    .foregroundColor(.orange)
                                Text("Not available locally")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Action buttons column
                HStack(spacing: 8) {
                    if fetchedData == nil && !isFetching && !isCheckingLocal && !isDeleted && fetchError == nil {
                        Button {
                            Task {
                                await fetchAttachment()
                            }
                        } label: {
                            Image(systemName: isAvailableLocally ? "arrow.down.to.line" : "arrow.down.circle")
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.borderless)
                        .help(isAvailableLocally ? "Fetch attachment from local store" : "Fetch attachment from network")
                    }
                }
                .frame(width: 60, alignment: .trailing)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)

            Divider()
        }
        .contentShape(Rectangle())
        .task {
            await checkLocalAvailability()
        }
    }

    private func checkLocalAvailability() async {
        print("[AttachmentFieldView] Checking local availability for \(fieldName)")

        guard let token = token else {
            print("[AttachmentFieldView] No token available for \(fieldName)")
            await MainActor.run {
                isCheckingLocal = false
            }
            return
        }

        do {
            guard let ditto = await DittoManager.shared.dittoSelectedApp else {
                print("[AttachmentFieldView] No Ditto instance available")
                await MainActor.run {
                    isCheckingLocal = false
                }
                return
            }

            // Try to get the attachment fetcher and check if it's available locally
            let fetcher = try await ditto.store.fetchAttachment(token: token) { event in
                Task { @MainActor in
                    do {
                        switch event {
                        case .progress(let downloadedBytes, let totalBytes):
                            print("[AttachmentFieldView] Progress: \(downloadedBytes)/\(totalBytes)")
                            if totalBytes > 0 {
                                fetchProgress = Double(downloadedBytes) / Double(totalBytes)
                            }

                        case .completed(let attachment):
                            print("[AttachmentFieldView] Attachment available locally: \(fieldName)")
                            fetchedData = try attachment.getData()
                            isFetching = false
                            isCheckingLocal = false

                        case .deleted:
                            print("[AttachmentFieldView] Attachment deleted: \(fieldName)")
                            isDeleted = true
                            isFetching = false
                            isCheckingLocal = false
                        }
                    } catch {
                        print("[AttachmentFieldView] ERROR processing attachment: \(error)")
                        fetchError = error.localizedDescription
                        isFetching = false
                        isCheckingLocal = false
                    }
                }
            }

            // Check if fetcher exists (meaning attachment is available or can be fetched)
            await MainActor.run {
                isAvailableLocally = true
                isCheckingLocal = false
            }

            // Auto-fetch if enabled
            if autoFetch {
                print("[AttachmentFieldView] Auto-fetching attachment: \(fieldName)")
                await fetchAttachment()
            }

        } catch {
            print("[AttachmentFieldView] ERROR checking attachment: \(error)")
            await MainActor.run {
                isAvailableLocally = false
                isCheckingLocal = false
            }
        }
    }

    private func fetchAttachment() async {
        guard let token = token else {
            fetchError = "No attachment token available"
            return
        }

        print("[AttachmentFieldView] Starting fetch for \(fieldName)")
        isFetching = true
        fetchProgress = 0
        fetchError = nil

        do {
            guard let ditto = await DittoManager.shared.dittoSelectedApp else {
                throw NSError(
                    domain: "AttachmentFetch",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "No Ditto instance available"]
                )
            }

            _ = try await ditto.store.fetchAttachment(token: token) { event in
                Task { @MainActor in
                    do {
                        switch event {
                        case .progress(let downloadedBytes, let totalBytes):
                            if totalBytes > 0 {
                                fetchProgress = Double(downloadedBytes) / Double(totalBytes)
                            }

                        case .completed(let attachment):
                            fetchedData = try attachment.getData()
                            isFetching = false

                        case .deleted:
                            isDeleted = true
                            isFetching = false
                        }
                    } catch {
                        fetchError = error.localizedDescription
                        isFetching = false
                    }
                }
            }

        } catch {
            await MainActor.run {
                fetchError = error.localizedDescription
                isFetching = false
            }
        }
    }
}

struct CheckingLocalView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .progressViewStyle(.circular)

            Text("Checking local availability...")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}

struct NotFetchedView: View {
    let metadata: AttachmentMetadata?
    let isAvailableLocally: Bool
    let onFetch: () async -> Void

    var body: some View {
        VStack(spacing: 12) {
            if isAvailableLocally {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 48))
                    .foregroundColor(.green)

                Text("Available locally")
                    .font(.caption)
                    .foregroundColor(.green)
            } else {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 48))
                    .foregroundColor(.accentColor)

                Text("Not available locally")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let metadata = metadata {
                VStack(spacing: 4) {
                    if let type = metadata.type {
                        Text(type)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Text("Size: \(metadata.sizeFormatted)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Button {
                Task {
                    await onFetch()
                }
            } label: {
                Label(
                    isAvailableLocally ? "Load Attachment" : "Fetch Attachment",
                    systemImage: isAvailableLocally ? "doc.fill" : "arrow.down.circle.fill"
                )
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}

struct FetchingView: View {
    let progress: Double

    var body: some View {
        VStack(spacing: 12) {
            ProgressView(value: progress, total: 1.0)
                .progressViewStyle(.linear)

            Text("Fetching... \(Int(progress * 100))%")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
    }
}

struct ErrorView: View {
    let message: String

    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)

            Text(message)
                .font(.caption)
                .foregroundColor(.red)
        }
        .padding()
    }
}

struct DeletedView: View {
    var body: some View {
        HStack {
            Image(systemName: "trash.fill")
                .foregroundColor(.secondary)

            Text("Attachment has been deleted")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
    }
}

struct AttachmentPreviewInline: View {
    let data: Data
    let metadata: AttachmentMetadata?

    @State private var showSaveDialog = false

    private var isImage: Bool {
        guard let type = metadata?.type else {
            // Try to detect from data
            if let _ = NSImage(data: data) {
                return true
            }
            return false
        }
        return type.hasPrefix("image/")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Fetched successfully")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Button {
                    saveAttachment()
                } label: {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderless)
                .help("Save attachment")
            }

            if isImage {
                #if os(macOS)
                if let nsImage = NSImage(data: data) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 200)
                        .cornerRadius(4)
                }
                #else
                if let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 200)
                        .cornerRadius(4)
                }
                #endif
            } else {
                HStack {
                    Image(systemName: "doc.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.secondary)

                    VStack(alignment: .leading) {
                        if let type = metadata?.type {
                            Text(type)
                                .font(.caption)
                        }
                        Text("\(data.count) bytes")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    private func saveAttachment() {
        #if os(macOS)
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [contentType]
        savePanel.nameFieldStringValue = defaultFilename
        savePanel.canCreateDirectories = true
        savePanel.isExtensionHidden = false

        savePanel.begin { response in
            guard response == .OK, let url = savePanel.url else {
                print("[AttachmentPreviewInline] Save cancelled")
                return
            }

            do {
                try data.write(to: url)
                print("[AttachmentPreviewInline] Saved attachment to \(url)")
            } catch {
                print("[AttachmentPreviewInline] Failed to save attachment: \(error)")
            }
        }
        #else
        // For iOS/iPadOS, use the fileExporter
        showSaveDialog = true
        #endif
    }

    private var contentType: UTType {
        if let typeString = metadata?.type,
           let utType = UTType(mimeType: typeString) {
            return utType
        }
        return .data
    }

    private var defaultFilename: String {
        if let type = metadata?.type {
            let ext = type.split(separator: "/").last.map(String.init) ?? "bin"
            return "attachment.\(ext)"
        }
        return "attachment.bin"
    }
}

struct AttachmentPreview: View {
    let data: Data
    let metadata: AttachmentMetadata?

    @State private var showSaveDialog = false

    private var isImage: Bool {
        guard let type = metadata?.type else {
            // Try to detect from data
            if let _ = NSImage(data: data) {
                return true
            }
            return false
        }
        return type.hasPrefix("image/")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)

                Text("Attachment fetched successfully")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Button {
                    saveAttachment()
                } label: {
                    Label("Save", systemImage: "square.and.arrow.down")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
            }

            if isImage {
                #if os(macOS)
                if let nsImage = NSImage(data: data) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 300)
                        .cornerRadius(8)
                }
                #else
                if let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 300)
                        .cornerRadius(8)
                }
                #endif
            } else {
                HStack {
                    Image(systemName: "doc.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)

                    VStack(alignment: .leading) {
                        if let type = metadata?.type {
                            Text(type)
                                .font(.caption)
                        }
                        Text("\(data.count) bytes")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
            }
        }
        .padding()
    }

    private func saveAttachment() {
        #if os(macOS)
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [contentType]
        savePanel.nameFieldStringValue = defaultFilename
        savePanel.canCreateDirectories = true
        savePanel.isExtensionHidden = false

        savePanel.begin { response in
            guard response == .OK, let url = savePanel.url else {
                print("[AttachmentPreview] Save cancelled")
                return
            }

            do {
                try data.write(to: url)
                print("[AttachmentPreview] Saved attachment to \(url)")
            } catch {
                print("[AttachmentPreview] Failed to save attachment: \(error)")
            }
        }
        #else
        // For iOS/iPadOS, use the fileExporter
        showSaveDialog = true
        #endif
    }

    private var contentType: UTType {
        if let typeString = metadata?.type,
           let utType = UTType(mimeType: typeString) {
            return utType
        }
        return .data
    }

    private var defaultFilename: String {
        if let type = metadata?.type {
            let ext = type.split(separator: "/").last.map(String.init) ?? "bin"
            return "attachment.\(ext)"
        }
        return "attachment.bin"
    }
}

// Document type for saving attachments
struct AttachmentDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.data] }

    let data: Data
    let metadata: AttachmentMetadata?

    init(data: Data, metadata: AttachmentMetadata?) {
        self.data = data
        self.metadata = metadata
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
        self.metadata = nil
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

#Preview {
    VStack(spacing: 20) {
        AttachmentFieldView(
            fieldName: "profileImage",
            token: ["id": "abc123", "len": 1024],
            metadata: AttachmentMetadata(id: "abc123", len: 1024, type: "image/jpeg"),
            autoFetch: false
        )

        AttachmentFieldView(
            fieldName: "document",
            token: ["id": "def456", "len": 2048],
            metadata: AttachmentMetadata(id: "def456", len: 2048, type: "application/pdf"),
            autoFetch: false
        )
    }
    .padding()
}
