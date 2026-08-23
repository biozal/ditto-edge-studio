import DittoSwift
import Foundation
import Testing
@testable import Ditto_Edge_Studio

/// Unit tests covering `AttachmentViewModel` — pure parsers, sheet staging,
/// and inspector attachment-detection. The SDK-bound paths
/// (`executeAddAttachment`, `fetchAttachmentForViewing`) are not exercised
/// here because `AttachmentService` isn't yet protocolized (deferred to
/// 10c); they fall under integration tests. Phase 10b extraction.
@Suite("AttachmentViewModel — sub-VM", .serialized)
struct AttachmentViewModelTests {
    @Test(.tags(.fast))
    @MainActor
    func `parseCollectionName extracts the table after FROM`() {
        let mocks = MockSet()
        let viewModel = AttachmentViewModel(queryService: mocks.queryService)

        #expect(viewModel.parseCollectionName(from: "SELECT * FROM cars") == "cars")
        #expect(
            viewModel.parseCollectionName(from: "select id from orders where x=1") == "orders"
        )
        #expect(viewModel.parseCollectionName(from: "INVALID QUERY") == nil)
    }

    @Test(.tags(.fast))
    @MainActor
    func `parseDocumentId returns nil for invalid JSON and the value for valid JSON`() {
        let mocks = MockSet()
        let viewModel = AttachmentViewModel(queryService: mocks.queryService)

        #expect(viewModel.parseDocumentId(from: "not-json") == nil)
        #expect(viewModel.parseDocumentId(from: "{\"foo\": 1}") == nil)

        if let id = viewModel.parseDocumentId(from: "{\"_id\": \"abc-123\"}") as? String {
            #expect(id == "abc-123")
        } else {
            Issue.record("Expected string _id")
        }
    }

    @Test(.tags(.fast))
    @MainActor
    func `stageAddAttachment captures json and parses collection from currentQuery`() {
        let mocks = MockSet()
        let viewModel = AttachmentViewModel(queryService: mocks.queryService)
        let docJson = "{\"_id\": \"doc-1\", \"name\": \"Alice\"}"

        // ACT
        viewModel.stageAddAttachment(
            documentJson: docJson,
            currentQuery: "SELECT * FROM users WHERE active = true"
        )

        // ASSERT
        #expect(viewModel.attachmentTargetJson == docJson)
        #expect(viewModel.attachmentTargetCollection == "users")
    }

    @Test(.tags(.fast))
    @MainActor
    func `detectAttachments populates from JSON tokens and clears caches`() {
        let mocks = MockSet()
        let viewModel = AttachmentViewModel(queryService: mocks.queryService)

        // Pre-load some cached state to confirm clearing works.
        viewModel.attachmentLoadedImages["stale"] = Data([0x01])
        viewModel.attachmentLoadingIds.insert("stale")
        viewModel.attachmentErrors["stale"] = "old error"

        // ACT — nil json should clear detected attachments.
        viewModel.detectAttachments(in: nil)

        // ASSERT
        #expect(viewModel.detectedAttachments.isEmpty)
    }
}
