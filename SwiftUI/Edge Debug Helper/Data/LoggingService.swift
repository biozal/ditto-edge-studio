import CocoaLumberjack
import CocoaLumberjackSwift
import Foundation

/// Centralized logging service for Edge Debug Helper
/// Provides file-based logging with rotation and retrieval capabilities for debugging and user support
/// Thread-safe: CocoaLumberjack handles all thread synchronization internally
class LoggingService {
    static let shared = LoggingService()

    private let fileLogger: DDFileLogger

    private init() {
        // Console logging for development (Xcode console)
        DDLog.add(DDOSLogger.sharedInstance)

        // File logging with automatic rotation
        fileLogger = DDFileLogger()

        // Rotate logs daily (24 hours)
        fileLogger.rollingFrequency = 60 * 60 * 24

        // Keep last 7 days of logs
        fileLogger.logFileManager.maximumNumberOfLogFiles = 7

        // Maximum 5MB per log file
        fileLogger.maximumFileSize = 1024 * 1024 * 5

        // Add file logger
        DDLog.add(fileLogger)

        // Set log level based on build configuration
        #if DEBUG
        DDLog.setLevel(.all, for: DDLog.self)
        #else
        DDLog.setLevel(.info, for: DDLog.self)
        #endif

        info("LoggingService initialized - logs directory: \(fileLogger.logFileManager.logsDirectory)")
    }

    // MARK: - Logging Methods

    /// Log debug information (development only)
    func debug(_ message: @autoclosure () -> String, file: StaticString = #file, function: StaticString = #function, line: UInt = #line) {
        DDLogDebug("\(message())", file: file, function: function, line: line)
    }

    /// Log informational messages
    func info(_ message: @autoclosure () -> String, file: StaticString = #file, function: StaticString = #function, line: UInt = #line) {
        DDLogInfo("\(message())", file: file, function: function, line: line)
    }

    /// Log warnings
    func warning(_ message: @autoclosure () -> String, file: StaticString = #file, function: StaticString = #function, line: UInt = #line) {
        DDLogWarn("\(message())", file: file, function: function, line: line)
    }

    /// Log errors
    func error(_ message: @autoclosure () -> String, file: StaticString = #file, function: StaticString = #function, line: UInt = #line) {
        DDLogError("\(message())", file: file, function: function, line: line)
    }

    // MARK: - Log Retrieval (for user viewing and GitHub issue export)

    /// Get all log file URLs sorted by date (newest first)
    func getAllLogFiles() -> [URL] {
        fileLogger.logFileManager.sortedLogFilePaths.map { URL(fileURLWithPath: $0) }
    }

    /// Get combined log content for viewing or export
    func getCombinedLogs() -> String {
        let logPaths = fileLogger.logFileManager.sortedLogFilePaths
        var combinedLogs = ""

        for logPath in logPaths {
            if let logContent = try? String(contentsOfFile: logPath, encoding: .utf8) {
                combinedLogs += "===== \(URL(fileURLWithPath: logPath).lastPathComponent) =====\n"
                combinedLogs += logContent
                combinedLogs += "\n\n"
            }
        }

        return combinedLogs
    }

    /// Get logs directory path for user access
    func getLogsDirectory() -> String {
        fileLogger.logFileManager.logsDirectory
    }

    /// Copy all logs to a specific directory (for export/sharing)
    func exportLogs(to destinationURL: URL) throws {
        let fileManager = FileManager.default

        // Create destination directory if needed
        if !fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)
        }

        // Copy each log file
        for logURL in getAllLogFiles() {
            let destFileURL = destinationURL.appendingPathComponent(logURL.lastPathComponent)

            // Remove existing file if present
            if fileManager.fileExists(atPath: destFileURL.path) {
                try fileManager.removeItem(at: destFileURL)
            }

            try fileManager.copyItem(at: logURL, to: destFileURL)
        }

        info("Exported \(getAllLogFiles().count) log files to: \(destinationURL.path)")
    }

    /// Clear all log files (for privacy/reset)
    func clearAllLogs() {
        let logPaths = fileLogger.logFileManager.sortedLogFilePaths

        for logPath in logPaths {
            try? FileManager.default.removeItem(atPath: logPath)
        }

        info("All log files cleared")
    }
}

/// Global logging convenience accessor
let Log = LoggingService.shared
