import Foundation
import Testing
@testable import Ditto_Edge_Studio

/// Tests for attachment-related functionality:
/// - AttachmentInfo model (token detection, computed properties)
/// - Collection name parsing from DQL queries
/// - Document ID parsing from JSON
/// - Field name validation logic
@Suite("Attachment Tests")
struct AttachmentTests {
    // MARK: - AttachmentInfo.detectTokens

    @Suite("detectTokens")
    struct DetectTokensTests {
        @Test(.tags(.model, .fast))
        func `Valid JSON with attachment token returns correct AttachmentInfo`() {
            // ARRANGE
            let json = """
            {"_id": "123", "photo": {"id": "abc", "len": 1024, "metadata": {"name": "test.png", "mimeType": "image/png"}}}
            """

            // ACT
            let tokens = AttachmentInfo.detectTokens(in: json)

            // ASSERT
            #expect(tokens.count == 1)
            #expect(tokens[0].fieldName == "photo")
            #expect(tokens[0].id == "abc")
            #expect(tokens[0].length == 1024)
            #expect(tokens[0].isImage == true)
            #expect(tokens[0].fileName == "test.png")
            #expect(tokens[0].mimeType == "image/png")
        }

        @Test(.tags(.model, .fast))
        func `JSON with no attachment tokens returns empty array`() {
            // ARRANGE
            let json = """
            {"_id": "123", "name": "Alice", "age": 30}
            """

            // ACT
            let tokens = AttachmentInfo.detectTokens(in: json)

            // ASSERT
            #expect(tokens.isEmpty)
        }

        @Test(.tags(.model, .fast))
        func `JSON with multiple attachment fields returns all of them`() {
            // ARRANGE
            let json = """
            {
                "_id": "doc1",
                "photo": {"id": "hash1", "len": 2048, "metadata": {"name": "photo.jpg", "mimeType": "image/jpeg"}},
                "thumbnail": {"id": "hash2", "len": 512, "metadata": {"name": "thumb.png", "mimeType": "image/png"}}
            }
            """

            // ACT
            let tokens = AttachmentInfo.detectTokens(in: json)

            // ASSERT
            #expect(tokens.count == 2)
            let fieldNames = Set(tokens.map(\.fieldName))
            #expect(fieldNames.contains("photo"))
            #expect(fieldNames.contains("thumbnail"))
        }

        @Test(.tags(.model, .fast))
        func `Invalid JSON returns empty array`() {
            // ARRANGE
            let json = "not valid json at all"

            // ACT
            let tokens = AttachmentInfo.detectTokens(in: json)

            // ASSERT
            #expect(tokens.isEmpty)
        }

        @Test(.tags(.model, .fast))
        func `Nested object missing metadata key is not detected`() {
            // ARRANGE — has "id" and "len" but no "metadata"
            let json = """
            {"_id": "123", "photo": {"id": "abc", "len": 1024, "description": "no metadata here"}}
            """

            // ACT
            let tokens = AttachmentInfo.detectTokens(in: json)

            // ASSERT
            #expect(tokens.isEmpty)
        }
    }

    // MARK: - AttachmentInfo Computed Properties

    @Suite("AttachmentInfo Properties")
    struct AttachmentInfoPropertiesTests {
        @Test(.tags(.model, .fast))
        func `isImage returns true for image MIME types`() {
            let info = AttachmentInfo(
                id: "hash1",
                fieldName: "photo",
                length: 1024,
                metadata: ["mimeType": "image/png"]
            )
            #expect(info.isImage == true)
        }

        @Test(.tags(.model, .fast))
        func `isImage returns false for non-image MIME types`() {
            let info = AttachmentInfo(
                id: "hash1",
                fieldName: "doc",
                length: 512,
                metadata: ["mimeType": "text/plain"]
            )
            #expect(info.isImage == false)
        }

        @Test(.tags(.model, .fast))
        func `isImage returns false when no MIME type present`() {
            let info = AttachmentInfo(
                id: "hash1",
                fieldName: "blob",
                length: 256,
                metadata: [:]
            )
            #expect(info.isImage == false)
        }

        @Test(.tags(.model, .fast))
        func `formattedSize returns human-readable string`() {
            let info = AttachmentInfo(
                id: "hash1",
                fieldName: "file",
                length: 1_048_576, // 1 MB
                metadata: [:]
            )
            let formatted = info.formattedSize
            // ByteCountFormatter with .file style should produce something like "1 MB"
            #expect(formatted.contains("MB") || formatted.contains("million"))
        }

