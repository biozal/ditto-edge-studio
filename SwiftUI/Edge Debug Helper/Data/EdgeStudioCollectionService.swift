//
//  EdgeStudioCollectionService.swift
//  Edge Studio
//
//  Service layer for managing collections in the selected app's __collections system collection
//

import Foundation
import DittoSwift

actor EdgeStudioCollectionService {
    static let shared = EdgeStudioCollectionService()

    private let repository = EdgeStudioCollectionsRepository.shared

    private init() { }

    // MARK: - Collection CRUD Operations

    /// Register a new collection in the __collections system collection
    func registerCollection(name: String) async throws {
        try await repository.registerCollection(name: name)
    }

    /// Remove a collection from the __collections system collection
    func removeCollection(name: String) async throws {
        try await repository.removeCollection(name: name)
    }

    // MARK: - Collection State Management

    /// Hydrate collections and register observer for real-time updates
    /// Note: The repository's hydrateCollections() method both hydrates initial data
    /// and registers an observer for future updates
    func hydrateCollections() async throws -> [DittoCollectionModel] {
        print("🔍 EdgeStudioCollectionService: Calling repository.hydrateCollections()")
        return try await repository.hydrateCollections()
    }

    /// Set the callback for collections updates
    func setOnCollectionsUpdate(_ callback: @escaping ([DittoCollectionModel]) -> Void) async {
        await repository.setOnCollectionsUpdate(callback)
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
