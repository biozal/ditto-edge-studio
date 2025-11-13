//
//  EdgeStudioCollectionsRepository.swift
//  Edge Studio
//
//  Repository for managing collections in the selected app's __collections system collection
//

import DittoSwift
import Foundation

actor EdgeStudioCollectionsRepository {
    static let shared = EdgeStudioCollectionsRepository()
    
    private let dittoManager = DittoManager.shared
    private var appState: AppState?
    private var collectionsObserver: DittoStoreObserver?
    
    // Store the callback inside the actor
    private var onCollectionsUpdate: (([DittoCollectionModel]) -> Void)?
    
    private init() { }
    
    deinit {
        collectionsObserver?.cancel()
    }
    
    func hydrateCollections() async throws -> [DittoCollectionModel] {
        guard let ditto = await dittoManager.dittoSelectedApp,
              let appState = self.appState else {
            throw InvalidStateError(message: "No Ditto selected app or app state available")
        }

        let query = "SELECT * FROM __collections"
        let decoder = JSONDecoder()

        do {
            // Hydrate the initial data from __collections
            let results = try await ditto.store.execute(query: query)
            let collectionNames = results.items.compactMap { item in
                do {
                    return try decoder.decode(
                        DittoCollection.self,
                        from: item.jsonData()
                    )
                } catch {
                    appState.setError(error)
                    return nil
                }
            }.filter { !$0.name.hasPrefix("__") } // Filter out system collections

            // Deduplicate collection names using Dictionary to preserve order and avoid duplicate IDs
            var uniqueCollections = Dictionary(grouping: collectionNames, by: { $0.name })
                .compactMap { $0.value.first }
                .sorted { $0.name < $1.name }

            // Asynchronously query __small_peer_info to get actual collections
            Task { [weak self] in
                guard let self else { return }
                await self.reconcileCollectionsFromSmallPeerInfo()
            }

            // Register for any changes in the __collections database
            collectionsObserver = try ditto.store.registerObserver(
                query: query
            ) { [weak self] results in
                Task { [weak self] in
                    guard let self else { return }

                    let collectionNames = results.items.compactMap { item in
                        do {
                            return try decoder.decode(
                                DittoCollection.self,
                                from: item.jsonData()
                            )
                        } catch {
                            appState.setError(error)
                            return nil
                        }
                    }.filter { !$0.name.hasPrefix("__") } // Filter out system collections

                    // Deduplicate collection names using Dictionary to preserve order and avoid duplicate IDs
                    let uniqueCollections = Dictionary(grouping: collectionNames, by: { $0.name })
                        .compactMap { $0.value.first }
                        .sorted { $0.name < $1.name }

                    // Create collection models with counts from __small_peer_info if available
                    let collections = uniqueCollections.map { DittoCollectionModel(name: $0.name, documentCount: 0) }

                    // Call the callback to update collections
                    await self.onCollectionsUpdate?(collections)
                }
            }

            // Create collection models without counts initially (will be updated by reconciliation)
            let collections = uniqueCollections.map { DittoCollectionModel(name: $0.name, documentCount: 0) }
            return collections
        } catch {
            self.appState?.setError(error)
            throw error
        }
    }

    private func reconcileCollectionsFromSmallPeerInfo() async {
        guard let ditto = await dittoManager.dittoSelectedApp else { return }

        do {
            // Query __small_peer_info to get actual collections with document counts
            let query = "SELECT * FROM __small_peer_info"
            let results = try await ditto.store.execute(query: query)

            // Extract user_collections from store field
            var discoveredCollections: [String: Int] = [:]
            for item in results.items {
                if let storeField = item.value["store"] as? [String: Any],
                   let userCollections = storeField["user_collections"] as? [String: Any] {
                    for (collectionName, collectionData) in userCollections {
                        if let collectionInfo = collectionData as? [String: Any],
                           let numDocs = collectionInfo["num_docs"] as? Int {
                            discoveredCollections[collectionName] = numDocs
                        }
                    }
                }
            }

            // Get current collections from __collections
            let collectionsQuery = "SELECT * FROM __collections"
            let collectionsResults = try await ditto.store.execute(query: collectionsQuery)
            let decoder = JSONDecoder()
            let existingCollections = Set(collectionsResults.items.compactMap { item -> String? in
                try? decoder.decode(DittoCollection.self, from: item.jsonData()).name
            })

            // Find collections that exist in __small_peer_info but not in __collections
            let newCollections = discoveredCollections.keys.filter { !existingCollections.contains($0) && !$0.hasPrefix("__") }

            // Register any new collections
            for collectionName in newCollections {
                try? await registerCollection(name: collectionName)
            }

            // If we found new collections or counts, update the UI
            if !newCollections.isEmpty {
                // Trigger a refresh of collections
                let allCollections = (existingCollections.union(newCollections))
                    .filter { !$0.hasPrefix("__") }
                    .sorted()
                    .map { name in
                        DittoCollectionModel(name: name, documentCount: discoveredCollections[name] ?? 0)
                    }

                await self.onCollectionsUpdate?(allCollections)
            }
        } catch {
            // Silently fail - this is a background reconciliation task
            print("Error reconciling collections from __small_peer_info: \(error)")
        }
    }
    
    func setAppState(_ appState: AppState) {
        self.appState = appState
    }
    
    func setOnCollectionsUpdate(_ callback: @escaping ([DittoCollectionModel]) -> Void) {
        self.onCollectionsUpdate = callback
    }
    
    func registerCollection(name: String) async throws {
        guard let ditto = await dittoManager.dittoSelectedApp else {
            throw InvalidStateError(message: "No Ditto selected app available")
        }

        // Register collection in __collections (idempotent operation)
        let query = "INSERT INTO __collections DOCUMENTS (:doc) ON ID CONFLICT DO UPDATE"
        let arguments = ["doc": ["name": name]]
        _ = try await ditto.store.execute(query: query, arguments: arguments)
    }

    func removeCollection(name: String) async throws {
        guard let ditto = await dittoManager.dittoSelectedApp else {
            throw InvalidStateError(message: "No Ditto selected app available")
        }

        // Remove from __collections system collection (unregisters from Edge Studio)
        let query = "DELETE FROM __collections WHERE name = :collectionName"
        let arguments = ["collectionName": name]
        print("DEBUG: Executing DELETE query: \(query) with arguments: \(arguments)")
        let results = try await ditto.store.execute(query: query, arguments: arguments)
        let mutatedCount = results.mutatedDocumentIDs().count
        print("DEBUG: DELETE mutated \(mutatedCount) documents in __collections")
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