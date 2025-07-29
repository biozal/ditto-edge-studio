//
//  DataManager_DittoAppConfig.swift
//  Edge Studio
//
//  Created by Aaron LaBeau on 6/4/25.
//

import DittoSwift
import Foundation

// MARK: DittoAppConfig Operations
extension DittoManager {
    
    func registerLocalObservers() throws {
        if let ditto = dittoLocal {
            let appStateRef = self.appState  // Capture reference before closure
            localAppConfigsObserver = try ditto.store.registerObserver(
                query: """
                    SELECT *
                    FROM dittoappconfigs
                    ORDER BY name
                    """
            ) { [weak self] results in
                guard let self else { return }
                let decoder = JSONDecoder()
                // Create new DittoAppConfig instances and update the published property
                let configs = results.items.compactMap { item in
                    do {
                        return try decoder.decode(
                            DittoAppConfig.self,
                            from: item.jsonData()
                        )
                    } catch {
                        // Use Task to access actor-isolated properties
                        if let appStateRef {
                            appStateRef.setError(error)
                        }
                        return nil
                    }
                }
                // need to update in a task with async so that this will
                // be published to the UI thread
                Task { [weak self] in
                    await self?.setDittoAppConfigs(configs)
                }
                
            }
        }
    }
    
    private func setDittoAppConfigs(_ configs: [DittoAppConfig]) async {
        self.dittoAppConfigs = configs
    }
    
    func addDittoAppConfig(_ appConfig: DittoAppConfig) async throws {
        do {
            if let ditto = dittoLocal {
                let query =
                "INSERT INTO dittoappconfigs INITIAL DOCUMENTS (:newConfig)"
                let arguments = [
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
                        "mongoDbConnectionString": appConfig.mongoDbConnectionString
                    ]
                ]
                try await ditto.store.execute(
                    query: query,
                    arguments: arguments
                )
            }
        } catch {
            self.appState?.setError(error)
        }
    }
    
    func deleteDittoAppConfig(_ appConfig: DittoAppConfig) async throws {
        if let ditto = dittoLocal {
            let query = "DELETE FROM dittoappconfigs WHERE _id = :id"
            let argument = ["id": appConfig._id]
            try await ditto.store.execute( query: query, arguments: argument )
        }
    }
    
    func updateDittoAppConfig(_ appConfig: DittoAppConfig) async throws {
        do {
            if let ditto = dittoLocal {
                let query =
                "UPDATE dittoappconfigs SET name = :name, appId = :appId, authToken = :authToken, authUrl = :authUrl, websocketUrl = :websocketUrl, httpApiUrl = :httpApiUrl, httpApiKey = :httpApiKey, mode = :mode, mongoDbConnectionString = :mongoDbConnectionString WHERE _id = :_id"
                let arguments = [
                    "_id": appConfig._id,
                    "name": appConfig.name,
                    "appId": appConfig.appId,
                    "authToken": appConfig.authToken,
                    "authUrl": appConfig.authUrl,
                    "websocketUrl": appConfig.websocketUrl,
                    "httpApiUrl": appConfig.httpApiUrl,
                    "httpApiKey": appConfig.httpApiKey,
                    "mode": appConfig.mode,
                    "mongoDbConnectionString": appConfig.mongoDbConnectionString
                ]
                try await ditto.store.execute(
                    query: query,
                    arguments: arguments
                )
            }
        } catch {
            self.appState?.setError(error)
        }
    }
}
