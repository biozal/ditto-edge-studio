import DittoSwift
import Foundation

actor CollectionsRepository {
    static let shared = CollectionsRepository()

    private let dittoManager = DittoManager.shared
    private var appState: AppState?
    private var collectionsObserver: DittoStoreObserver?

    // Store the callback inside the actor
    private var onCollectionsUpdate: (@MainActor ([DittoCollection]) -> Void)?
    private let decoder = JSONDecoder()

    private init() {}

    deinit {
        collectionsObserver?.cancel()
    }

    func hydrateCollections() async throws -> [DittoCollection] {
        guard let ditto = await dittoManager.dittoSelectedApp,
              let appState else
        {
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

            // Fetch document counts as dictionary: [collectionName: count]
            let counts = try await fetchDocumentCounts(for: collections)

            // Enrich each collection with its count by looking up the collection name in the dictionary
            for i in collections.indices {
                let collectionName = collections[i].name
                collections[i].documentCount = counts[collectionName]
            }

            // Fetch indexes and attach to each collection
            let indexesByCollection = try await fetchIndexes(for: collections)
            for i in collections.indices {
                collections[i].indexes = indexesByCollection[collections[i].name] ?? []
            }

            // Register for any changes in the database
            collectionsObserver = try ditto.store.registerObserver(query: query) { [weak self] results in
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
                    if let counts = try? await fetchDocumentCounts(for: updatedCollections) {
                        // Match counts to collections by name (dictionary lookup)
                        for i in updatedCollections.indices {
                            let collectionName = updatedCollections[i].name
                            updatedCollections[i].documentCount = counts[collectionName]
                        }
                    }

                    // Fetch indexes and attach to each collection
                    if let indexesByCollection = try? await fetchIndexes(for: updatedCollections) {
                        for i in updatedCollections.indices {
                            updatedCollections[i].indexes = indexesByCollection[updatedCollections[i].name] ?? []
                        }
                    }

                    // Call the callback to update collections on main actor
                    await notifyCollectionsUpdate(updatedCollections.sorted { $0.name < $1.name })
                }
            }

            return collections.sorted { $0.name < $1.name }
        } catch {
            self.appState?.setError(error)
            throw error
        }
    }

    private func fetchIndexes(for collections: [DittoCollection]) async throws -> [String: [DittoIndex]] {
        guard let ditto = await dittoManager.dittoSelectedApp else {
            throw InvalidStateError(message: "No Ditto selected app available")
        }
        let results = try await ditto.store.execute(query: "SELECT * FROM system:indexes")
        var indexesByCollection: [String: [DittoIndex]] = [:]
        for item in results.items {
            do {
                let index = try decoder.decode(DittoIndex.self, from: item.jsonData())
                item.dematerialize()
                indexesByCollection[index.collection, default: []].append(index)
            } catch {
                item.dematerialize()
            }
        }
        return indexesByCollection
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
                   let count = firstItem.value["numDocs"] as? Int
                {
                    countsByCollection[collection.name] = count
                    firstItem.dematerialize()
                }
            } catch {
                // Continue with other collections even if one fails
            }
        }

        return countsByCollection
    }

    func refreshCollections() async throws -> [DittoCollection] {
        guard let ditto = await dittoManager.dittoSelectedApp,
              let appState else
        {
            throw InvalidStateError(message: "No Ditto selected app or app state available")
        }

        // Fetch current collections from the database
        let query = "SELECT * FROM __collections"
        let results = try await ditto.store.execute(query: query)

        var collections = results.items.compactMap { item -> DittoCollection? in
            do {
                let decodedItem = try decoder.decode(
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

        // Fetch fresh document counts
        let counts = try await fetchDocumentCounts(for: collections)

        // Enrich collections with updated counts
        for i in collections.indices {
            let collectionName = collections[i].name
            collections[i].documentCount = counts[collectionName]
        }

        // Fetch indexes and attach to each collection
        let indexesByCollection = try await fetchIndexes(for: collections)
        for i in collections.indices {
            collections[i].indexes = indexesByCollection[collections[i].name] ?? []
        }

        // Trigger the update callback to refresh UI on main actor
        let sorted = collections.sorted { $0.name < $1.name }
        await notifyCollectionsUpdate(sorted)

        return sorted
    }

    func createIndex(collection: String, fieldName: String) async throws {
        guard let ditto = await dittoManager.dittoSelectedApp else {
            throw InvalidStateError(message: "No Ditto selected app available")
        }
        let safeName = "idx_\(collection)_\(fieldName)"
            .replacingOccurrences(of: ".", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        let query = "CREATE INDEX IF NOT EXISTS \(safeName) ON \(collection) (\(fieldName))"
        _ = try await ditto.store.execute(query: query)
    }

    private func notifyCollectionsUpdate(_ collections: [DittoCollection]) async {
        await onCollectionsUpdate?(collections)
    }

    func setAppState(_ appState: AppState) {
        self.appState = appState
    }

    func setOnCollectionsUpdate(_ callback: @escaping @MainActor ([DittoCollection]) -> Void) {
        onCollectionsUpdate = callback
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