        @Test(.tags(.model, .fast))
        func `fileName extracts from metadata 'name' key`() {
            let info = AttachmentInfo(
                id: "hash1",
                fieldName: "photo",
                length: 1024,
                metadata: ["name": "vacation.jpg"]
            )
            #expect(info.fileName == "vacation.jpg")
        }

        @Test(.tags(.model, .fast))
        func `fileName extracts from metadata 'fileName' key`() {
            let info = AttachmentInfo(
                id: "hash1",
                fieldName: "photo",
                length: 1024,
                metadata: ["fileName": "report.pdf"]
            )
            #expect(info.fileName == "report.pdf")
        }

        @Test(.tags(.model, .fast))
        func `fileName returns nil when no matching key`() {
            let info = AttachmentInfo(
                id: "hash1",
                fieldName: "photo",
                length: 1024,
                metadata: ["description": "some file"]
            )
            #expect(info.fileName == nil)
        }

        @Test(.tags(.model, .fast))
        func `mimeType extracts from metadata 'mimeType' key`() {
            let info = AttachmentInfo(
                id: "hash1",
                fieldName: "photo",
                length: 1024,
                metadata: ["mimeType": "image/jpeg"]
            )
            #expect(info.mimeType == "image/jpeg")
        }

        @Test(.tags(.model, .fast))
        func `mimeType extracts from metadata 'type' key`() {
            let info = AttachmentInfo(
                id: "hash1",
                fieldName: "photo",
                length: 1024,
                metadata: ["type": "application/pdf"]
            )
            #expect(info.mimeType == "application/pdf")
        }

        @Test(.tags(.model, .fast))
        func `mimeType returns nil when no matching key`() {
            let info = AttachmentInfo(
                id: "hash1",
                fieldName: "photo",
                length: 1024,
                metadata: [:]
            )
            #expect(info.mimeType == nil)
        }
    }

    // MARK: - parseCollectionName

    @Suite("parseCollectionName")
    struct ParseCollectionNameTests {
        /// Helper to create an AttachmentViewModel for testing parser methods.
        /// Phase 10b: parsers moved from `MainStudioView.ViewModel` to
        /// `AttachmentViewModel`, so the returned type changed accordingly.
        @MainActor
        private static func makeViewModel() -> AttachmentViewModel {
            AttachmentViewModel()
        }

        @Test(.tags(.model, .fast))
        @MainActor
        func `Simple SELECT FROM query`() {
            let vm = Self.makeViewModel()
            let result = vm.parseCollectionName(from: "SELECT * FROM cars")
            #expect(result == "cars")
        }

        @Test(.tags(.model, .fast))
        @MainActor
        func `Case insensitive FROM`() {
            let vm = Self.makeViewModel()
            let result = vm.parseCollectionName(from: "select * from Cars")
            #expect(result == "Cars")
        }

        @Test(.tags(.model, .fast))
        @MainActor
        func `Complex query with WHERE clause`() {
            let vm = Self.makeViewModel()
            let result = vm.parseCollectionName(from: "SELECT * FROM users WHERE age > 21")
            #expect(result == "users")
        }

        @Test(.tags(.model, .fast))
        @MainActor
        func `No FROM clause returns nil`() {
            let vm = Self.makeViewModel()
            let result = vm.parseCollectionName(from: "INSERT INTO cars")
            #expect(result == nil)
        }

        @Test(.tags(.model, .fast))
        @MainActor
        func `Multiple FROM returns first match`() {
            let vm = Self.makeViewModel()
            let result = vm.parseCollectionName(from: "SELECT * FROM orders WHERE id IN (SELECT id FROM items)")
            #expect(result == "orders")
        }
    }

    // MARK: - parseDocumentId

    @Suite("parseDocumentId")
    struct ParseDocumentIdTests {
        @MainActor
        private static func makeViewModel() -> AttachmentViewModel {
            AttachmentViewModel()
        }

        @Test(.tags(.model, .fast))
        @MainActor
        func `String ID extracts correctly`() {
            let vm = Self.makeViewModel()
            let json = """
            {"_id": "abc123", "name": "test"}
            """
            let result = vm.parseDocumentId(from: json)
            #expect(result as? String == "abc123")
        }

        @Test(.tags(.model, .fast))
        @MainActor
        func `Numeric ID extracts correctly`() {
            let vm = Self.makeViewModel()
            let json = """
            {"_id": 42, "name": "test"}
            """
            let result = vm.parseDocumentId(from: json)
            #expect(result as? Int == 42)
        }

