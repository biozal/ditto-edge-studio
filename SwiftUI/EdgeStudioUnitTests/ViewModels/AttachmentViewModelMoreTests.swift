import DittoSwift
import Foundation
import Testing
@testable import Ditto_Edge_Studio

/// Additional `AttachmentViewModel` coverage beyond `AttachmentViewModelTests`.
///
/// Focuses on the genuinely unit-testable surface: delete-sheet staging,
/// inspector token detection from valid JSON, and the early-return error paths
/// of `executeAddAttachment` / `executeDeleteAttachment` that fire *before* any
/// `AttachmentService` (singleton, not yet protocolized) call is reached.
///
/// The SDK-bound success paths (actual upload / fetch / DQL UPDATE) still belong
/// to integration tests — see the header note on `AttachmentViewModelTests`.
@Suite("AttachmentViewModel — staging & error paths", .serialized)
struct AttachmentViewModelMoreTests {
    // MARK: - Helpers

    /// `AttachmentError` does not conform to `Equatable`, so case identity is
    /// asserted via pattern matching on the (no-associated-value) cases used
    /// by the early-return guards under test.
    private static func isNoDocumentId(_ error: Error?) -> Bool {
        guard let attachmentError = error as? AttachmentError else { return false }
        if case .noDocumentId = attachmentError {
            return true
        }
        return false
    }

    private static func isCollectionNotFound(_ error: Error?) -> Bool {
        guard let attachmentError = error as? AttachmentError else { return false }
        if case .collectionNotFound = attachmentError {
            return true
        }
        return false
    }

    private static func isInvalidFieldName(_ error: Error?) -> Bool {
        guard let attachmentError = error as? AttachmentError else { return false }
        if case .invalidFieldName = attachmentError {
            return true
        }
        return false
    }

    private static func isNoDittoInstance(_ error: Error?) -> Bool {
        guard let attachmentError = error as? AttachmentError else { return false }
        if case .noDittoInstance = attachmentError {
            return true
        }
        return false
    }

    /// A document JSON string carrying one valid attachment token in the
    /// `photo` field plus an unrelated scalar field.
    private static let docWithToken = """
    {"_id":"doc-9","photo":{"id":"hash-abc","len":2048,"metadata":{"name":"pic.png","mimeType":"image/png"}},"title":"hi"}
    """

    // MARK: - Delete staging

    @Test(.tags(.fast))
    @MainActor
    func `stageDeleteAttachment captures json, collection, and detected tokens`() {
        // ARRANGE
        let mocks = MockSet()
        let viewModel = AttachmentViewModel(queryService: mocks.queryService)

        // ACT
        viewModel.stageDeleteAttachment(
            documentJson: Self.docWithToken,
            currentQuery: "SELECT * FROM media WHERE _id = 'doc-9'"
        )

        // ASSERT — staging writes the three delete-sheet inputs.
        #expect(viewModel.deleteAttachmentTargetJson == Self.docWithToken)
        #expect(viewModel.deleteAttachmentTargetCollection == "media")
        #expect(viewModel.deleteAttachmentTokens.count == 1)
        #expect(viewModel.deleteAttachmentTokens.first?.fieldName == "photo")
        #expect(viewModel.deleteAttachmentTokens.first?.id == "hash-abc")
    }

    @Test(.tags(.fast))
    @MainActor
    func `stageDeleteAttachment with no tokens yields an empty token list`() {
        // ARRANGE
        let mocks = MockSet()
        let viewModel = AttachmentViewModel(queryService: mocks.queryService)

        // ACT — plain document, no attachment-shaped fields.
        viewModel.stageDeleteAttachment(
            documentJson: "{\"_id\":\"d1\",\"name\":\"Bob\"}",
            currentQuery: "SELECT * FROM users"
        )

        // ASSERT
        #expect(viewModel.deleteAttachmentTargetCollection == "users")
        #expect(viewModel.deleteAttachmentTokens.isEmpty)
    }

    // MARK: - Inspector detection

    @Test(.tags(.fast))
    @MainActor
    func `detectAttachments populates detectedAttachments from a valid token`() {
        // ARRANGE
        let mocks = MockSet()
        let viewModel = AttachmentViewModel(queryService: mocks.queryService)

        // ACT
        viewModel.detectAttachments(in: Self.docWithToken)

        // ASSERT
        #expect(viewModel.detectedAttachments.count == 1)
        #expect(viewModel.detectedAttachments.first?.fieldName == "photo")
        #expect(viewModel.detectedAttachments.first?.isImage == true)
    }

