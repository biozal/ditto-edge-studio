import DittoSwift
import Foundation

// MARK: - DittoManagerProtocol

/// Surface of `DittoManager` consumed by ViewModels. Defines only what is needed
/// for `MainStudioView.ViewModel` and `ContentView.ViewModel` to drive the
/// session lifecycle (open / close / sync toggle / SDK handle access). Other
/// `DittoManager` APIs (transport config, log level changes, untrusted session
/// caching) stay actor-private and continue to be reached via the singleton.
protocol DittoManagerProtocol: Sendable {
    var dittoSelectedApp: Ditto? { get async }
    var dittoSelectedAppConfig: DittoConfigForDatabase? { get async }
    func setAppState(_ appState: AppState) async
    func hydrateDittoSelectedDatabase(_ databaseConfig: DittoConfigForDatabase) async throws -> Bool
    func closeDittoSelectedDatabase() async
    func selectedDatabaseStartSync() async throws
    func selectedDatabaseStopSync() async
}

// MARK: - QueryServiceProtocol

/// Subset of `QueryService` used by ViewModels: the two execute paths the
/// query editor and attachment-deletion flows call into.
protocol QueryServiceProtocol: Sendable {
    func executeSelectedAppQuery(query: String) async throws -> [String]
    func executeSelectedAppQueryHttp(query: String) async throws -> [String]
    /// SELECT-with-profile variant for the Query editor — captures the
    /// PROFILE envelope alongside the user-facing rows when Collect
    /// Metrics is enabled. MCP / attachment flows keep using the
    /// plain `[String]` method above; they don't need the profile.
    func executeSelectedAppQueryWithProfile(query: String) async throws -> QueryExecutionResult
}

// MARK: - DatabaseRepositoryProtocol

/// Surface of `DatabaseRepository` used by `ContentView.ViewModel`.
protocol DatabaseRepositoryProtocol: Sendable {
    func setAppState(_ appState: AppState) async
    func loadDatabaseConfigs() async throws -> [DittoConfigForDatabase]
    func addDittoAppConfig(_ appConfig: DittoConfigForDatabase) async throws
    func updateDittoAppConfig(_ appConfig: DittoConfigForDatabase) async throws
    func deleteDittoAppConfig(_ appConfig: DittoConfigForDatabase) async throws
    func setOnDittoDatabaseConfigUpdate(_ callback: @escaping @MainActor ([DittoConfigForDatabase]) -> Void) async
}

// MARK: - SubscriptionsRepositoryProtocol

protocol SubscriptionsRepositoryProtocol: Sendable {
    func setAppState(_ appState: AppState) async
    func setOnSubscriptionsUpdate(_ callback: @escaping @MainActor ([DittoSubscription]) -> Void) async
    func loadSubscriptions(for databaseId: String) async throws -> [DittoSubscription]
    func saveDittoSubscription(_ subscription: DittoSubscription) async throws
    func removeDittoSubscription(_ subscription: DittoSubscription) async throws
    func clearCache() async
    func getCachedSubscriptions() async -> [DittoSubscription]
}

// MARK: - SystemRepositoryProtocol

protocol SystemRepositoryProtocol: Sendable {
    func setAppState(_ appState: AppState) async
    func setOnSyncStatusUpdate(
        _ callback: @escaping @MainActor ([SyncStatusInfo], @escaping @Sendable () -> Void) -> Void
    ) async
    func setOnConnectionsUpdate(
        _ callback: @escaping @MainActor (ConnectionsByTransport) -> Void
    ) async
    func registerConnectionsPresenceObserver() async throws
    func invalidateSession() async
    func stopObserver() async
}

// MARK: - HistoryRepositoryProtocol

protocol HistoryRepositoryProtocol: Sendable {
    func setAppState(_ appState: AppState) async
    func setOnHistoryUpdate(_ callback: @escaping @MainActor ([DittoQueryHistory]) -> Void) async
    func loadHistory(for databaseId: String) async throws -> [DittoQueryHistory]
    func saveQueryHistory(_ history: DittoQueryHistory) async throws
    func clearCache() async
}

// MARK: - FavoritesRepositoryProtocol

protocol FavoritesRepositoryProtocol: Sendable {
    func setAppState(_ appState: AppState) async
    func setOnFavoritesUpdate(_ callback: @escaping @MainActor ([DittoQueryHistory]) -> Void) async
    func loadFavorites(for databaseId: String) async throws -> [DittoQueryHistory]
    func saveFavorite(_ favorite: DittoQueryHistory) async throws
    func clearCache() async
}

// MARK: - ObservableRepositoryProtocol

protocol ObservableRepositoryProtocol: Sendable {
    func setAppState(_ appState: AppState) async
    func setOnObservablesUpdate(_ callback: @escaping @MainActor ([DittoObservable]) -> Void) async
    func loadObservers(for databaseId: String) async throws -> [DittoObservable]
    func saveDittoObservable(_ observable: DittoObservable) async throws
    func removeDittoObservable(_ observable: DittoObservable) async throws
    func clearCache() async
}

// MARK: - CollectionsRepositoryProtocol

protocol CollectionsRepositoryProtocol: Sendable {
    func setAppState(_ appState: AppState) async
    func setOnCollectionsUpdate(_ callback: @escaping @MainActor ([DittoCollection]) -> Void) async
    func hydrateCollections() async throws -> [DittoCollection]
    func refreshCollections() async throws -> [DittoCollection]
    func stopObserver() async
}
