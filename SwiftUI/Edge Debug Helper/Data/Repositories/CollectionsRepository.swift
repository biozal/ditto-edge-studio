import DittoSwift
import Foundation

actor CollectionsRepository {
    static let shared = CollectionsRepository()
    
    private let dittoManager = DittoManager.shared
    private var appState: AppState?
    private var collectionsObserver: DittoStoreObserver?
    
    // Store the callback inside the actor
    private var onCollectionsUpdate: (([DittoCollection]) -> Void)?
    private let decoder = JSONDecoder()
    
    private init() { }
    
    deinit {
        collectionsObserver?.cancel()
    }
    
    func hydrateCollections() async throws -> [DittoCollection] {
        guard let ditto = await dittoManager.dittoSelectedApp,
              let appState = self.appState else {
            throw InvalidStateError(message: "No Ditto selected app or app state available")
        }

        let query = "SELECT * FROM __collections"

        do {
            // Hydrate the initial data from the database
            let results = try await ditto.store.execute(query: query)
            var collections = results.items.compactMap { item in
                do {
                    let decodedItem = try decoder.decode(
                        DittoCollection.self,
                        from: item.jsonData())
                    item.dematerialize()
                    return decodedItem
                } catch {
                    item.dematerialize()
                    appState.setError(error)
                    return nil
                }
            }.filter { !$0.name.hasPrefix("__") } // Filter out system collections

            // Fetch document counts as dictionary: [collectionName: count]
            let counts = try await fetchDocumentCounts(for: collections)

            // Enrich each collection with its count by looking up the collection name in the dictionary
            for i in collections.indices {
                let collectionName = collections[i].name
                collections[i].documentCount = counts[collectionName]
            }

            // Register for any changes in the database
            collectionsObserver = try ditto.store.registerObserver(
                query: query
            ) { [weak self] results in
                Task { [weak self] in
                    guard let self else { return }

                    var updatedCollections = results.items.compactMap { item -> DittoCollection? in
                        do {
                            let decodedItem = try self.decoder.decode(
                                DittoCollection.self,
                                from: item.jsonData()
                            )
                            item.dematerialize()
                            return decodedItem
                        } catch {
                            item.dematerialize()
                            appState.setError(error)
                            return nil
                        }
                    }.filter { !$0.name.hasPrefix("__") } // Filter out system collections

                    // Fetch counts on every update as dictionary: [collectionName: count]
                    if let counts = try? await self.fetchDocumentCounts(for: updatedCollections) {
                        // Match counts to collections by name (dictionary lookup)
                        for i in updatedCollections.indices {
                            let collectionName = updatedCollections[i].name
                            updatedCollections[i].documentCount = counts[collectionName]
                        }
                    }

                    // Call the callback to update collections
                    await self.onCollectionsUpdate?(updatedCollections)
                }
            }

            return collections
        } catch {
            self.appState?.setError(error)
            throw error
        }
    }

    private func fetchDocumentCounts(for collections: [DittoCollection]) async throws -> [String: Int] {
        guard let ditto = await dittoManager.dittoSelectedApp else {
            throw InvalidStateError(message: "No Ditto selected app available")
        }

        var countsByCollection: [String: Int] = [:]

        // Execute COUNT query for each collection
        // Note: 'count' is a reserved word in DQL, so we use 'numDocs' as the alias
        for collection in collections {
            let query = "SELECT COUNT(*) as numDocs FROM \(collection.name)"
            do {
                let results = try await ditto.store.execute(query: query, arguments: [:])

                if let firstItem = results.items.first,
                   let count = firstItem.value["numDocs"] as? Int {
                    countsByCollection[collection.name] = count
                    firstItem.dematerialize()
                }

                // Dematerialize any remaining items
                for item in results.items.dropFirst() {
                    item.dematerialize()
                }
            } catch {
                // Continue with other collections even if one fails
            }
        }

        return countsByCollection
    }
    
    func setAppState(_ appState: AppState) {
        self.appState = appState
    }
    
    func setOnCollectionsUpdate(_ callback: @escaping ([DittoCollection]) -> Void) {
        self.onCollectionsUpdate = callback
    }
    
    func stopObserver() {
        // Use Task to ensure observer cleanup runs on appropriate background queue
        // This prevents priority inversion when called from main thread
        Task.detached(priority: .utility) { [weak self] in
            await self?.performObserverCleanup()
        }
    }
    
    private func performObserverCleanup() {
        collectionsObserver?.cancel()
        collectionsObserver = nil
    }
}
