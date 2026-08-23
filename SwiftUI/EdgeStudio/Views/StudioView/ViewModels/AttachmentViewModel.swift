import DittoSwift
import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Owns attachment workflow state: upload progress, sheet staging values for
/// add/delete, and the inspector's attachment-viewer cache (loaded image data,
/// in-flight loads, errors). Sub-VM of `MainStudioView.ViewModel`.
///
/// Cross-VM inputs (current selectedQuery, current selectedExecuteMode) are
/// passed as method arguments rather than read from a sibling VM, keeping this
/// class self-contained for unit testing of its parsers and staging logic.
///
/// Phase 10b extraction. Direct singleton calls into `AttachmentService.shared`
/// remain for upload/fetch — protocolizing `AttachmentService` is deferred to
/// 10c (the `[String: Any]` token argument complicates a `: Sendable` protocol).
@Observable
@MainActor
final class AttachmentViewModel {
    // MARK: - Injected Dependencies

    @ObservationIgnored
    private let queryService: any QueryServiceProtocol
    @ObservationIgnored
    private let dittoManager: any DittoManagerProtocol

    // MARK: - Progress

    /// Drives the in-app progress overlay during upload / delete / fetch.
    /// `AttachmentProgress` is its own `@Observable` so reads from the
    /// progress view register directly on it.
    let attachmentProgress = AttachmentProgress()

    // MARK: - Sheet Staging State

    var attachmentTargetJson: String?
    var attachmentTargetCollection: String?
    var deleteAttachmentTargetJson: String?
    var deleteAttachmentTargetCollection: String?
    /// Attachment tokens detected when the delete sheet is staged — computed once
    /// here rather than re-parsing the document JSON during sheet body evaluation.
    var deleteAttachmentTokens: [AttachmentInfo] = []

    // MARK: - Inspector Attachment Viewer

    var detectedAttachments: [AttachmentInfo] = []
    var attachmentLoadedImages: [String: Data] = [:]
    var attachmentLoadingIds: Set<String> = []
    var attachmentErrors: [String: String] = [:]

    // MARK: - Init

    init(
        queryService: any QueryServiceProtocol = QueryService.shared,
        dittoManager: any DittoManagerProtocol = DittoManager.shared
    ) {
        self.queryService = queryService
        self.dittoManager = dittoManager
    }

    // MARK: - Parsers (pure helpers exposed for unit testability)

    func parseCollectionName(from query: String) -> String? {
        let pattern = #"(?i)\bFROM\s+(\w+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: query, range: NSRange(query.startIndex..., in: query)),
              let range = Range(match.range(at: 1), in: query) else
        {
            return nil
        }
        return String(query[range])
    }

    func parseDocumentId(from jsonString: String) -> Any? {
        guard let data = jsonString.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else
        {
            return nil
        }
        return dict["_id"]
    }

    // MARK: - Sheet Staging

    /// Stages the document JSON + parsed collection name for the add-attachment
    /// sheet. The View pulls the collection from the current `selectedQuery`
    /// and passes it through `currentQuery`; staging only writes data, never
    /// drives the sheet directly (that's View state).
    func stageAddAttachment(documentJson: String, currentQuery: String) {
        attachmentTargetJson = documentJson
        attachmentTargetCollection = parseCollectionName(from: currentQuery)
    }

    func stageDeleteAttachment(documentJson: String, currentQuery: String) {
        deleteAttachmentTargetJson = documentJson
        deleteAttachmentTargetCollection = parseCollectionName(from: currentQuery)
        deleteAttachmentTokens = AttachmentInfo.detectTokens(in: documentJson)
    }

    // MARK: - Add / Delete

    /// Uploads an attachment via `AttachmentService` (Local or HTTP) and links
    /// it to the staged document via DQL UPDATE. The current execute mode is
    /// passed in by the View so this VM stays decoupled from `QueryViewModel`.
    func executeAddAttachment(
        fileURL: URL,
        fieldName: String,
        metadata: [String: String],
        executeMode: String,
        appState: AppState
    ) async {
        guard let json = attachmentTargetJson,
              let docId = parseDocumentId(from: json) else
        {
            appState.setError(AttachmentError.noDocumentId)
            return
        }
        guard let collection = attachmentTargetCollection else {
            appState.setError(AttachmentError.collectionNotFound)
            return
        }

        let docIdString: String = if let str = docId as? String {
            str
        } else {
            "\(docId)"
        }

        attachmentProgress.isActive = true
        attachmentProgress.message = "Uploading attachment..."
        attachmentProgress.fractionCompleted = 0.0

        do {
            if executeMode == "Local" {
                try await AttachmentService.shared.createAndLink(
                    fileURL: fileURL,
                    metadata: metadata,
                    collection: collection,
                    documentId: docIdString,
                    fieldName: fieldName
                )
            } else {
                try await AttachmentService.shared.createAndLinkViaHttp(
                    fileURL: fileURL,
                    metadata: metadata,
                    collection: collection,
                    documentId: docIdString,
                    fieldName: fieldName
                )
            }
            attachmentProgress.fractionCompleted = 1.0
            attachmentProgress.message = "Attachment linked successfully"
            try? await Task.sleep(for: .seconds(1.5))
            attachmentProgress.isActive = false
        } catch {
            attachmentProgress.isActive = false
            appState.setError(error)
        }
    }

