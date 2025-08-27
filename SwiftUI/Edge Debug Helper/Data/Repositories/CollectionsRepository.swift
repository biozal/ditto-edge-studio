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
    private var onCollectionsUpdate: (([String]) -> Void)?
    
    private init() { }
    
    deinit {
        collectionsObserver?.cancel()
    }
    
    func hydrateCollections() async throws -> [String] {
        guard let ditto = await dittoManager.dittoSelectedApp,
              let appState = self.appState else {
            throw InvalidStateError(message: "No Ditto selected app or app state available")
        }
        
        let query = "SELECT * FROM __collections"
        let decoder = JSONDecoder()
        
        do {
            // Hydrate the initial data from the database
            let results = try await ditto.store.execute(query: query)
            let items = results.items.compactMap { item in
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
            
            // Register for any changes in the database
            collectionsObserver = try ditto.store.registerObserver(
                query: query
            ) { [weak self] results in
                Task { [weak self] in
                    guard let self else { return }
                    
                    let items = results.items.compactMap { item in
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
                    
                    // Call the callback to update collections
                    await self.onCollectionsUpdate?(items.map { $0.name })
                }
            }
            
            return items.map { $0.name }
        } catch {
            self.appState?.setError(error)
            throw error
        }
    }
    
    func setAppState(_ appState: AppState) {
        self.appState = appState
    }
    
    func setOnCollectionsUpdate(_ callback: @escaping ([String]) -> Void) {
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