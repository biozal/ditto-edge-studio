//
//  ObserverService.swift
//  Edge Studio
//
//  Service layer for managing Ditto observables (observers)
//

import Foundation
import DittoSwift

actor ObserverService {
    static let shared = ObserverService()

    private let dittoManager = DittoManager.shared
    private let repository = ObservableRepository.shared

    private init() { }

    // MARK: - Observer CRUD Operations

    /// Save or update an observable
    func saveObservable(_ observable: DittoObservable) async throws {
        try await repository.saveDittoObservable(observable)
    }

    /// Delete an observable and clean up its resources
    func deleteObservable(_ observable: DittoObservable) async throws {
        // First, cancel the store observer if it exists
        if let storeObserver = observable.storeObserver {
            storeObserver.cancel()
        }

        // Then delete from repository
        try await repository.removeDittoObservable(observable)
    }

    /// Register (activate) a store observer for an observable
    func registerStoreObserver(
        for observable: DittoObservable,
        onEvent: @escaping (DittoObserveEvent) -> Void
    ) async throws -> DittoStoreObserver {
        guard let ditto = await dittoManager.dittoSelectedApp else {
            throw InvalidStateError(message: "Could not get ditto reference from manager")
        }

        // Parse arguments if they exist
        var arguments: [String: Any?]? = nil
        if let argsString = observable.args, !argsString.isEmpty {
            // Try to parse JSON arguments
            if let data = argsString.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                arguments = json
            }
        }

        // Used for calculating the diffs
        let dittoDiffer = DittoDiffer()

        // Register the observer
        let storeObserver = try ditto.store.registerObserver(
            query: observable.query,
            arguments: arguments
        ) { results in
            // Calculate diffs
            let diffs = dittoDiffer.diff(results.items)

            // Convert results to JSON strings
            let dataStrings = results.items.compactMap { item -> String? in
                let data = item.jsonData()
                return String(data: data, encoding: .utf8)
            }

            // Create observe event
            let event = DittoObserveEvent(
                id: UUID().uuidString,
                observeId: observable.id,
                data: dataStrings,
                insertIndexes: Array(diffs.insertions),
                updatedIndexes: Array(diffs.updates),
                movedIndexes: Array(diffs.moves),
                deletedIndexes: Array(diffs.deletions),
                eventTime: Date().ISO8601Format()
            )

            // Call the callback
            onEvent(event)
        }

        return storeObserver
    }

    /// Remove (deactivate) a store observer
    func removeStoreObserver(_ storeObserver: DittoStoreObserver?) {
        storeObserver?.cancel()
    }

    // MARK: - Observer State Management

    /// Hydrate observables for a specific app
    func hydrateObservables(for selectedAppId: String) async throws -> [DittoObservable] {
        return try await repository.hydrateObservables(for: selectedAppId)
    }

    /// Register repository observer for real-time updates
    func registerObservablesObserver(for selectedAppId: String) async throws {
        try await repository.registerObservablesObserver(for: selectedAppId)
    }

    /// Set the callback for observables updates
    func setOnObservablesUpdate(_ callback: @escaping ([DittoObservable]) -> Void) async {
        await repository.setOnObservablesUpdate(callback)
    }

    /// Set app state for error handling
    func setAppState(_ appState: AppState) async {
        await repository.setAppState(appState)
    }

    /// Stop the repository observer
    func stopObserver() async {
        await repository.stopObserver()
    }
}
