import DittoSwift
import Foundation

actor ObservableRepository {
    static let shared = ObservableRepository()
    
    private let dittoManager = DittoManager.shared
    private var observablesObserver: DittoStoreObserver?
    private var appState: AppState?
    private let differ = DittoDiffer()
    
    // Store the callback inside the actor
    private var onObservablesUpdate: (([DittoObservable]) -> Void)?
    
    private init() { }
    
    deinit {
        observablesObserver?.cancel()
    }
    
    func registerObservablesObserver(for selectedAppId: String) async throws {
        guard let ditto = await dittoManager.dittoLocal else {
            throw InvalidStateError(message: "Local Ditto instance not available")
        }
        
        _ = self.appState  // Capture reference before closure
        
        // Cancel existing observer if any
        observablesObserver?.cancel()
        
        // Create a mutable array to track observables
        var currentObservables: [DittoObservable] = []
        
        // Register observer for observables
        let query = "SELECT * FROM dittoobservations WHERE selectedApp_id = :selectedAppId ORDER BY lastUpdated"
        let arguments = ["selectedAppId": selectedAppId]
        
        observablesObserver = try ditto.store.registerObserver(
            query: query,
            arguments: arguments
        ) { [weak self] results in
            Task { [weak self] in
                guard let self else { return }
                
                // Calculate diffs
                let diffs = await self.differ.diff(results.items)
                
                // Apply deletions
                diffs.deletions.forEach { index in
                    if index < currentObservables.count {
                        currentObservables.remove(at: index)
                    }
                }
                
                // Apply insertions
                diffs.insertions.forEach { index in
                    if index < results.items.count {
                        let item = results.items[index]
                        let observable = DittoObservable(item.value)
                        if index <= currentObservables.count {
                            currentObservables.insert(observable, at: index)
                        } else {
                            currentObservables.append(observable)
                        }
                    }
                }
                
                // Apply updates
                diffs.updates.forEach { index in
                    if index < results.items.count && index < currentObservables.count {
                        let item = results.items[index]
                        currentObservables[index] = DittoObservable(item.value)
                    }
                }
                
                // Call the callback to update the ViewModel's published property
                await self.onObservablesUpdate?(currentObservables)
            }
        }
    }
    
    func removeDittoObservable(_ observable: DittoObservable) async throws {
        guard let ditto = await dittoManager.dittoLocal else {
            throw InvalidStateError(message: "Local Ditto instance not available")
        }
        
        let query = "DELETE FROM dittoobservations WHERE _id = :id"
        let arguments = ["id": observable.id]
        
        do {
            try await ditto.store.execute(
                query: query,
                arguments: arguments
            )
        } catch {
            self.appState?.setError(error)
            throw error
        }
    }
    
    func saveDittoObservable(_ observable: DittoObservable) async throws {
        guard let ditto = await dittoManager.dittoLocal,
              let selectedAppConfig = await dittoManager.dittoSelectedAppConfig else {
            throw InvalidStateError(message: "Local Ditto or selected app config not available")
        }
        
        let query = "INSERT INTO dittoobservations DOCUMENTS (:newObservable) ON ID CONFLICT DO MERGE"
        let arguments: [String: Any] = [
            "newObservable": [
                "_id": observable.id,
                "name": observable.name,
                "query": observable.query,
                "selectedApp_id": selectedAppConfig._id,
                "lastUpdated": Date().ISO8601Format(),
                "args": observable.args ?? "",
            ]
        ]
        
        do {
            try await ditto.store.execute(
                query: query,
                arguments: arguments
            )
        } catch {
            self.appState?.setError(error)
            throw error
        }
    }
    
    func setAppState(_ appState: AppState) {
        self.appState = appState
    }
    
    // Function to set the callback from outside the actor
    func setOnObservablesUpdate(_ callback: @escaping ([DittoObservable]) -> Void) {
        self.onObservablesUpdate = callback
    }
    
    func stopObserver() {
        // Use Task to ensure observer cleanup runs on appropriate background queue
        // This prevents priority inversion when called from main thread
        Task.detached(priority: .utility) { [weak self] in
            await self?.performObserverCleanup()
        }
    }
    
    private func performObserverCleanup() {
        observablesObserver?.cancel()
        observablesObserver = nil
    }
}