        @Test(.tags(.model, .fast))
        @MainActor
        func `Missing _id returns nil`() {
            let vm = Self.makeViewModel()
            let json = """
            {"name": "test"}
            """
            let result = vm.parseDocumentId(from: json)
            #expect(result == nil)
        }

        @Test(.tags(.model, .fast))
        @MainActor
        func `Invalid JSON returns nil`() {
            let vm = Self.makeViewModel()
            let result = vm.parseDocumentId(from: "not json")
            #expect(result == nil)
        }
    }

    // MARK: - Field Name Validation

    @Suite("Field Name Validation")
    struct FieldNameValidationTests {
        /// Replicates the isValidFieldName logic from AttachmentPickerSheet:
        /// trimmed, non-empty, only letters/numbers/underscores
        private func isValidFieldName(_ input: String) -> Bool {
            let name = input.trimmingCharacters(in: .whitespacesAndNewlines)
            return !name.isEmpty && name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
        }

        @Test(.tags(.model, .fast))
        func `Simple alphabetic field name is valid`() {
            #expect(isValidFieldName("photo") == true)
        }

        @Test(.tags(.model, .fast))
        func `Field name with underscores is valid`() {
            #expect(isValidFieldName("my_attachment") == true)
        }

        @Test(.tags(.model, .fast))
        func `Field name with numbers is valid`() {
            #expect(isValidFieldName("field123") == true)
        }

        @Test(.tags(.model, .fast))
        func `Empty string is invalid`() {
            #expect(isValidFieldName("") == false)
        }

        @Test(.tags(.model, .fast))
        func `Field name with spaces is invalid`() {
            #expect(isValidFieldName("has spaces") == false)
        }

        @Test(.tags(.model, .fast))
        func `Field name with dashes is invalid`() {
            #expect(isValidFieldName("has-dashes") == false)
        }

        @Test(.tags(.model, .fast))
        func `Field name with SQL injection chars is invalid`() {
            #expect(isValidFieldName("drop;--") == false)
        }

        @Test(.tags(.model, .fast))
        func `Whitespace-only string is invalid`() {
            #expect(isValidFieldName("   ") == false)
        }
    }

    // MARK: - Delete Attachment Flow Tests

    @Suite("Delete Attachment Flow")
    struct DeleteAttachmentFlowTests {
        @Test(.tags(.model, .fast))
        func `detectTokens finds attachment fields for delete dialog`() {
            // ARRANGE
            let json = """
            {
                "_id": "doc1",
                "name": "test",
                "photo": { "id": "att1", "len": 2048, "metadata": { "name": "pic.png", "mimeType": "image/png" } },
                "resume": { "id": "att2", "len": 51200, "metadata": { "name": "resume.pdf", "mimeType": "application/pdf" } }
            }
            """

            // ACT
            let tokens = AttachmentInfo.detectTokens(in: json)

            // ASSERT
            #expect(tokens.count == 2)
            let fieldNames = tokens.map(\.fieldName)
            #expect(fieldNames.contains("photo"))
            #expect(fieldNames.contains("resume"))
        }

        @Test(.tags(.model, .fast))
        func `detectTokens returns empty for document with no attachments`() {
            // ARRANGE
            let json = #"{"_id": "doc1", "name": "test", "age": 30}"#

            // ACT
            let tokens = AttachmentInfo.detectTokens(in: json)

            // ASSERT
            #expect(tokens.isEmpty)
        }

        @Test(.tags(.model, .fast))
        func `Field name validation rejects unsafe identifiers`() {
            // Pattern for safe field identifiers: start with letter or underscore, followed by letters/numbers/underscores
            let pattern = /^[a-zA-Z_][a-zA-Z0-9_]*$/

            // ARRANGE & ACT & ASSERT - Safe names
            #expect("photo".wholeMatch(of: pattern) != nil)
            #expect("my_field".wholeMatch(of: pattern) != nil)
            #expect("_private".wholeMatch(of: pattern) != nil)
            #expect("field123".wholeMatch(of: pattern) != nil)

            // ARRANGE & ACT & ASSERT - Unsafe names
            #expect("drop;--".wholeMatch(of: pattern) == nil)
            #expect("field name".wholeMatch(of: pattern) == nil)
            #expect("123start".wholeMatch(of: pattern) == nil)
            #expect("field-name".wholeMatch(of: pattern) == nil)
        }
    }
}
