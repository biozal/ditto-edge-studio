//
//  HistoryService.swift
//  Edge Studio
//
//  Service layer for managing query history.
//  Handles all business logic for recording and retrieving query history.
//

import Foundation

/// Service that manages query history operations
@MainActor
class HistoryService {
    static let shared = HistoryService()

    private let repository = HistoryRepository.shared

    private init() {}

    /// Records a query execution to history
    /// Records every execution, regardless of whether the query is unique
    /// - Parameters:
    ///   - query: The query string to record
    ///   - appState: AppState for error handling
    func recordQueryExecution(_ query: String, appState: AppState) async {
        // Skip empty queries
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        let queryHistory = DittoQueryHistory(
            id: UniqueIDGenerator.generateHistoryID(),
            query: query,
            createdDate: Date().ISO8601Format()
        )

        do {
            // Always insert a new record for every execution
            try await repository.insertQueryHistory(queryHistory)
        } catch {
            appState.setError(error)
        }
    }

    /// Loads all query history for the current app
    /// - Returns: Array of query history items, sorted by date (most recent first)
    func loadHistory() async throws -> [DittoQueryHistory] {
        return try await repository.hydrateQueryHistory()
    }

    /// Deletes a specific query history entry
    /// - Parameter id: The ID of the history entry to delete
    func deleteHistoryEntry(_ id: String) async throws {
        try await repository.deleteQueryHistory(id)
    }

    /// Clears all query history for the current app
    func clearAllHistory() async throws {
        try await repository.clearQueryHistory()
    }

    /// Sets up a callback to be notified when history changes
    /// - Parameter callback: Closure to call when history is updated
    func setOnHistoryUpdate(_ callback: @escaping ([DittoQueryHistory]) -> Void) async {
        await repository.setOnHistoryUpdate(callback)
    }

    /// Sets the app state for error handling
    /// - Parameter appState: The AppState instance
    func setAppState(_ appState: AppState) async {
        await repository.setAppState(appState)
    }

    /// Stops observing history changes
    func stopObserving() async {
        await repository.stopObserver()
    }
}
