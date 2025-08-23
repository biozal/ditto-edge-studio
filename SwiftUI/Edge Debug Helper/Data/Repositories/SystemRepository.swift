import DittoSwift
import Foundation

actor SystemRepository {
    static let shared = SystemRepository()
    
    private let dittoManager = DittoManager.shared
    private var syncStatusObserver: DittoStoreObserver?
    private var appState: AppState?
    
    // Store the callback inside the actor
    private var onSyncStatusUpdate: (([SyncStatusInfo]) -> Void)?
    
    private init() { }
    
    deinit {
        syncStatusObserver?.cancel()
    }
    
    func registerSyncStatusObserver() async throws {
        guard let ditto = await dittoManager.dittoSelectedApp else {
            throw InvalidStateError(message: "No selected app available")
        }
        
        // Register observer for sync status
        syncStatusObserver = try ditto.store.registerObserver(
            query: """
                SELECT * 
                FROM system:data_sync_info 
                ORDER BY documents.sync_session_status, documents.last_update_received_time desc
                """
        ) { [weak self] results in
            Task { [weak self] in
                guard let self else { return }
                
                // Create new SyncStatusInfo instances
                let statusItems = results.items.compactMap { item in
                    SyncStatusInfo(item.jsonData())
                }
                
                // Call the callback to update the ViewModel's published property
                await self.onSyncStatusUpdate?(statusItems)
            }
        }
    }
    
    func setAppState(_ appState: AppState) {
        self.appState = appState
    }
    
    // Function to set the callback from outside the actor
    func setOnSyncStatusUpdate(_ callback: @escaping ([SyncStatusInfo]) -> Void) {
        self.onSyncStatusUpdate = callback
    }
    
    func stopObserver() {
        // Use Task to ensure observer cleanup runs on appropriate background queue
        // This prevents priority inversion when called from main thread
        Task.detached(priority: .utility) { [weak self] in
            await self?.performObserverCleanup()
        }
    }
    
    private func performObserverCleanup() {
        syncStatusObserver?.cancel()
        syncStatusObserver = nil
    }
}