    @Test(.tags(.fast))
    @MainActor
    func `detectAttachments clears prior viewer caches on a new detect`() {
        // ARRANGE — seed stale viewer caches.
        let mocks = MockSet()
        let viewModel = AttachmentViewModel(queryService: mocks.queryService)
        viewModel.attachmentLoadedImages["stale"] = Data([0x01])
        viewModel.attachmentLoadingIds.insert("stale")
        viewModel.attachmentErrors["stale"] = "old"

        // ACT — detecting against fresh JSON resets the caches.
        viewModel.detectAttachments(in: Self.docWithToken)

        // ASSERT
        #expect(viewModel.attachmentLoadedImages.isEmpty)
        #expect(viewModel.attachmentLoadingIds.isEmpty)
        #expect(viewModel.attachmentErrors.isEmpty)
    }

    // MARK: - executeAddAttachment early-return errors

    @Test(.tags(.fast))
    @MainActor
    func `executeAddAttachment without a staged document sets noDocumentId`() async {
        // ARRANGE — nothing staged → no JSON / no _id.
        let mocks = MockSet()
        let appState = AppState()
        let viewModel = AttachmentViewModel(queryService: mocks.queryService)

        // ACT
        await viewModel.executeAddAttachment(
            fileURL: URL(fileURLWithPath: "/tmp/x.png"),
            fieldName: "photo",
            metadata: [:],
            executeMode: "Local",
            appState: appState
        )

        // ASSERT — error surfaced, progress overlay never activated.
        #expect(Self.isNoDocumentId(appState.error))
        #expect(viewModel.attachmentProgress.isActive == false)
    }

    @Test(.tags(.fast))
    @MainActor
    func `executeAddAttachment with json but no collection sets collectionNotFound`() async {
        // ARRANGE — stage a document whose query has no FROM clause, so the
        // collection can't be parsed even though the _id is present.
        let mocks = MockSet()
        let appState = AppState()
        let viewModel = AttachmentViewModel(queryService: mocks.queryService)
        viewModel.stageAddAttachment(
            documentJson: "{\"_id\":\"doc-1\"}",
            currentQuery: "NOT A REAL QUERY"
        )
        #expect(viewModel.attachmentTargetCollection == nil)

        // ACT
        await viewModel.executeAddAttachment(
            fileURL: URL(fileURLWithPath: "/tmp/x.png"),
            fieldName: "photo",
            metadata: [:],
            executeMode: "Local",
            appState: appState
        )

        // ASSERT
        #expect(Self.isCollectionNotFound(appState.error))
    }

    // MARK: - executeDeleteAttachment early-return / validation errors

    @Test(.tags(.fast))
    @MainActor
    func `executeDeleteAttachment without a staged document sets noDocumentId`() async {
        // ARRANGE
        let mocks = MockSet()
        let appState = AppState()
        let viewModel = AttachmentViewModel(queryService: mocks.queryService)

        // ACT
        await viewModel.executeDeleteAttachment(
            selectedAttachments: [],
            appState: appState
        )

        // ASSERT
        #expect(Self.isNoDocumentId(appState.error))
        // No query should have been issued.
        #expect(await mocks.queryService.lastLocalQuery == nil)
    }

    @Test(.tags(.fast))
    @MainActor
    func `executeDeleteAttachment with an invalid field name sets invalidFieldName`() async {
        // ARRANGE — valid staged doc + collection, but the attachment's
        // fieldName is not a legal DQL identifier, so the injection guard
        // throws before any query runs.
        let mocks = MockSet()
        let appState = AppState()
        let viewModel = AttachmentViewModel(queryService: mocks.queryService)
        viewModel.stageDeleteAttachment(
            documentJson: "{\"_id\":\"doc-1\"}",
            currentQuery: "SELECT * FROM media"
        )
        let badAttachment = AttachmentInfo(
            id: "att-1",
            fieldName: "bad field; DROP",
            length: 10,
            metadata: [:]
        )

        // ACT
        await viewModel.executeDeleteAttachment(
            selectedAttachments: [badAttachment],
            appState: appState
        )

        // ASSERT — guard rejects the field name, surfaces the error, and
        // never forwards a DQL UPDATE to the query service.
        #expect(Self.isInvalidFieldName(appState.error))
        #expect(await mocks.queryService.lastLocalQuery == nil)
        #expect(viewModel.attachmentProgress.isActive == false)
    }

    @Test(.tags(.fast))
    @MainActor
    func `executeDeleteAttachment with valid inputs but no open database sets noDittoInstance`() async {
        // ARRANGE — valid staged doc + collection + a legal identifier field.
        // The mock DittoManager vends no live Ditto, so execution must stop
        // at the SDK boundary with noDittoInstance. The actual DQL UPDATE is
        // covered by integration tests; the statement construction itself is
        // covered by the `deleteAttachmentStatement` suite below.
        let mocks = MockSet()
        let appState = AppState()
        let viewModel = AttachmentViewModel(
            queryService: mocks.queryService,
            dittoManager: mocks.dittoManager
        )
        viewModel.stageDeleteAttachment(
            documentJson: "{\"_id\":\"doc-7\"}",
            currentQuery: "SELECT * FROM media"
        )
        let attachment = AttachmentInfo(
            id: "att-1",
            fieldName: "photo",
            length: 10,
            metadata: [:]
        )

        // ACT
        await viewModel.executeDeleteAttachment(
            selectedAttachments: [attachment],
            appState: appState
        )

        // ASSERT
        #expect(Self.isNoDittoInstance(appState.error))
        #expect(viewModel.attachmentProgress.isActive == false)
    }
}

