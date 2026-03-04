import Foundation
@testable import Ditto_Edge_Studio

// MARK: - Mock SQLCipher Service

/// Mock SQLCipher service for unit testing
/// Provides in-memory storage without actual database operations
actor MockSQLCipherService {
    
    // MARK: - Mock Storage
    
    var mockConfigs: [SQLCipherService.DatabaseConfigRow] = []
    var mockHistory: [SQLCipherService.HistoryRow] = []
    var mockFavorites: [SQLCipherService.FavoriteRow] = []
    var mockSubscriptions: [SQLCipherService.SubscriptionRow] = []
    var mockObservables: [SQLCipherService.ObservableRow] = []
    
    // MARK: - Call Tracking
    
    var initializeCalled = false
    var insertConfigCallCount = 0
    var updateConfigCallCount = 0
    var deleteConfigCallCount = 0
    var getAllConfigsCallCount = 0
    
    var insertHistoryCallCount = 0
    var insertFavoriteCallCount = 0
    var insertSubscriptionCallCount = 0
    var insertObservableCallCount = 0
    
    // MARK: - Error Simulation
    
    var shouldThrowError = false
    var errorToThrow: Error = MockError.simulatedFailure
    
    // MARK: - Initialization
    
    func initialize() async throws {
        initializeCalled = true
        if shouldThrowError {
            throw errorToThrow
        }
    }
    
    // MARK: - Database Config Operations
    
    func getAllDatabaseConfigs() async throws -> [SQLCipherService.DatabaseConfigRow] {
        getAllConfigsCallCount += 1
        if shouldThrowError {
            throw errorToThrow
        }
        return mockConfigs
    }
    
    func insertDatabaseConfig(_ config: SQLCipherService.DatabaseConfigRow) async throws {
        insertConfigCallCount += 1
        if shouldThrowError {
            throw errorToThrow
        }
        mockConfigs.append(config)
    }
    
    func updateDatabaseConfig(_ config: SQLCipherService.DatabaseConfigRow) async throws {
        updateConfigCallCount += 1
        if shouldThrowError {
            throw errorToThrow
        }
        if let index = mockConfigs.firstIndex(where: { $0._id == config._id }) {
            mockConfigs[index] = config
        }
    }
    
    func deleteDatabaseConfig(id: String) async throws {
        deleteConfigCallCount += 1
        if shouldThrowError {
            throw errorToThrow
        }
        mockConfigs.removeAll { $0._id == id }
    }
    
    // MARK: - History Operations
    
    func getAllHistory(forDatabaseId databaseId: String) async throws -> [SQLCipherService.HistoryRow] {
        if shouldThrowError {
            throw errorToThrow
        }
        return mockHistory.filter { $0.databaseId == databaseId }
    }
    
    func insertHistory(_ history: SQLCipherService.HistoryRow) async throws {
        insertHistoryCallCount += 1
        if shouldThrowError {
            throw errorToThrow
        }
        mockHistory.append(history)
    }
    
    func deleteAllHistory(forDatabaseId databaseId: String) async throws {
        if shouldThrowError {
            throw errorToThrow
        }
        mockHistory.removeAll { $0.databaseId == databaseId }
    }
    
    // MARK: - Favorites Operations
    
    func getAllFavorites(forDatabaseId databaseId: String) async throws -> [SQLCipherService.FavoriteRow] {
        if shouldThrowError {
            throw errorToThrow
        }
        return mockFavorites.filter { $0.databaseId == databaseId }
    }
    
    func insertFavorite(_ favorite: SQLCipherService.FavoriteRow) async throws {
        insertFavoriteCallCount += 1
        if shouldThrowError {
            throw errorToThrow
        }
        mockFavorites.append(favorite)
    }
    
    func deleteFavorite(id: String) async throws {
        if shouldThrowError {
            throw errorToThrow
        }
        mockFavorites.removeAll { $0._id == id }
    }
    
    // MARK: - Subscriptions Operations
    
    func getAllSubscriptions(forDatabaseId databaseId: String) async throws -> [SQLCipherService.SubscriptionRow] {
        if shouldThrowError {
            throw errorToThrow
        }
        return mockSubscriptions.filter { $0.databaseId == databaseId }
    }
    
    func insertSubscription(_ subscription: SQLCipherService.SubscriptionRow) async throws {
        insertSubscriptionCallCount += 1
        if shouldThrowError {
            throw errorToThrow
        }
        mockSubscriptions.append(subscription)
    }
    
    func deleteSubscription(id: String) async throws {
        if shouldThrowError {
            throw errorToThrow
        }
        mockSubscriptions.removeAll { $0._id == id }
    }
    
    // MARK: - Observables Operations
    
    func getAllObservables(forDatabaseId databaseId: String) async throws -> [SQLCipherService.ObservableRow] {
        if shouldThrowError {
            throw errorToThrow
        }
        return mockObservables.filter { $0.databaseId == databaseId }
    }
    
    func insertObservable(_ observable: SQLCipherService.ObservableRow) async throws {
        insertObservableCallCount += 1
        if shouldThrowError {
            throw errorToThrow
        }
        mockObservables.append(observable)
    }
    
    func deleteObservable(id: String) async throws {
        if shouldThrowError {
            throw errorToThrow
        }
        mockObservables.removeAll { $0._id == id }
    }
    
    // MARK: - Test Utilities
    
    func reset() {
        mockConfigs = []
        mockHistory = []
        mockFavorites = []
        mockSubscriptions = []
        mockObservables = []
        
        initializeCalled = false
        insertConfigCallCount = 0
        updateConfigCallCount = 0
        deleteConfigCallCount = 0
        getAllConfigsCallCount = 0
        
        insertHistoryCallCount = 0
        insertFavoriteCallCount = 0
        insertSubscriptionCallCount = 0
        insertObservableCallCount = 0
        
        shouldThrowError = false
    }
}

