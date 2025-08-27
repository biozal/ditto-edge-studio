import DittoSwift
import Foundation

//Ditto Apps will be called Ditto Database in the future
//This repository is for storing local cache registered
//Ditto Databases (apps) the end user wants to interact with
actor DatabaseRepository {
    static let shared = DatabaseRepository()
    
    private let dittoManager = DittoManager.shared
    private var dittoDatabaseConfigsObserver: DittoStoreObserver?
    private var appState: AppState?
    
    // Store the callback inside the actor
    private var onDittoDatabaseConfigUpdate: (([DittoAppConfig]) -> Void)?
    
    var localAppConfigSubscription: DittoSyncSubscription?
    
    private init() { }
    
    deinit {
        dittoDatabaseConfigsObserver?.cancel()
    }

    func addDittoAppConfig(_ appConfig: DittoAppConfig) async throws {
        let ditto = await dittoManager.dittoLocal
        guard let ditto = ditto else { return }
        
        do {
            let query =
            "INSERT INTO dittoappconfigs INITIAL DOCUMENTS (:newConfig)"
            let arguments: [String: Any] = [
                "newConfig": [
                    "_id": appConfig._id,
                    "name": appConfig.name,
                    "appId": appConfig.appId,
                    "authToken": appConfig.authToken,
                    "authUrl": appConfig.authUrl,
                    "websocketUrl": appConfig.websocketUrl,
                    "httpApiUrl": appConfig.httpApiUrl,
                    "httpApiKey": appConfig.httpApiKey,
                    "mode": appConfig.mode,
                    "allowUntrustedCerts": appConfig.allowUntrustedCerts,
                ]
            ]
            try await ditto.store.execute(
                query: query,
                arguments: arguments
            )
        } catch {
            self.appState?.setError(error)
            throw error
        }
    }
    
    func deleteDittoAppConfig(_ appConfig: DittoAppConfig) async throws {
        let ditto = await dittoManager.dittoLocal
        guard let ditto = ditto else { return }
        
        let query = "DELETE FROM dittoappconfigs WHERE _id = :id"
        let argument = ["id": appConfig._id]
        try await ditto.store.execute(query: query, arguments: argument)
    }
    
    func registerLocalObservers() async throws {
        let ditto = await dittoManager.dittoLocal
        guard let ditto = ditto else { return }
        
        let appStateRef = self.appState  // Capture reference before closure
        
        // Since we're in an actor, the observer callback will handle threading automatically
        dittoDatabaseConfigsObserver = try ditto.store.registerObserver(
            query: """
                SELECT *
                FROM dittoappconfigs
                ORDER BY name
                """
        ) { [weak self] results in
            Task { [weak self] in
                guard let self else { return }
                
                let decoder = JSONDecoder()
                // Create new DittoAppConfig instances
                // This work is now done within the actor's context (background)
                let configs = results.items.compactMap { item in
                    do {
                        return try decoder.decode(
                            DittoAppConfig.self,
                            from: item.jsonData()
                        )
                    } catch {
                        // Handle error
                        if let appStateRef {
                            appStateRef.setError(error)
                        }
                        return nil
                    }
                }
                
                // Call the callback to update the ViewModel's published property
                await self.onDittoDatabaseConfigUpdate?(configs)
            }
        }
    }
    
    func setAppState(_ appState: AppState) {
        self.appState = appState
    }
    
    // Function to set the callback from outside the actor
    func setOnDittoDatabaseConfigUpdate(_ callback: @escaping ([DittoAppConfig]) -> Void) {
        self.onDittoDatabaseConfigUpdate = callback
    }
    
    func setupDatabaseConfigSubscriptions() async throws {
        if let ditto = await DittoManager.shared.dittoLocal {
            //set collection to only sync to local
            let syncScopes = [
                "dittoappconfigs": "LocalPeerOnly",
                "dittosubscriptions": "LocalPeerOnly",
                "dittoobservations": "LocalPeerOnly",
                "dittoqueryfavorites": "LocalPeerOnly",
                "dittoqueryhistory": "LocalPeerOnly",
            ]
            try await ditto.store.execute(
                query:
                    "ALTER SYSTEM SET USER_COLLECTION_SYNC_SCOPES = :syncScopes",
                arguments: ["syncScopes": syncScopes]
            )
            //setup subscription
            self.localAppConfigSubscription = try ditto.sync
                .registerSubscription(
                    query: """
                        SELECT *
                        FROM dittoappconfigs 
                        """
                )
            // Use detached task with utility priority to prevent threading priority inversion
            Task.detached(priority: .utility) {
                try ditto.sync.start()
            }
        }
    }
    
    func stopDatabaseConfigSubscription() async {
        let ditto = await dittoManager.dittoLocal
        guard let ditto = ditto else { return }
        
        if let subscriptionInstance = localAppConfigSubscription {
            subscriptionInstance.cancel()
            // Use detached task with utility priority to prevent threading priority inversion
            await Task.detached(priority: .utility) {
                ditto.sync.stop()
            }.value
        }
        localAppConfigSubscription = nil
    }
    
    func updateDittoAppConfig(_ appConfig: DittoAppConfig) async throws {
        let ditto = await dittoManager.dittoLocal
        guard let ditto = ditto else { return }
        
        do {
            let query =
            "UPDATE dittoappconfigs SET name = :name, appId = :appId, authToken = :authToken, authUrl = :authUrl, websocketUrl = :websocketUrl, httpApiUrl = :httpApiUrl, httpApiKey = :httpApiKey, mode = :mode, allowUntrustedCerts = :allowUntrustedCerts WHERE _id = :_id"
            let arguments: [String: Any] = [
                "_id": appConfig._id,
                "name": appConfig.name,
                "appId": appConfig.appId,
                "authToken": appConfig.authToken,
                "authUrl": appConfig.authUrl,
                "websocketUrl": appConfig.websocketUrl,
                "httpApiUrl": appConfig.httpApiUrl,
                "httpApiKey": appConfig.httpApiKey,
                "mode": appConfig.mode,
                "allowUntrustedCerts": appConfig.allowUntrustedCerts,
            ]
            try await ditto.store.execute(
                query: query,
                arguments: arguments
            )
        } catch {
            self.appState?.setError(error)
            throw error
        }
    }
}