// MARK: - deleteAttachmentStatement (DQL injection safety)

/// Pure-decision tests for the null-out UPDATE builder. The security
/// invariant: the document id is ALWAYS a bound argument (`:docId`), never
/// interpolated — `_id` values come from synced document data, so a hostile
/// peer could otherwise smuggle DQL through a crafted `_id`.
@Suite("AttachmentViewModel.deleteAttachmentStatement — bound arguments", .serialized)
struct DeleteAttachmentStatementTests {
    @Test(.tags(.fast))
    func `document id is bound as an argument, not interpolated`() {
        // ARRANGE / ACT
        let (query, arguments) = AttachmentViewModel.deleteAttachmentStatement(
            collection: "media",
            fieldName: "photo",
            documentId: "doc-7"
        )

        // ASSERT
        #expect(query == "UPDATE media SET photo = null WHERE _id = :docId")
        #expect(arguments["docId"] as? String == "doc-7")
    }

    @Test(.tags(.fast))
    func `hostile document id cannot break out of the statement`() {
        // ARRANGE — an `_id` crafted to inject a second statement via quote
        // breakout, as a malicious peer could write into synced data.
        let hostileId = "x' ; DROP TABLE media ; --"

        // ACT
        let (query, arguments) = AttachmentViewModel.deleteAttachmentStatement(
            collection: "media",
            fieldName: "photo",
            documentId: hostileId
        )

        // ASSERT — the statement text is untouched; the hostile value only
        // ever reaches the store as a bound argument.
        #expect(query == "UPDATE media SET photo = null WHERE _id = :docId")
        #expect(!query.contains("DROP"))
        #expect(arguments["docId"] as? String == hostileId)
    }

    @Test(.tags(.fast))
    func `collection and field names are interpolated`() {
        // ARRANGE / ACT — identifiers are interpolated by design; the caller
        // validates them against the strict identifier regex first.
        let (query, _) = AttachmentViewModel.deleteAttachmentStatement(
            collection: "users",
            fieldName: "avatar",
            documentId: "d1"
        )

        // ASSERT
        #expect(query == "UPDATE users SET avatar = null WHERE _id = :docId")
    }
}

// MARK: - AttachmentInfo model coverage

/// Pure-model tests for `AttachmentInfo` token detection and the derived
/// display properties consumed by the inspector / delete sheet.
@Suite("AttachmentInfo — token detection & display", .serialized)
struct AttachmentInfoModelTests {
    @Test(.tags(.model, .fast))
    func `detectTokens finds attachment-shaped fields and skips others`() {
        // ARRANGE — one valid token, one scalar, one malformed (missing len).
        let json = """
        {
          "_id": "d1",
          "doc": {"id":"h1","len":1024,"metadata":{"name":"a.pdf"}},
          "title": "hello",
          "broken": {"id":"h2","metadata":{}}
        }
        """

        // ACT
        let tokens = AttachmentInfo.detectTokens(in: json)

        // ASSERT — only the well-formed token is returned.
        #expect(tokens.count == 1)
        #expect(tokens.first?.fieldName == "doc")
        #expect(tokens.first?.length == 1024)
    }

    @Test(.tags(.model, .fast))
    func `detectTokens returns empty for invalid JSON`() {
        #expect(AttachmentInfo.detectTokens(in: "not json").isEmpty)
    }

    @Test(.tags(.model, .fast))
    func `display properties derive from metadata`() {
        // ARRANGE
        let info = AttachmentInfo(
            id: "h",
            fieldName: "photo",
            length: 2_400_000,
            metadata: ["name": "pic.jpg", "mimeType": "image/jpeg"]
        )

        // ASSERT
        #expect(info.fileName == "pic.jpg")
        #expect(info.mimeType == "image/jpeg")
        #expect(info.isImage == true)
        #expect(info.formattedSize.isEmpty == false)
    }

    @Test(.tags(.model, .fast))
    func `mimeType falls back across alternate metadata keys`() {
        // ARRANGE — uses the snake_case fallback key.
        let info = AttachmentInfo(
            id: "h",
            fieldName: "f",
            length: 1,
            metadata: ["mime_type": "application/pdf", "file_name": "doc.pdf"]
        )

        // ASSERT
        #expect(info.mimeType == "application/pdf")
        #expect(info.fileName == "doc.pdf")
        #expect(info.isImage == false)
    }
}
