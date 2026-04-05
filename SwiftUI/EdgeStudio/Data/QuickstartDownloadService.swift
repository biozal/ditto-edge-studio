import Foundation
import Observation

// MARK: - QuickstartProject Model

struct QuickstartProject: Identifiable {
    let id = UUID()
    let name: String
    let directoryName: String
    let path: URL
    var isConfigured: Bool
}

// MARK: - QuickstartDownloadService

@Observable
final class QuickstartDownloadService {
    // MARK: - State

    var isDownloading = false
    var downloadProgress = 0.0
    var projects: [QuickstartProject] = []

    // MARK: - Static Constants

    static let zipURL = URL(string: "https://github.com/getditto/quickstart/archive/refs/heads/main.zip")!
    static let extractedFolderName = "quickstart-main"

    static let projectDisplayNames: [String: String] = [
        "android-java": "Android Java",
        "android-kotlin": "Android Kotlin",
        "cpp-tui": "C++ TUI",
        "dotnet-maui": ".NET MAUI",
        "dotnet-tui": ".NET TUI",
        "dotnet-winforms": ".NET WinForms",
        "edge-server": "Edge Server",
        "flutter_app": "Flutter",
        "go-tui": "Go TUI",
        "java-server": "Java Server",
        "javascript-tui": "JavaScript TUI",
        "javascript-web": "JavaScript Web",
        "kotlin-multiplatform": "Kotlin Multiplatform",
        "react-native": "React Native",
        "react-native-expo": "React Native Expo",
        "rust-tui": "Rust TUI",
        "swift": "Swift"
    ]

    // MARK: - Errors

    enum QuickstartError: LocalizedError {
        case extractionFailed(String)
        case envSampleNotFound(String)

        var errorDescription: String? {
            switch self {
            case let .extractionFailed(detail):
                return "Extraction failed: \(detail)"
            case let .envSampleNotFound(path):
                return "Could not find .env.sample at: \(path)"
            }
        }
    }

    // MARK: - Download & Extract

    /// Downloads the quickstart zip from GitHub, extracts it to the given destination, and returns the extracted folder URL.
    func downloadAndExtract(to destination: URL) async throws -> URL {
        await MainActor.run {
            isDownloading = true
            downloadProgress = 0.0
        }

        defer {
            Task { @MainActor in
                isDownloading = false
            }
        }

        Log.info("QuickstartDownloadService: Starting download from \(Self.zipURL)")

        // Download zip
        let (localZipURL, _) = try await URLSession.shared
            .download(from: Self.zipURL) { [weak self] _, totalBytesWritten, totalBytesExpectedToWrite in
                guard let self else { return }
                if totalBytesExpectedToWrite > 0 {
                    let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) * 0.8
                    Task { @MainActor in
                        self.downloadProgress = progress
                    }
                }
            }

        Log.info("QuickstartDownloadService: Download complete, extracting to \(destination.path)")

        await MainActor.run {
            downloadProgress = 0.85
        }

        // Extract zip using /usr/bin/unzip
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", localZipURL.path, "-d", destination.path]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let exitCode = process.terminationStatus
        if exitCode != 0 {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            Log.error("QuickstartDownloadService: Extraction failed with exit code \(exitCode): \(errorMessage)")
            throw QuickstartError.extractionFailed("Exit code \(exitCode): \(errorMessage)")
        }

        // Clean up temp zip
        try? FileManager.default.removeItem(at: localZipURL)

        await MainActor.run {
            downloadProgress = 1.0
        }

