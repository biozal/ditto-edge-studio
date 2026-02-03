import DittoSwift
import Foundation

actor HistoryRepository {
    static let shared = HistoryRepository()
    
    private let dittoManager = DittoManager.shared
    private var appState: AppState?
    private var historyObserver: DittoStoreObserver?
    
    // Store the callback inside the actor
    private var onHistoryUpdate: (([DittoQueryHistory]) -> Void)?
    
    private init() { }
    
    deinit {
        historyObserver?.cancel()
    }
    
    func clearQueryHistory() async throws {
        guard let ditto = await dittoManager.dittoLocal,
              let selectedAppConfig = await dittoManager.dittoSelectedAppConfig else {
            throw InvalidStateError(message: "No Ditto local database or selected app available")
        }
        
        let query = "DELETE FROM dittoqueryhistory WHERE selectedApp_id = :selectedApp_id"
        let arguments: [String: Any] = ["selectedApp_id": selectedAppConfig._id]
        
        do {
            let _ = try await ditto.store.execute(query: query, arguments: arguments)
        } catch {
            self.appState?.setError(error)
            throw error
        }
    }
    
    func deleteQueryHistory(_ id: String) async throws {
        guard let ditto = await dittoManager.dittoLocal else {
            throw InvalidStateError(message: "No Ditto local database available")
        }
        
        let query = "DELETE FROM dittoqueryhistory WHERE _id = :id"
        let arguments: [String: Any] = ["id": id]
        
        do {
            let _ = try await ditto.store.execute(query: query, arguments: arguments)
        } catch {
            self.appState?.setError(error)
            throw error
        }
    }
    
    func hydrateQueryHistory() async throws -> [DittoQueryHistory] {
        guard let ditto = await dittoManager.dittoLocal,
              let selectedAppConfig = await dittoManager.dittoSelectedAppConfig else {
            throw InvalidStateError(message: "No Ditto local database or selected app available")
        }
        
        let appStateRef = self.appState  // Capture reference before closure
        let query = "SELECT * FROM dittoqueryhistory WHERE selectedApp_id = :selectedAppId ORDER BY createdDate DESC"
        let arguments = ["selectedAppId": selectedAppConfig._id]
        let decoder = JSONDecoder()
        
        do {
            // Hydrate the initial data from the database
            let historyResults = try await ditto.store.execute(query: query, arguments: arguments)
            let historyItems = historyResults.items.compactMap { item in
                do {
                    let result = try decoder.decode(DittoQueryHistory.self, from: item.jsonData())
                    item.dematerialize()
                    return result
                } catch {
                    appStateRef?.setError(error)
                    return nil
                }
            }
            
            // Register for any changes in the database
            historyObserver = try ditto.store.registerObserver(
                query: query,
                arguments: arguments
            ) { [weak self] results in
                Task { [weak self] in
                    guard let self else { return }
                    
                    let historyItems = results.items.compactMap { item in
                        do {
                            let result =  try decoder.decode(DittoQueryHistory.self, from: item.jsonData())
                            item.dematerialize()
                            return result
                        } catch {
                            appStateRef?.setError(error)
                            return nil
                        }
                    }
                    
                    // Call the callback to update the ViewModel's published property
                    await self.onHistoryUpdate?(historyItems)
                }
            }
            
            return historyItems
        } catch {
            self.appState?.setError(error)
            throw error
        }
    }
    
    func saveQueryHistory(_ history: DittoQueryHistory) async throws {
        guard let ditto = await dittoManager.dittoLocal,
              let selectedAppConfig = await dittoManager.dittoSelectedAppConfig else {
            throw InvalidStateError(message: "No Ditto local database or selected app available")
        }
        
        do {
            // Check if we already have the query; if so, update the date, otherwise insert new record
            let queryCheck = "SELECT * FROM dittoqueryhistory WHERE query = :query AND selectedApp_id = :selectedAppId"
            let argumentsCheck: [String: Any] = [
                "query": history.query,
                "selectedAppId": selectedAppConfig._id
            ]
            let resultsCheck = try await ditto.store.execute(query: queryCheck, arguments: argumentsCheck)
            
            if resultsCheck.items.count > 0 {
                let decoder = JSONDecoder()
                guard let item = resultsCheck.items.first else {
                    return
                }
                let existingHistory = try decoder.decode(DittoQueryHistory.self, from: item.jsonData())
                let query = "UPDATE dittoqueryhistory SET createdDate = :createdDate WHERE _id = :id"
                let arguments: [String: Any] = [
                    "id": existingHistory.id,
                    "createdDate": Date().ISO8601Format()
                ]
                let _ = try await ditto.store.execute(query: query, arguments: arguments)
                item.dematerialize()
            } else {
                let query = "INSERT INTO dittoqueryhistory DOCUMENTS (:queryHistory)"
                let arguments: [String: Any] = [
                    "queryHistory": [
                        "_id": history.id,
                        "query": history.query,
                        "createdDate": history.createdDate,
                        "selectedApp_id": selectedAppConfig._id
                    ]
                ]
                let _ = try await ditto.store.execute(query: query, arguments: arguments)
            }
        } catch {
            self.appState?.setError(error)
            throw error
        }
    }
    
    func setAppState(_ appState: AppState) {
        self.appState = appState
    }
    
    func setOnHistoryUpdate(_ callback: @escaping ([DittoQueryHistory]) -> Void) {
        self.onHistoryUpdate = callback
    }
    
    func stopObserver() {
        // Use Task to ensure observer cleanup runs on appropriate background queue
        // This prevents priority inversion when called from main thread
        Task.detached(priority: .utility) { [weak self] in
            await self?.performObserverCleanup()
        }
    }
    
    private func performObserverCleanup() {
        historyObserver?.cancel()
        historyObserver = nil
    }
}
