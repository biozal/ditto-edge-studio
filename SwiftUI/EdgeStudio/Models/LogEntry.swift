@preconcurrency import DittoSwift
import Foundation

/// A single log entry from any source (Ditto SDK, app logs, or imported files).
struct LogEntry: Identifiable {
    let id: UUID
    let timestamp: Date
    let level: DittoLogLevel
    let message: String
    let component: LogComponent
    let source: LogEntrySource
    /// Original raw text line for copy/export
    let rawLine: String

    init(
        id: UUID = UUID(),
        timestamp: Date,
        level: DittoLogLevel,
        message: String,
        component: LogComponent = .other,
        source: LogEntrySource,
        rawLine: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.message = message
        self.component = component
        self.source = source
        self.rawLine = rawLine
    }
}

extension LogEntry {
    /// Returns true if the entry's timestamp falls within [start, end] (inclusive on both ends).
    static func isWithinDateRange(_ entry: LogEntry, start: Date, end: Date) -> Bool {
        entry.timestamp >= start && entry.timestamp <= end
    }
}

/// Describes where a log entry originated.
enum LogEntrySource: Equatable {
    case dittoSDK
    case application
    case imported(label: String)
}

/// Log component, mapped from the Ditto SDK `target` field or inferred heuristically.
enum LogComponent: String, CaseIterable {
    case all = "All"
    case sync = "Sync"
    case store = "Store"
    case query = "Query"
    case observer = "Observer"
    case transport = "Transport"
    case auth = "Auth"
    case other = "Other"

    /// Maps a Ditto SDK `target` field (e.g. "ditto::sync") to a component.
    static func from(target: String) -> LogComponent {
        let lower = target.lowercased()
        if lower.contains("sync") { return .sync }
        if lower.contains("replication") { return .sync }
        if lower.contains("subscription") { return .sync }
        if lower.contains("store") { return .store }
        if lower.contains("service=blob") { return .store }
        if lower.contains("query") { return .query }
        if lower.contains("sqlparser") || lower.contains("sql_parser") { return .query }
        if lower.contains("observer") { return .observer }
        if lower.contains("transport") { return .transport }
        if lower.contains("discovery") { return .transport }
        if lower.contains("presence") { return .transport }
        if lower.contains("multihop") { return .transport }
        if lower.contains("network") { return .transport }
        if lower.contains("ble") { return .transport }
        if lower.contains("tcp") { return .transport }
        if lower.contains("awdl") { return .transport }
        if lower.contains("virtual_connection") { return .transport }
        if lower.contains("router") { return .transport }
        if lower.contains("auth") { return .auth }
        return .other
    }

    /// Heuristic component detection from plain-text callback messages.
    static func heuristic(from message: String) -> LogComponent {
        let lower = message.lowercased()
        if lower.contains("sync") { return .sync }
        if lower.contains("replication") { return .sync }
        if lower.contains("subscription") { return .sync }
        if lower.contains("store") || lower.contains("insert") || lower.contains("document") { return .store }
        if lower.contains("service=blob") { return .store }
        // Transport-first: well-known SDK operation names that must not be hijacked by a
        // "query" substring appearing later in the long message body.
        if lower.hasPrefix("add_ble_transport") ||
            lower.hasPrefix("start_tcp_server") ||
            lower.hasPrefix("add_awdl_transport") ||
            lower.hasPrefix("add_wifi_transport") { return .transport }
        // Additional missing transport keywords
        if lower.contains("tcp") { return .transport }
        if lower.contains("awdl") { return .transport }
        if lower.contains("query") || lower.contains("select") { return .query }
        if lower.hasPrefix("parsing sql") || lower.contains("sql parser") { return .query }
        if lower.contains("observer") { return .observer }
        if lower.contains("transport") || lower.contains("bluetooth") || lower.contains("wifi") { return .transport }
        if lower.contains("discovery") || lower.contains("mdns") { return .transport }
        if lower.contains("presence") || lower.contains("multihop") { return .transport }
        if lower.contains("ble_") || lower.contains(" ble") { return .transport }
        if lower.contains("virtual_connection") { return .transport }
        if lower.contains("router_") { return .transport }
        if lower.contains("auth") || lower.contains("token") { return .auth }
        return .other
    }
}

extension DittoLogLevel {
    /// Human-readable label for display in the UI.
    var displayName: String {
        switch self {
        case .error: return "Error"
        case .warning: return "Warning"
        case .info: return "Info"
        case .debug: return "Debug"
        case .verbose: return "Verbose"
        @unknown default: return "Unknown"
        }
    }

    /// Short label for compact display.
    var shortName: String {
        switch self {
        case .error: return "ERR"
        case .warning: return "WARN"
        case .info: return "INFO"
        case .debug: return "DBG"
        case .verbose: return "VERB"
        @unknown default: return "?"
        }
    }

    /// Initializes from the string stored in `DittoConfigForDatabase.logLevel`.
    static func from(string: String) -> DittoLogLevel {
        switch string {
        case "error": return .error
        case "warning": return .warning
        case "debug": return .debug
        case "verbose": return .verbose
        default: return .info
        }
    }

    /// Returns a string suitable for storage in `DittoConfigForDatabase.logLevel`.
    var storageString: String {
        switch self {
        case .error: return "error"
        case .warning: return "warning"
        case .info: return "info"
        case .debug: return "debug"
        case .verbose: return "verbose"
        @unknown default: return "info"
        }
    }
}
