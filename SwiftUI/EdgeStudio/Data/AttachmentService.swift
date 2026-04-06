import DittoSwift
import Foundation

// MARK: - AttachmentError

enum AttachmentError: LocalizedError {
    case noDittoInstance
    case noDocumentId
    case collectionNotFound
    case fileTooLarge(size: Int64, limit: Int64)
    case fileNotAccessible
    case fetchFailed(String)
    case httpUploadFailed(String)
    case httpDownloadFailed(String)

    var errorDescription: String? {
        switch self {
        case .noDittoInstance:
            return "No Ditto instance is currently active. Please connect to a database first."
        case .noDocumentId:
            return "A document ID is required to link an attachment."
        case .collectionNotFound:
            return "The specified collection could not be found."
        case let .fileTooLarge(size, limit):
            let sizeStr = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
            let limitStr = ByteCountFormatter.string(fromByteCount: limit, countStyle: .file)
            return "File size (\(sizeStr)) exceeds the maximum allowed size (\(limitStr))."
        case .fileNotAccessible:
            return "Unable to access the selected file. Please try selecting it again."
        case let .fetchFailed(message):
            return "Attachment fetch failed: \(message)"
        case let .httpUploadFailed(message):
            return "HTTP attachment upload failed: \(message)"
        case let .httpDownloadFailed(message):
            return "HTTP attachment download failed: \(message)"
        }
    }
}

// MARK: - AttachmentProgress

@Observable
@MainActor
final class AttachmentProgress {
    var isActive = false
    var message = ""
    var fractionCompleted = 0.0
}

// MARK: - AttachmentService