// MARK: - Mock Keychain Service

/// Mock Keychain service for unit testing
/// Provides in-memory storage without actual keychain operations
actor MockKeychainService {
    
    // MARK: - Mock Storage
    
    var storage: [String: KeychainService.DatabaseCredentials] = [:]
    
    // MARK: - Call Tracking
    
    var saveCallCount = 0
    var loadCallCount = 0
    var deleteCallCount = 0
    var deleteAllCallCount = 0
    
    // MARK: - Error Simulation
    
    var shouldThrowError = false
    var errorToThrow: Error = MockError.simulatedFailure
    
    // MARK: - Operations
    
    func saveDatabaseCredentials(_ id: String, credentials: KeychainService.DatabaseCredentials) throws {
        saveCallCount += 1
        if shouldThrowError {
            throw errorToThrow
        }
        storage[id] = credentials
    }
    
    func loadDatabaseCredentials(_ id: String) throws -> KeychainService.DatabaseCredentials? {
        loadCallCount += 1
        if shouldThrowError {
            throw errorToThrow
        }
        return storage[id]
    }
    
    func deleteDatabaseCredentials(_ id: String) throws {
        deleteCallCount += 1
        if shouldThrowError {
            throw errorToThrow
        }
        storage.removeValue(forKey: id)
    }
    
    func deleteAllDatabaseCredentials() throws {
        deleteAllCallCount += 1
        if shouldThrowError {
            throw errorToThrow
        }
        storage.removeAll()
    }
    
    // MARK: - Test Utilities
    
    func reset() {
        storage.removeAll()
        saveCallCount = 0
        loadCallCount = 0
        deleteCallCount = 0
        deleteAllCallCount = 0
        shouldThrowError = false
    }
}

// MARK: - Mock Query Service

/// Mock Query service for unit testing
/// Simulates query execution without actual Ditto operations
actor MockQueryService {
    
    // MARK: - Mock Storage
    
    var mockResults: [String: String] = [:] // Query -> Result JSON
    var mockErrors: [String: Error] = [:] // Query -> Error to throw
    
    // MARK: - Call Tracking
    
    var executeQueryCallCount = 0
    var lastExecutedQuery: String?
    var lastDatabaseId: String?
    
    // MARK: - Error Simulation
    
    var shouldThrowError = false
    var errorToThrow: Error = MockError.simulatedFailure
    
    // MARK: - Operations
    
    func executeQuery(
        _ query: String,
        databaseId: String,
        localExecution: Bool = true
    ) async throws -> String {
        executeQueryCallCount += 1
        lastExecutedQuery = query
        lastDatabaseId = databaseId
        
        if shouldThrowError {
            throw errorToThrow
        }
        
        // Check for query-specific errors
        if let error = mockErrors[query] {
            throw error
        }
        
        // Return mock result
        if let result = mockResults[query] {
            return result
        }
        
        // Default result
        return """
        {
            "documents": [],
            "mutationSummary": {
                "inserted": 0,
                "updated": 0,
                "deleted": 0
            }
        }
        """
    }
    
    // MARK: - Test Utilities
    
    func setMockResult(for query: String, result: String) {
        mockResults[query] = result
    }
    
    func setMockError(for query: String, error: Error) {
        mockErrors[query] = error
    }
    
    func reset() {
        mockResults.removeAll()
        mockErrors.removeAll()
        executeQueryCallCount = 0
        lastExecutedQuery = nil
        lastDatabaseId = nil
        shouldThrowError = false
    }
}

// MARK: - Mock Errors

enum MockError: Error {
    case simulatedFailure
    case customError(String)
    
    var localizedDescription: String {
        switch self {
        case .simulatedFailure:
            return "Simulated failure for testing"
        case .customError(let message):
            return message
        }
    }
}