    /// Builds the null-out UPDATE that deletes an attachment field. The
    /// document id is ALWAYS passed as a bound argument (`:docId`), never
    /// interpolated into the statement: `_id` values come from synced document
    /// data, so a hostile peer could otherwise smuggle DQL through a crafted
    /// `_id`. `collection` and `fieldName` are interpolated and must therefore
    /// already be validated against the identifier regex by the caller.
    ///
    /// `nonisolated static` so the injection-safety decision is unit-testable
    /// without a live `Ditto` — same pattern as `DittoManager.createDatabaseConfig`.
    nonisolated static func deleteAttachmentStatement(
        collection: String,
        fieldName: String,
        documentId: String
    ) -> (query: String, arguments: [String: Any]) {
        (
            "UPDATE \(collection) SET \(fieldName) = null WHERE _id = :docId",
            ["docId": documentId]
        )
    }

    /// Issues `UPDATE collection SET field = null WHERE _id = :docId` for each
    /// selected attachment field. Collection / field names are validated
    /// against a strict identifier regex; the document id is bound as an
    /// argument (see `deleteAttachmentStatement`) so synced `_id` values
    /// cannot inject DQL.
    func executeDeleteAttachment(
        selectedAttachments: [AttachmentInfo],
        appState: AppState
    ) async {
        guard let json = deleteAttachmentTargetJson,
              let docId = parseDocumentId(from: json) else
        {
            appState.setError(AttachmentError.noDocumentId)
            return
        }
        guard let collection = deleteAttachmentTargetCollection else {
            appState.setError(AttachmentError.collectionNotFound)
            return
        }

        let docIdString: String = if let str = docId as? String {
            str
        } else {
            "\(docId)"
        }

        let identifierPattern = /^[a-zA-Z_][a-zA-Z0-9_]*$/

        attachmentProgress.isActive = true
        attachmentProgress.message = "Deleting attachment field(s)..."
        attachmentProgress.fractionCompleted = 0.0

        do {
            // Validate every identifier up front, so a hostile field or
            // collection name rejects the whole batch before any UPDATE runs.
            for att in selectedAttachments {
                guard att.fieldName.wholeMatch(of: identifierPattern) != nil,
                      collection.wholeMatch(of: identifierPattern) != nil else
                {
                    throw AttachmentError.invalidFieldName
                }
            }

            // Bound arguments require the live Ditto store — the QueryService
            // protocol surface only accepts a pre-baked query string.
            guard let ditto = await dittoManager.dittoSelectedApp else {
                throw AttachmentError.noDittoInstance
            }

            for (index, att) in selectedAttachments.enumerated() {
                let (query, arguments) = Self.deleteAttachmentStatement(
                    collection: collection,
                    fieldName: att.fieldName,
                    documentId: docIdString
                )
                try await ditto.store.execute(query: query, arguments: arguments)
                attachmentProgress.fractionCompleted = Double(index + 1) / Double(selectedAttachments.count)
            }
            attachmentProgress.message = "Deleted \(selectedAttachments.count) field(s) — re-run query to see changes"
            try? await Task.sleep(for: .seconds(2.5))
            attachmentProgress.isActive = false
            Log.info("Deleted \(selectedAttachments.count) attachment field(s) from document \(docIdString)")
        } catch {
            attachmentProgress.isActive = false
            appState.setError(error)
        }
    }

    // MARK: - Inspector Detection & Viewing

    /// Detects attachment tokens in the supplied JSON (or clears state when
    /// `nil`). The JSON comes from `QueryViewModel.selectedJsonForInspector`
    /// and is forwarded by `MainStudioView.ViewModel.showJsonInInspector(_:)`.
    func detectAttachments(in jsonString: String?) {
        guard let json = jsonString else {
            detectedAttachments = []
            return
        }
        detectedAttachments = AttachmentInfo.detectTokens(in: json)
        attachmentLoadedImages.removeAll()
        attachmentLoadingIds.removeAll()
        attachmentErrors.removeAll()
    }

    /// Downloads an attachment for inspector preview. Image data is cached on
    /// `attachmentLoadedImages`; non-image attachments are written to a temp
    /// file and opened via the OS share sheet / NSWorkspace.
    func fetchAttachmentForViewing(
        _ attachment: AttachmentInfo,
        json: String?,
        executeMode: String,
        appState: AppState
    ) async {
        guard let json,
              let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = dict[attachment.fieldName] as? [String: Any] else
        {
            return
        }

        attachmentLoadingIds.insert(attachment.id)
        attachmentProgress.isActive = true
        attachmentProgress.message = "Downloading attachment..."

        do {
            let fileData: Data = if executeMode == "Local" {
                try await AttachmentService.shared.fetch(token: token, id: attachment.id)
            } else {
                try await AttachmentService.shared.fetchViaHttp(attachmentId: attachment.id)
            }
            attachmentProgress.isActive = false

            if attachment.isImage {
                attachmentLoadedImages[attachment.id] = fileData
            } else {
                // Save to temp and open in OS default app
                let tempDir = FileManager.default.temporaryDirectory
                let fileName = attachment.fileName ?? "attachment"
                let tempURL = tempDir.appendingPathComponent(fileName)
                try fileData.write(to: tempURL)
                #if os(macOS)
                NSWorkspace.shared.open(tempURL)
                #else
                // UIApplication.shared.open() doesn't work with local file URLs on iOS.
                // Use UIActivityViewController as a share sheet to let the user open/save the file.
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let rootVC = windowScene.windows.first?.rootViewController
                {
                    let activityVC = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)
                    activityVC.popoverPresentationController?.sourceView = rootVC.view
                    rootVC.present(activityVC, animated: true)
                }
                #endif
            }
            attachmentLoadingIds.remove(attachment.id)
        } catch {
            attachmentProgress.isActive = false
            attachmentLoadingIds.remove(attachment.id)
            attachmentErrors[attachment.id] = error.localizedDescription
            appState.setError(error)
        }
    }
}