actor AttachmentService {
    static let shared = AttachmentService()

    private let dittoManager = DittoManager.shared

    /// Maximum file size for local (peer-to-peer) attachment creation: 10 MB
    static let localSizeLimit: Int64 = 10 * 1024 * 1024

    /// Maximum file size for HTTP API attachment upload: 20 MB
    static let httpSizeLimit: Int64 = 20 * 1024 * 1024

    /// Active attachment fetchers keyed by a caller-provided identifier.
    /// Retaining the fetcher is required to keep the download alive.
    private var activeFetchers: [String: DittoAttachmentFetcher] = [:]

    private init() {}

    // MARK: - Create & Link

    /// Creates a new Ditto attachment from a local file and links it to a document field via DQL UPDATE.
    ///
    /// - Parameters:
    ///   - fileURL: Security-scoped URL to the source file.
    ///   - metadata: Key-value metadata stored alongside the attachment (e.g. name, mimeType).
    ///   - collection: The target collection name.
    ///   - documentId: The `_id` of the document to attach to.
    ///   - fieldName: The document field that will hold the attachment token.
    ///
    /// - Throws: `AttachmentError` on failure.
    func createAndLink(
        fileURL: URL,
        metadata: [String: String],
        collection: String,
        documentId: String,
        fieldName: String
    ) async throws {
        guard let ditto = await dittoManager.dittoSelectedApp else {
            throw AttachmentError.noDittoInstance
        }

        guard !documentId.isEmpty else {
            throw AttachmentError.noDocumentId
        }

        // Access security-scoped resource
        guard fileURL.startAccessingSecurityScopedResource() else {
            throw AttachmentError.fileNotAccessible
        }
        defer { fileURL.stopAccessingSecurityScopedResource() }

        // Validate file size
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let fileSize = (attributes[.size] as? Int64) ?? 0
        if fileSize > Self.localSizeLimit {
            throw AttachmentError.fileTooLarge(size: fileSize, limit: Self.localSizeLimit)
        }

        // Create the attachment in the Ditto store
        let attachment = try await ditto.store.newAttachment(
            path: fileURL.path,
            metadata: metadata
        )

        // Link the attachment to the document using DQL UPDATE with ATTACHMENT type hint
        let query = "UPDATE \(collection) (\(fieldName) ATTACHMENT) SET \(fieldName) = :att WHERE _id = :docId"
        let arguments: [String: Any] = ["att": attachment, "docId": documentId]
        try await ditto.store.execute(query: query, arguments: arguments)

        Log.info("[Attachment] Created and linked attachment to \(collection)/\(documentId).\(fieldName)")
    }

    // MARK: - Fetch

    /// Fetches an attachment by its token, returning the file data once the download completes.
    ///
    /// The attachment token should be obtained from a query result item's value dictionary,
    /// where the field was stored as an ATTACHMENT type.
    ///
    /// - Parameters:
    ///   - token: The attachment token dictionary obtained from a query result item's value dictionary.
    ///            Typically extracted as: `result.items.first?.value["fieldName"] as? [String: Any]`
    ///   - id: A unique identifier for this fetch operation (used for cancellation).
    ///
    /// - Returns: The raw `Data` of the fetched attachment.
    /// - Throws: `AttachmentError.fetchFailed` if the download fails.
    func fetch(token: [String: Any], id: String = UUID().uuidString) async throws -> Data {
        guard let ditto = await dittoManager.dittoSelectedApp else {
            throw AttachmentError.noDittoInstance
        }

        return try await withCheckedThrowingContinuation { continuation in
            do {
                let fetcher = try ditto.store.fetchAttachment(token: token) { [weak self] event in
                    switch event {
                    case let .completed(attachment):
                        // Clean up the fetcher reference
                        Task { await self?.removeFetcher(id: id) }
                        // Read the attachment data
                        do {
                            let data = try attachment.data()
                            continuation.resume(returning: data)
                        } catch {
                            continuation.resume(
                                throwing: AttachmentError.fetchFailed(
                                    "Failed to read attachment data: \(error.localizedDescription)"
                                )
                            )
                        }

                    case .progress:
                        // Progress updates are informational; the continuation resolves on completion
                        break

                    case .deleted:
                        Task { await self?.removeFetcher(id: id) }
                        continuation.resume(
                            throwing: AttachmentError.fetchFailed(
                                "Attachment was deleted before fetch completed."
                            )
                        )

                    @unknown default:
                        break
                    }
                }

                // Retain the fetcher so the download stays alive
                self.activeFetchers[id] = fetcher
            } catch {
                continuation.resume(
                    throwing: AttachmentError.fetchFailed(
                        "Failed to start attachment fetch: \(error.localizedDescription)"
                    )
                )
            }
        }
    }

    // MARK: - HTTP Create & Link

    /// Uploads a file via the HTTP API and links it to a document field.
    ///
    /// Step 1: Multipart POST to `/api/v4/attachments/upload`
    /// Step 2: DQL UPDATE via `/api/v5/store/execute` to link the attachment token.
    ///
    /// - Parameters:
    ///   - fileURL: Security-scoped URL to the source file.
    ///   - metadata: Key-value metadata stored alongside the attachment.
    ///   - collection: The target collection name.
    ///   - documentId: The `_id` of the document to attach to (passed as Any for DQL args).
    ///   - fieldName: The document field that will hold the attachment token.
    func createAndLinkViaHttp(
        fileURL: URL,
        metadata: [String: String],
        collection: String,
        documentId: String,
        fieldName: String
    ) async throws {
        guard let appConfig = await dittoManager.dittoSelectedAppConfig else {
            throw AttachmentError.noDittoInstance
        }

        guard fileURL.startAccessingSecurityScopedResource() else {
            throw AttachmentError.fileNotAccessible
        }
        defer { fileURL.stopAccessingSecurityScopedResource() }

        // Validate file size against HTTP limit
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let fileSize = (attributes[.size] as? Int64) ?? 0
        if fileSize > Self.httpSizeLimit {
            throw AttachmentError.fileTooLarge(size: fileSize, limit: Self.httpSizeLimit)
        }

        // Step 1: Upload via multipart
        let uploadResult = try await httpUpload(fileURL: fileURL, appConfig: appConfig)

        // Step 2: Link via DQL UPDATE over HTTP
        guard let attachmentId = uploadResult["id"] as? String,
              let attachmentLen = uploadResult["len"] as? Int else
        {
            throw AttachmentError.httpUploadFailed("Invalid upload response — missing id or len")
        }

        let updateQuery = "UPDATE \(collection) (\(fieldName) ATTACHMENT) SET \(fieldName) = :att WHERE _id = :docId"
        let attToken: [String: Any] = ["id": attachmentId, "len": attachmentLen, "metadata": metadata]
        let requestBody: [String: Any] = [
            "statement": updateQuery,
            "args": ["att": attToken, "docId": documentId]
        ]

        let urlString = "https://\(appConfig.httpApiUrl)/api/v5/store/execute"
        guard let url = URL(string: urlString) else {
            throw AttachmentError.httpUploadFailed("Invalid URL: \(urlString)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(appConfig.httpApiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let session: URLSession = if appConfig.allowUntrustedCerts {
            await dittoManager.getCachedUntrustedSession()
        } else {
            URLSession.shared
        }
        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200 ... 299).contains(httpResponse.statusCode) else
        {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw AttachmentError.httpUploadFailed("Server returned HTTP \(statusCode)")
        }

        Log.info("[Attachment] HTTP: Created and linked attachment to \(collection)/\(documentId).\(fieldName)")
    }

    // MARK: - HTTP Upload (private)

    private func httpUpload(fileURL: URL, appConfig: DittoConfigForDatabase) async throws -> [String: Any] {
        let urlString = "https://\(appConfig.httpApiUrl)/api/v4/attachments/upload"
        guard let url = URL(string: urlString) else {
            throw AttachmentError.httpUploadFailed("Invalid upload URL: \(urlString)")
        }

        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(appConfig.httpApiKey)", forHTTPHeaderField: "Authorization")

        let fileData = try Data(contentsOf: fileURL)
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append(
            "Content-Disposition: form-data; name=\"file\"; filename=\"\(fileURL.lastPathComponent)\"\r\n"
                .data(using: .utf8)!
        )
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let session: URLSession = if appConfig.allowUntrustedCerts {
            await dittoManager.getCachedUntrustedSession()
        } else {
            URLSession.shared
        }
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200 ... 299).contains(httpResponse.statusCode) else
        {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AttachmentError.httpUploadFailed("Upload returned HTTP \(statusCode): \(errorBody)")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AttachmentError.httpUploadFailed("Invalid upload response format")
        }

        return json
    }

    // MARK: - HTTP Fetch

    /// Downloads an attachment by its ID via the HTTP API.
    ///
    /// - Parameter attachmentId: The attachment identifier returned by the upload endpoint.
    /// - Returns: The raw file data.
    func fetchViaHttp(attachmentId: String) async throws -> Data {
        guard let appConfig = await dittoManager.dittoSelectedAppConfig else {
            throw AttachmentError.noDittoInstance
        }

        let urlString = "https://\(appConfig.httpApiUrl)/api/v4/attachments/\(attachmentId)"
        guard let url = URL(string: urlString) else {
            throw AttachmentError.httpDownloadFailed("Invalid download URL: \(urlString)")
        }

        var request = URLRequest(url: url)
        request.addValue("Bearer \(appConfig.httpApiKey)", forHTTPHeaderField: "Authorization")

        let session: URLSession = if appConfig.allowUntrustedCerts {
            await dittoManager.getCachedUntrustedSession()
        } else {
            URLSession.shared
        }
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200 ... 299).contains(httpResponse.statusCode) else
        {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw AttachmentError.httpDownloadFailed("Download returned HTTP \(statusCode)")
        }

        return data
    }

    // MARK: - Cancellation

    /// Cancels a specific in-progress fetch by its identifier.
    func cancelFetch(id: String) {
        removeFetcher(id: id)
    }

    /// Cancels all in-progress attachment fetches.
    func cancelAllFetches() {
        activeFetchers.removeAll()
        Log.info("[Attachment] All active fetches cancelled")
    }

    // MARK: - Private

    private func removeFetcher(id: String) {
        activeFetchers.removeValue(forKey: id)
    }
}
