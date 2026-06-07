import Compression
import DittoSwift
import Foundation

/// Parses log files from multiple formats into `LogEntry` arrays.
enum LogFileParser {
    // MARK: - Directory Parsing

    /// Parses all `.log` and `.log.gz` files in a Ditto SDK logs directory.
    static func parseDirectory(_ url: URL) -> [LogEntry] {
        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil
        ) else { return [] }

        let logFiles = contents.filter { url in
            let name = url.lastPathComponent
            return name.hasSuffix(".log") || name.hasSuffix(".log.gz")
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }

        var entries: [LogEntry] = []
        for fileURL in logFiles {
            if fileURL.lastPathComponent.hasSuffix(".gz") {
                entries.append(contentsOf: parseGzipJSONL(fileURL))
            } else {
                entries.append(contentsOf: parseJSONLFile(fileURL))
            }
        }
        return entries
    }

    // MARK: - JSON Lines Parsing (plain text .log files)

    static func parseJSONLFile(_ url: URL) -> [LogEntry] {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return parseJSONLString(content, source: .dittoSDK)
    }

    // MARK: - Gzip JSON Lines Parsing (.log.gz files)

    /// Decompresses a gzip file using Apple's Compression framework and parses JSON Lines.
    static func parseGzipJSONL(_ url: URL) -> [LogEntry] {
        guard let compressedData = try? Data(contentsOf: url) else { return [] }

        // Use Apple's Compression framework (sandbox-safe, no shell processes)
        guard let decompressed = decompressGzip(compressedData) else { return [] }
        guard let content = String(data: decompressed, encoding: .utf8) else { return [] }
        return parseJSONLString(content, source: .dittoSDK)
    }

    // MARK: - CocoaLumberjack Plain-Text Log Files

    /// Parses CocoaLumberjack plain-text log files.
    /// CocoaLumberjack writes UTC timestamps with slash separators:
    /// `YYYY/MM/DD HH:MM:SS:mmm LEVEL [file.swift:line]   Message`
    /// Compiled once and reused — `NSRegularExpression(pattern:)` compilation is
    /// expensive and the pattern is constant across every parse invocation.
    private static let cocoaLumberjackRegex = try? NSRegularExpression(
        pattern: #"^(\d{4}/\d{2}/\d{2} \d{2}:\d{2}:\d{2}:\d{3})\s+(\w+)\s"#
    )

    /// Reused across parses (see `cocoaLumberjackRegex`). `DateFormatter` is
    /// `Sendable`, so a plain `static let` is safe to share.
    private static let cocoaLumberjackDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy/MM/dd HH:mm:ss:SSS"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0) // CL writes UTC
        return f
    }()

    static func parseCocoaLumberjackFiles(_ urls: [URL]) -> [LogEntry] {
        var entries: [LogEntry] = []
        let formatter = Self.cocoaLumberjackDateFormatter
        let regex = Self.cocoaLumberjackRegex

        for fileURL in urls {
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            let lines = content.components(separatedBy: .newlines)
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { continue }

                let nsLine = trimmed as NSString
                guard let match = regex?.firstMatch(
                    in: trimmed,
                    range: NSRange(trimmed.startIndex..., in: trimmed)
                ) else {
                    // Unparseable line — still include as 'other' with info level
                    entries.append(LogEntry(
                        timestamp: Date.now,
                        level: .info,
                        message: trimmed,
                        component: .other,
                        source: .application,
                        rawLine: trimmed
                    ))
                    continue
                }

                let dateStr = nsLine.substring(with: match.range(at: 1))
                let levelStr = nsLine.substring(with: match.range(at: 2)).uppercased()
                let timestamp = formatter.date(from: dateStr) ?? Date.now
                let level = cocoaLevelFromString(levelStr)

                // Message = everything after the match
                let matchEnd = match.range.location + match.range.length
                let message = matchEnd < nsLine.length
                    ? nsLine.substring(from: matchEnd).trimmingCharacters(in: .whitespaces)
                    : trimmed

                entries.append(LogEntry(
                    timestamp: timestamp,
                    level: level,
                    message: message,
                    component: .other,
                    source: .application,
                    rawLine: trimmed
                ))
            }
        }
        return entries
    }

    // MARK: - Private Helpers

    static func parseJSONLString(_ content: String, source: LogEntrySource) -> [LogEntry] {
        // Function-local formatters: `ISO8601DateFormatter` is not `Sendable`, so
        // keeping these local (rather than shared statics) avoids any cross-thread
        // sharing without needing a `nonisolated(unsafe)` escape hatch. Creation is
        // negligible relative to the file I/O and per-line parsing below, and they
        // are reused across every line in this file.
        let isoWithFraction: ISO8601DateFormatter = {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return f
        }()
        let isoWithoutFraction: ISO8601DateFormatter = {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime]
            return f
        }()

        let lines = content.components(separatedBy: .newlines)
        var entries: [LogEntry] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, trimmed.hasPrefix("{") else { continue }
            guard let data = trimmed.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

            let timestampStr = json["timestamp"] as? String ?? ""
            // Try with fractional seconds first, then without — Ditto SDK may omit milliseconds
            let timestamp = isoWithFraction.date(from: timestampStr)
                ?? isoWithoutFraction.date(from: timestampStr)
                ?? Date.now
            let levelStr = (json["level"] as? String ?? "info").lowercased()
            let target = json["target"] as? String ?? ""
            let message = json["message"] as? String ?? trimmed
            let level = dittoLevelFromString(levelStr)
            let component = LogComponent.from(target: target)

            entries.append(LogEntry(
                timestamp: timestamp,
                level: level,
                message: message,
                component: component,
                source: source,
                rawLine: trimmed
            ))
        }
        return entries
    }

    private static func decompressGzip(_ data: Data) -> Data? {
        // Skip the 10-byte gzip header + 8-byte trailer and decompress the payload
        guard data.count > 18 else { return nil }

        // The gzip payload starts at byte 10 (after fixed header)
        // We use a large output buffer and decompress with COMPRESSION_ZLIB (raw deflate)
        let payloadRange = 10 ..< (data.count - 8)
        let compressedPayload = data.subdata(in: payloadRange)

        // Use original size hint from gzip trailer (last 4 bytes = uncompressed size mod 2^32)
        let sizeBytes = data.subdata(in: (data.count - 4) ..< data.count)
        let originalSize = sizeBytes.withUnsafeBytes { ptr in
            ptr.load(as: UInt32.self).littleEndian
        }

        // Allocate output buffer — use 4x as fallback if size hint is 0
        let bufferSize = originalSize > 0 ? Int(originalSize) : compressedPayload.count * 8
        var outputBuffer = [UInt8](repeating: 0, count: bufferSize)

        let decompressedSize = compressedPayload.withUnsafeBytes { srcPtr -> Int in
            guard let src = srcPtr.baseAddress else { return 0 }
            return compression_decode_buffer(
                &outputBuffer, bufferSize,
                src, compressedPayload.count,
                nil, COMPRESSION_ZLIB
            )
        }

        guard decompressedSize > 0 else { return nil }
        return Data(outputBuffer.prefix(decompressedSize))
    }

    private static func dittoLevelFromString(_ str: String) -> DittoLogLevel {
        switch str.lowercased() {
        case "error": return .error
        case "warn", "warning": return .warning
        case "debug": return .debug
        case "trace", "verbose": return .verbose
        default: return .info
        }
    }

    private static func cocoaLevelFromString(_ str: String) -> DittoLogLevel {
        switch str {
        case "ERROR": return .error
        case "WARN", "WARNING": return .warning
        case "DEBUG": return .debug
        case "VERBOSE": return .verbose
        default: return .info
        }
    }
}
