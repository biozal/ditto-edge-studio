import DittoSwift
import Foundation

actor FavoritesRepository {
    static let shared = FavoritesRepository()
    
    private let dittoManager = DittoManager.shared
    private var appState: AppState?
    private var favoritesObserver: DittoStoreObserver?
    
    // Store the callback inside the actor
    private var onFavoritesUpdate: (([DittoQueryHistory]) -> Void)?
    
    private init() { }
    
    deinit {
        favoritesObserver?.cancel()
    }
    
    func deleteFavorite(_ id: String) async throws {
        guard let ditto = await dittoManager.dittoLocal else {
            throw InvalidStateError(message: "No Ditto local database available")
        }
        
        let query = "DELETE FROM dittoqueryfavorites WHERE _id = :id"
        let arguments: [String: Any] = ["id": id]
        
        do {
            let _ = try await ditto.store.execute(query: query, arguments: arguments)
        } catch {
            self.appState?.setError(error)
            throw error
        }
    }

    func hydrateQueryFavorites() async throws -> [DittoQueryHistory] {
        guard let ditto = await dittoManager.dittoLocal,
              let selectedAppConfig = await dittoManager.dittoSelectedAppConfig else {
            throw InvalidStateError(message: "No Ditto local database or selected app available")
        }
        
        let appStateRef = self.appState  // Capture reference before closure
        let query = "SELECT * FROM dittoqueryfavorites WHERE selectedApp_id = :selectedAppId ORDER BY createdDate DESC"
        let arguments = ["selectedAppId": selectedAppConfig._id]
        let decoder = JSONDecoder()
        
        do {
            // Hydrate the initial data from the database
            let historyResults = try await ditto.store.execute(query: query, arguments: arguments)
            let historyItems = historyResults.items.compactMap { item in
                do {
                    return try decoder.decode(DittoQueryHistory.self, from: item.jsonData())
                } catch {
                    appStateRef?.setError(error)
                    return nil
                }
            }
            
            // Register for any changes in the database
            favoritesObserver = try ditto.store.registerObserver(
                query: query,
                arguments: arguments
            ) { [weak self] results in
                Task { [weak self] in
                    guard let self else { return }
                    
                    let historyItems = results.items.compactMap { item in
                        do {
                            return try decoder.decode(DittoQueryHistory.self, from: item.jsonData())
                        } catch {
                            appStateRef?.setError(error)
                            return nil
                        }
                    }

                    // Update the in-memory service
                    await MainActor.run {
                        FavoritesService.shared.loadFavorites(historyItems)
                    }

                    // Call the callback to update the ViewModel's published property
                    await self.onFavoritesUpdate?(historyItems)
                }
            }
            
            return historyItems
        } catch {
            self.appState?.setError(error)
            throw error
        }
    }
    
    func isFavorited(query: String) async throws -> Bool {
        guard let ditto = await dittoManager.dittoLocal,
              let selectedAppConfig = await dittoManager.dittoSelectedAppConfig else {
            return false
        }

        let checkQuery = "SELECT * FROM dittoqueryfavorites WHERE selectedApp_id = :selectedAppId AND query = :query LIMIT 1"
        let arguments: [String: Any] = [
            "selectedAppId": selectedAppConfig._id,
            "query": query
        ]

        do {
            let results = try await ditto.store.execute(query: checkQuery, arguments: arguments)
            return !results.items.isEmpty
        } catch {
            return false
        }
    }

    func saveFavorite(_ favorite: DittoQueryHistory) async throws {
        guard let ditto = await dittoManager.dittoLocal,
              let selectedAppConfig = await dittoManager.dittoSelectedAppConfig else {
            throw InvalidStateError(message: "No Ditto local database or selected app available")
        }

        // Check if already favorited
        let isFav = try await isFavorited(query: favorite.query)
        if isFav {
            return // Already favorited, skip
        }

        let query = "INSERT INTO dittoqueryfavorites DOCUMENTS (:queryHistory)"
        let arguments: [String: Any] = [
            "queryHistory": [
                "_id": UUID().uuidString,
                "query": favorite.query,
                "createdDate": Date().ISO8601Format(),
                "selectedApp_id": selectedAppConfig._id
            ]
        ]

        do {
            let _ = try await ditto.store.execute(query: query, arguments: arguments)
        } catch {
            self.appState?.setError(error)
            throw error
        }
    }

    func removeFavoriteByQuery(query: String) async throws {
        guard let ditto = await dittoManager.dittoLocal,
              let selectedAppConfig = await dittoManager.dittoSelectedAppConfig else {
            throw InvalidStateError(message: "No Ditto local database or selected app available")
        }

        let deleteQuery = "DELETE FROM dittoqueryfavorites WHERE selectedApp_id = :selectedAppId AND query = :query"
        let arguments: [String: Any] = [
            "selectedAppId": selectedAppConfig._id,
            "query": query
        ]

        do {
            let _ = try await ditto.store.execute(query: deleteQuery, arguments: arguments)
        } catch {
            self.appState?.setError(error)
            throw error
        }
    }
    
    func setAppState(_ appState: AppState) {
        self.appState = appState
    }
    
    // Function to set the callback from outside the actor
    func setOnFavoritesUpdate(_ callback: @escaping ([DittoQueryHistory]) -> Void) {
        self.onFavoritesUpdate = callback
    }
    
    func stopObserver() {
        // Use Task to ensure observer cleanup runs on appropriate background queue
        // This prevents priority inversion when called from main thread
        Task.detached(priority: .utility) { [weak self] in
            await self?.performObserverCleanup()
        }
    }
    
    private func performObserverCleanup() {
        favoritesObserver?.cancel()
        favoritesObserver = nil
    }
}
