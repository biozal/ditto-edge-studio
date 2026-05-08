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

        @Test("Valid JSON with attachment token returns correct AttachmentInfo", .tags(.model, .fast))
        func validAttachmentToken() {
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

        @Test("JSON with no attachment tokens returns empty array", .tags(.model, .fast))
        func noAttachmentTokens() {
            // ARRANGE
            let json = """
            {"_id": "123", "name": "Alice", "age": 30}
            """

            // ACT
            let tokens = AttachmentInfo.detectTokens(in: json)

            // ASSERT
            #expect(tokens.isEmpty)
        }

        @Test("JSON with multiple attachment fields returns all of them", .tags(.model, .fast))
        func multipleAttachmentTokens() {
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

        @Test("Invalid JSON returns empty array", .tags(.model, .fast))
        func invalidJson() {
            // ARRANGE
            let json = "not valid json at all"

            // ACT
            let tokens = AttachmentInfo.detectTokens(in: json)

            // ASSERT
            #expect(tokens.isEmpty)
        }

        @Test("Nested object missing metadata key is not detected", .tags(.model, .fast))
        func missingMetadataKey() {
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

        @Test("isImage returns true for image MIME types", .tags(.model, .fast))
        func isImageTrue() {
            let info = AttachmentInfo(
                id: "hash1",
                fieldName: "photo",
                length: 1024,
                metadata: ["mimeType": "image/png"]
            )
            #expect(info.isImage == true)
        }

        @Test("isImage returns false for non-image MIME types", .tags(.model, .fast))
        func isImageFalse() {
            let info = AttachmentInfo(
                id: "hash1",
                fieldName: "doc",
                length: 512,
                metadata: ["mimeType": "text/plain"]
            )
            #expect(info.isImage == false)
        }

        @Test("isImage returns false when no MIME type present", .tags(.model, .fast))
        func isImageNoMimeType() {
            let info = AttachmentInfo(
                id: "hash1",
                fieldName: "blob",
                length: 256,
                metadata: [:]
            )
            #expect(info.isImage == false)
        }

        @Test("formattedSize returns human-readable string", .tags(.model, .fast))
        func formattedSize() {
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

        @Test("fileName extracts from metadata 'name' key", .tags(.model, .fast))
        func fileNameFromName() {
            let info = AttachmentInfo(
                id: "hash1",
                fieldName: "photo",
                length: 1024,
                metadata: ["name": "vacation.jpg"]
            )
            #expect(info.fileName == "vacation.jpg")
        }

        @Test("fileName extracts from metadata 'fileName' key", .tags(.model, .fast))
        func fileNameFromFileName() {
            let info = AttachmentInfo(
                id: "hash1",
                fieldName: "photo",
                length: 1024,
                metadata: ["fileName": "report.pdf"]
            )
            #expect(info.fileName == "report.pdf")
        }

        @Test("fileName returns nil when no matching key", .tags(.model, .fast))
        func fileNameMissing() {
            let info = AttachmentInfo(
                id: "hash1",
                fieldName: "photo",
                length: 1024,
                metadata: ["description": "some file"]
            )
            #expect(info.fileName == nil)
        }

        @Test("mimeType extracts from metadata 'mimeType' key", .tags(.model, .fast))
        func mimeTypeFromMimeType() {
            let info = AttachmentInfo(
                id: "hash1",
                fieldName: "photo",
                length: 1024,
                metadata: ["mimeType": "image/jpeg"]
            )
            #expect(info.mimeType == "image/jpeg")
        }

        @Test("mimeType extracts from metadata 'type' key", .tags(.model, .fast))
        func mimeTypeFromType() {
            let info = AttachmentInfo(
                id: "hash1",
                fieldName: "photo",
                length: 1024,
                metadata: ["type": "application/pdf"]
            )
            #expect(info.mimeType == "application/pdf")
        }

        @Test("mimeType returns nil when no matching key", .tags(.model, .fast))
        func mimeTypeMissing() {
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

        /// Helper to create a ViewModel for testing parser methods
        @MainActor
        private static func makeViewModel() -> MainStudioView.ViewModel {
            let config = DittoConfigForDatabase(
                UUID().uuidString,
                name: "Test",
                databaseId: "db-test",
                token: "",
                authUrl: "",
                websocketUrl: "",
                httpApiUrl: "",
                httpApiKey: ""
            )
            return MainStudioView.ViewModel(config)
        }

        @Test("Simple SELECT FROM query", .tags(.model, .fast))
        @MainActor
        func simpleSelectFrom() {
            let vm = Self.makeViewModel()
            let result = vm.parseCollectionName(from: "SELECT * FROM cars")
            #expect(result == "cars")
        }

        @Test("Case insensitive FROM", .tags(.model, .fast))
        @MainActor
        func caseInsensitiveFrom() {
            let vm = Self.makeViewModel()
            let result = vm.parseCollectionName(from: "select * from Cars")
            #expect(result == "Cars")
        }

        @Test("Complex query with WHERE clause", .tags(.model, .fast))
        @MainActor
        func complexQueryWithWhere() {
            let vm = Self.makeViewModel()
            let result = vm.parseCollectionName(from: "SELECT * FROM users WHERE age > 21")
            #expect(result == "users")
        }

        @Test("No FROM clause returns nil", .tags(.model, .fast))
        @MainActor
        func noFromClause() {
            let vm = Self.makeViewModel()
            let result = vm.parseCollectionName(from: "INSERT INTO cars")
            #expect(result == nil)
        }

        @Test("Multiple FROM returns first match", .tags(.model, .fast))
        @MainActor
        func multipleFromReturnsFirst() {
            let vm = Self.makeViewModel()
            let result = vm.parseCollectionName(from: "SELECT * FROM orders WHERE id IN (SELECT id FROM items)")
            #expect(result == "orders")
        }
    }

    // MARK: - parseDocumentId

    @Suite("parseDocumentId")
    struct ParseDocumentIdTests {

        @MainActor
        private static func makeViewModel() -> MainStudioView.ViewModel {
            let config = DittoConfigForDatabase(
                UUID().uuidString,
                name: "Test",
                databaseId: "db-test",
                token: "",
                authUrl: "",
                websocketUrl: "",
                httpApiUrl: "",
                httpApiKey: ""
            )
            return MainStudioView.ViewModel(config)
        }

        @Test("String ID extracts correctly", .tags(.model, .fast))
        @MainActor
        func stringId() {
            let vm = Self.makeViewModel()
            let json = """
            {"_id": "abc123", "name": "test"}
            """
            let result = vm.parseDocumentId(from: json)
            #expect(result as? String == "abc123")
        }

        @Test("Numeric ID extracts correctly", .tags(.model, .fast))
        @MainActor
        func numericId() {
            let vm = Self.makeViewModel()
            let json = """
            {"_id": 42, "name": "test"}
            """
            let result = vm.parseDocumentId(from: json)
            #expect(result as? Int == 42)
        }

        @Test("Missing _id returns nil", .tags(.model, .fast))
        @MainActor
        func missingId() {
            let vm = Self.makeViewModel()
            let json = """
            {"name": "test"}
            """
            let result = vm.parseDocumentId(from: json)
            #expect(result == nil)
        }

        @Test("Invalid JSON returns nil", .tags(.model, .fast))
        @MainActor
        func invalidJson() {
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

        @Test("Simple alphabetic field name is valid", .tags(.model, .fast))
        func simpleAlphabetic() {
            #expect(isValidFieldName("photo") == true)
        }

        @Test("Field name with underscores is valid", .tags(.model, .fast))
        func withUnderscores() {
            #expect(isValidFieldName("my_attachment") == true)
        }

        @Test("Field name with numbers is valid", .tags(.model, .fast))
        func withNumbers() {
            #expect(isValidFieldName("field123") == true)
        }

        @Test("Empty string is invalid", .tags(.model, .fast))
        func emptyString() {
            #expect(isValidFieldName("") == false)
        }

        @Test("Field name with spaces is invalid", .tags(.model, .fast))
        func withSpaces() {
            #expect(isValidFieldName("has spaces") == false)
        }

        @Test("Field name with dashes is invalid", .tags(.model, .fast))
        func withDashes() {
            #expect(isValidFieldName("has-dashes") == false)
        }

        @Test("Field name with SQL injection chars is invalid", .tags(.model, .fast))
        func withInjectionChars() {
            #expect(isValidFieldName("drop;--") == false)
        }

        @Test("Whitespace-only string is invalid", .tags(.model, .fast))
        func whitespaceOnly() {
            #expect(isValidFieldName("   ") == false)
        }
    }

    // MARK: - Delete Attachment Flow Tests

    @Suite("Delete Attachment Flow")
    struct DeleteAttachmentFlowTests {

        @Test("detectTokens finds attachment fields for delete dialog", .tags(.model, .fast))
        func detectTokensForDeleteDialog() {
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

        @Test("detectTokens returns empty for document with no attachments", .tags(.model, .fast))
        func detectTokensNoAttachments() {
            // ARRANGE
            let json = #"{"_id": "doc1", "name": "test", "age": 30}"#

            // ACT
            let tokens = AttachmentInfo.detectTokens(in: json)

            // ASSERT
            #expect(tokens.isEmpty)
        }

        @Test("Field name validation rejects unsafe identifiers", .tags(.model, .fast))
        func fieldNameValidation() {
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
