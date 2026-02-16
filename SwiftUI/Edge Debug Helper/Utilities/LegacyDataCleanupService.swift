import Foundation
import AppKit

/// Service for detecting and cleaning up legacy data from pre-v1.0 versions
///
/// **Breaking Change Strategy:**
/// - v1.0 is NOT backward compatible with previous versions
/// - Users must manually re-enter all database configurations
/// - On first launch, if old data exists: show warning dialog
///   - Option 1: Delete all old data and start fresh
///   - Option 2: Close app (continue using old version)
/// - No data migration - clean slate approach
///
/// **Old Data Locations:**
/// - `ditto_appconfig/` - Old local Ditto database (insecure storage)
/// - `ditto_apps/` - Old app databases (need recreation with new directory structure)
///
/// **UserDefaults Flag:**
/// - `BreakingChangeCleanup_v1_Completed` - prevents showing dialog again
@MainActor
class LegacyDataCleanupService {
    static let shared = LegacyDataCleanupService()
    
    private let fileManager = FileManager.default
    private let userDefaultsKey = "BreakingChangeCleanup_v1_Completed"
    
    private init() {}
    
    // MARK: - Public API
    
    /// Checks if legacy data exists from pre-v1.0 versions
    /// - Returns: True if old data directories exist, false otherwise
    func hasLegacyData() async -> Bool {
        // Check if cleanup was already completed
        if UserDefaults.standard.bool(forKey: userDefaultsKey) {
            return false
        }
        
        // Get base directory
        guard let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return false
        }
        
        // Check for old directories
        let oldConfigDir = baseURL.appendingPathComponent("ditto_appconfig")
        let oldAppsDir = baseURL.appendingPathComponent("ditto_apps")
        
        let hasOldConfigDir = fileManager.fileExists(atPath: oldConfigDir.path)
        let hasOldAppsDir = fileManager.fileExists(atPath: oldAppsDir.path)
        
        return hasOldConfigDir || hasOldAppsDir
    }
    
    /// Shows breaking change warning dialog to user
    /// - Returns: True if user approved cleanup, false if user cancelled
    func showBreakingChangeWarning() async -> Bool {
        let alert = NSAlert()
        alert.messageText = "Breaking Change - Data Not Compatible"
        alert.informativeText = """
        Version 1.0 of Edge Debug Helper is not backward compatible with previous versions.
        
        All database configurations, query history, and favorites from the old version must be removed to continue. You will need to manually re-enter your database configurations.
        
        Would you like to remove the old data and continue with the new version?
        
        • Click 'Remove Old Data' to delete incompatible data and start fresh
        • Click 'Cancel' to close the app and continue using the old version
        
        Note: Only one version of Edge Debug Helper can be used at a time.
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Remove Old Data")
        alert.addButton(withTitle: "Cancel")
        
        let response = alert.runModal()
        
        // .alertFirstButtonReturn = "Remove Old Data" clicked
        // .alertSecondButtonReturn = "Cancel" clicked
        return response == .alertFirstButtonReturn
    }
    
    /// Cleans up all legacy data from pre-v1.0 versions
    /// - Throws: CleanupError if cleanup fails
    func cleanupLegacyData() async throws {
        print("🗑️ Starting legacy data cleanup...")
        
        // Get base directory
        guard let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw CleanupError.directoryNotFound
        }
        
        var errors: [Error] = []
        
        // Delete old config directory
        let oldConfigDir = baseURL.appendingPathComponent("ditto_appconfig")
        if fileManager.fileExists(atPath: oldConfigDir.path) {
            do {
                try fileManager.removeItem(at: oldConfigDir)
                print("✅ Deleted old config directory: \(oldConfigDir.path)")
            } catch {
                print("❌ Failed to delete old config directory: \(error)")
                errors.append(error)
            }
        }
        
        // Delete old apps directory
        let oldAppsDir = baseURL.appendingPathComponent("ditto_apps")
        if fileManager.fileExists(atPath: oldAppsDir.path) {
            do {
                try fileManager.removeItem(at: oldAppsDir)
                print("✅ Deleted old apps directory: \(oldAppsDir.path)")
            } catch {
                print("❌ Failed to delete old apps directory: \(error)")
                errors.append(error)
            }
        }
        
        // If any errors occurred, throw combined error
        if !errors.isEmpty {
            throw CleanupError.partialFailure(errors: errors)
        }
        
        // Mark cleanup as completed
        UserDefaults.standard.set(true, forKey: userDefaultsKey)
        print("✅ Legacy data cleanup completed successfully")
    }
    
    /// Resets the cleanup flag (for testing purposes only)
    func resetCleanupFlag() {
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
    }
}

// MARK: - Error Types

enum CleanupError: Error, LocalizedError {
    case directoryNotFound
    case partialFailure(errors: [Error])
    
    var errorDescription: String? {
        switch self {
        case .directoryNotFound:
            return "Application Support directory not found"
        case .partialFailure(let errors):
            let errorMessages = errors.map { $0.localizedDescription }.joined(separator: "\n")
            return "Some cleanup operations failed:\n\(errorMessages)"
        }
    }
}