        let extractedPath = destination.appendingPathComponent(Self.extractedFolderName)
        Log.info("QuickstartDownloadService: Extracted to \(extractedPath.path)")
        return extractedPath
    }

    // MARK: - Configure .env Files

    /// Generates .env content and writes it to three locations: repo root, flutter_app/, and go-tui/.
    func configureEnvFiles(
        in repoRoot: URL,
        databaseId: String,
        token: String,
        authUrl: String,
        websocketUrl: String
    ) throws {
        // Build env content without leading whitespace on each line
        let envLines = [
            "#!/usr/bin/env bash",
            "",
            "# Auto-configured by Edge Studio",
            "DITTO_APP_ID=\"\(databaseId)\"",
            "DITTO_PLAYGROUND_TOKEN=\"\(token)\"",
            "DITTO_AUTH_URL=\"\(authUrl)\"",
            "DITTO_WEBSOCKET_URL=\"\(websocketUrl)\""
        ]
        let envContent = envLines.joined(separator: "\n")

        let envLocations: [URL] = [
            repoRoot.appendingPathComponent(".env"),
            repoRoot.appendingPathComponent("flutter_app").appendingPathComponent(".env"),
            repoRoot.appendingPathComponent("go-tui").appendingPathComponent(".env")
        ]

        let fileManager = FileManager.default

        for envURL in envLocations {
            let directory = envURL.deletingLastPathComponent()
            if fileManager.fileExists(atPath: directory.path) {
                do {
                    try envContent.write(to: envURL, atomically: true, encoding: .utf8)
                    Log.info("QuickstartDownloadService: Wrote .env to \(envURL.path)")
                } catch {
                    Log.warning("QuickstartDownloadService: Failed to write .env to \(envURL.path): \(error.localizedDescription)")
                }
            } else {
                Log.info("QuickstartDownloadService: Skipping .env for non-existent directory \(directory.path)")
            }
        }
    }

    // MARK: - Configure Edge Server YAML

    /// Generates quickstart_config.yaml in the edge-server/ subdirectory.
    func configureEdgeServerYaml(
        in repoRoot: URL,
        databaseId: String,
        token: String,
        authUrl: String
    ) throws {
        // Build YAML content without leading whitespace on each line
        let yamlLines = [
            "resources:",
            "  my_ditto_db:",
            "    resource_type: DittoDatabase",
            "    db_id: \"\(databaseId)\"",
            "    device_name: \"edge-studio-quickstart\"",
            "    subscriptions:",
            "      - \"SELECT * FROM tasks\"",
            "    auth:",
            "      server:",
            "        access_token: \"\(token)\"",
            "        auth_url: \"\(authUrl)\"",
            "        provider: \"__playgroundProvider\"",
            "  my_http_server:",
            "    resource_type: HttpServer",
            "    listen_addr: \"0.0.0.0:8080\"",
            "    databases:",
            "      my_db:",
            "        db_id: \"\(databaseId)\"",
            "        base_path: my_server",
            "        http_api: true"
        ]
        let yamlContent = yamlLines.joined(separator: "\n")

        let edgeServerDir = repoRoot.appendingPathComponent("edge-server")
        let yamlURL = edgeServerDir.appendingPathComponent("quickstart_config.yaml")

        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: edgeServerDir.path) else {
            Log.info("QuickstartDownloadService: edge-server directory not found, skipping YAML config")
            return
        }

        try yamlContent.write(to: yamlURL, atomically: true, encoding: .utf8)
        Log.info("QuickstartDownloadService: Wrote edge-server YAML to \(yamlURL.path)")
    }

    // MARK: - Discover Projects

    /// Scans the directory for known project folders and populates the projects array.
    func discoverProjects(in directory: URL, isConfigured: Bool) {
        let fileManager = FileManager.default
        var discovered: [QuickstartProject] = []

        for (dirName, displayName) in Self.projectDisplayNames {
            let projectURL = directory.appendingPathComponent(dirName)
            if fileManager.fileExists(atPath: projectURL.path) {
                let project = QuickstartProject(
                    name: displayName,
                    directoryName: dirName,
                    path: projectURL,
                    isConfigured: isConfigured
                )
                discovered.append(project)
            }
        }

        // Sort by display name for consistent ordering
        discovered.sort { $0.name < $1.name }

        Task { @MainActor in
            projects = discovered
        }

        Log.info("QuickstartDownloadService: Discovered \(discovered.count) projects in \(directory.path)")
    }

    // MARK: - Existing Folder Check

    /// Returns the URL of the quickstart-main folder if it exists at the given location.
    func existingQuickstartFolder(in location: URL) -> URL? {
        let folderURL = location.appendingPathComponent(Self.extractedFolderName)
        if FileManager.default.fileExists(atPath: folderURL.path) {
            return folderURL
        }
        return nil
    }

    // MARK: - Remove Existing Folder

    /// Removes the directory at the given URL.
    func removeExistingFolder(at url: URL) throws {
        try FileManager.default.removeItem(at: url)
        Log.info("QuickstartDownloadService: Removed folder at \(url.path)")
    }
}

// MARK: - URLSession Download Extension

private extension URLSession {
    func download(from url: URL, progressHandler: @escaping (Int64, Int64, Int64) -> Void) async throws -> (URL, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            let task = downloadTask(with: url) { localURL, response, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let localURL, let response else {
                    continuation.resume(throwing: URLError(.badServerResponse))
                    return
                }
                continuation.resume(returning: (localURL, response))
            }

            // Observe progress via a periodic check is not straightforward here;
            // use the delegate-based approach for progress reporting via the observation block
            let observation = task.progress.observe(\.fractionCompleted) { progress, _ in
                progressHandler(0, Int64(progress.fractionCompleted * 1_000_000), 1_000_000)
            }

            task.resume()

            // Keep observation alive until task completes
            _ = observation
        }
    }
}
