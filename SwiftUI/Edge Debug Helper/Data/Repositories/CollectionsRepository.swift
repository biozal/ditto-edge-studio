//
//  CollectionsRepository.swift
//  Edge Studio
//
//  Created by Assistant on 8/23/25.
//

import DittoSwift
import Foundation

actor CollectionsRepository {
    static let shared = CollectionsRepository()
    
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
            // Hydrate the initial data from the database
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
            let uniqueCollections = Dictionary(grouping: collectionNames, by: { $0.name })
                .compactMap { $0.value.first }
                .sorted { $0.name < $1.name }

            // Create collection models without counts (set to 0)
            let collections = uniqueCollections.map { DittoCollectionModel(name: $0.name, documentCount: 0) }

            // Register for any changes in the database
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

                    // Create collection models without counts (set to 0)
                    let collections = uniqueCollections.map { DittoCollectionModel(name: $0.name, documentCount: 0) }

                    // Call the callback to update collections
                    await self.onCollectionsUpdate?(collections)
                }
            }

            return collections
        } catch {
            self.appState?.setError(error)
            throw error
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