import Foundation
import Testing
@testable import Ditto_Edge_Studio

/// Unit tests for `AttachmentService`'s identifier validation on the
/// add/link paths (`createAndLink`, `createAndLinkViaHttp`).
///
/// The validation runs before any Ditto or file work, so these tests need
/// no Ditto instance and no real file — an ordering failure shows up as the
/// wrong error case (`noDittoInstance` / `fileNotAccessible` instead of
/// `invalidFieldName`). The SDK-bound success paths belong to integration
/// tests (see the header note on `AttachmentViewModelTests`).
@Suite("AttachmentService Tests", .serialized, .tags(.service))
struct AttachmentServiceTests {
    // MARK: - Helpers

    private static func isInvalidFieldName(_ error: Error) -> Bool {
        guard let attachmentError = error as? AttachmentError else { return false }
        if case .invalidFieldName = attachmentError {
            return true
        }
        return false
    }

    private static func isNoDittoInstance(_ error: Error) -> Bool {
        guard let attachmentError = error as? AttachmentError else { return false }
        if case .noDittoInstance = attachmentError {
            return true
        }
        return false
    }

    /// A file URL that does not exist — validation must fire before any
    /// file access, so the path is never touched.
    private static let nonexistentFileURL = URL(fileURLWithPath: "/tmp/edge-studio-test-\(UUID().uuidString)")

    // MARK: - validateLinkIdentifiers

    @Suite("validateLinkIdentifiers", .serialized)
    struct ValidateLinkIdentifiersTests {
        @Test(.tags(.service, .fast))
        func `Accepts plain identifiers`() {
            #expect(throws: Never.self) {
                try AttachmentService.validateLinkIdentifiers(collection: "tasks", fieldName: "photo")
            }
            #expect(throws: Never.self) {
                try AttachmentService.validateLinkIdentifiers(collection: "_media2", fieldName: "_thumbnail")
            }
        }

        @Test(.tags(.service, .fast))
        func `Rejects a field name with a space`() {
            // Free text from AttachmentPickerSheet like "my field" previously
            // reached DQL and failed with an opaque error.
            #expect(throws: AttachmentError.self) {
                try AttachmentService.validateLinkIdentifiers(collection: "tasks", fieldName: "my field")
            }
        }

        @Test(.tags(.service, .fast))
        func `Rejects unsafe collection and field names`() {
            for bad in ["my field", "123start", "field-name", "drop;--", ""] {
                #expect(throws: AttachmentError.self) {
                    try AttachmentService.validateLinkIdentifiers(collection: bad, fieldName: "ok")
                }
                #expect(throws: AttachmentError.self) {
                    try AttachmentService.validateLinkIdentifiers(collection: "ok", fieldName: bad)
                }
            }
        }
    }

    // MARK: - createAndLink validation ordering

    @Suite("createAndLink validation ordering", .serialized)
    struct CreateAndLinkTests {
        @Test(.tags(.service, .fast))
        func `Invalid field name throws invalidFieldName before any work`() async {
            // ARRANGE — no Ditto instance in the test environment, and the
            // file does not exist: if validation did not run first, this
            // would throw noDittoInstance or fileNotAccessible instead.
            do {
                // ACT
                try await AttachmentService.shared.createAndLink(
                    fileURL: AttachmentServiceTests.nonexistentFileURL,
                    metadata: [:],
                    collection: "tasks",
                    documentId: "doc-1",
                    fieldName: "my field"
                )
                Issue.record("Expected invalidFieldName to be thrown")
            } catch {
                // ASSERT
                #expect(AttachmentServiceTests.isInvalidFieldName(error))
            }
        }

        @Test(.tags(.service, .fast))
        func `Invalid collection name throws invalidFieldName before any work`() async {
            do {
                try await AttachmentService.shared.createAndLink(
                    fileURL: AttachmentServiceTests.nonexistentFileURL,
                    metadata: [:],
                    collection: "bad collection!",
                    documentId: "doc-1",
                    fieldName: "photo"
                )
                Issue.record("Expected invalidFieldName to be thrown")
            } catch {
                #expect(AttachmentServiceTests.isInvalidFieldName(error))
            }
        }

        @Test(.tags(.service, .fast))
        func `Valid identifiers pass validation and reach the Ditto guard`() async {
            // With no active database, a valid request must get past
            // validation and fail at the no-Ditto guard instead.
            do {
                try await AttachmentService.shared.createAndLink(
                    fileURL: AttachmentServiceTests.nonexistentFileURL,
                    metadata: [:],
                    collection: "tasks",
                    documentId: "doc-1",
                    fieldName: "photo"
                )
                Issue.record("Expected noDittoInstance to be thrown")
            } catch {
                #expect(AttachmentServiceTests.isNoDittoInstance(error))
            }
        }
    }

    // MARK: - createAndLinkViaHttp validation ordering

    @Suite("createAndLinkViaHttp validation ordering", .serialized)
    struct CreateAndLinkViaHttpTests {
        @Test(.tags(.service, .fast))
        func `invalid field name throws first`() async {
            // No app config and no file in the test environment — any
            // ordering regression surfaces as a different error case.
            do {
                try await AttachmentService.shared.createAndLinkViaHttp(
                    fileURL: AttachmentServiceTests.nonexistentFileURL,
                    metadata: [:],
                    collection: "tasks",
                    documentId: "doc-1",
                    fieldName: "my field"
                )
                Issue.record("Expected invalidFieldName to be thrown")
            } catch {
                #expect(AttachmentServiceTests.isInvalidFieldName(error))
            }
        }

        @Test(.tags(.service, .fast))
        func `invalid collection throws first`() async {
            do {
                try await AttachmentService.shared.createAndLinkViaHttp(
                    fileURL: AttachmentServiceTests.nonexistentFileURL,
                    metadata: [:],
                    collection: "bad collection!",
                    documentId: "doc-1",
                    fieldName: "photo"
                )
                Issue.record("Expected invalidFieldName to be thrown")
            } catch {
                #expect(AttachmentServiceTests.isInvalidFieldName(error))
            }
        }
    }
}
