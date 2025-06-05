//
//  DittoManager_Subscription.swift
//  Edge Studio
//
//  Created by Aaron LaBeau on 6/4/25.
//

import Foundation
import DittoSwift

// MARK: Ditto Local DB - Subscriptions
extension DittoManager {
    
    func setupLocalSubscription() async throws {
        if let ditto = dittoLocal {
            //set collection to only sync to local
            let syncScopes = [
                "dittoappconfigs": "LocalPeerOnly",
                "dittosubscriptions": "LocalPeerOnly",
                "dittoobservations": "LocalPeerOnly",
                "dittofavorites": "LocalPeerOnly",
                "dittohistory": "LocalPeerOnly",
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
            Task(priority: .background) {
                try ditto.startSync()
            }
        }
    }
    
    func stopLocalSubscription() {
        if let subscriptionInstance = localAppConfigSubscription {
            subscriptionInstance.cancel()
            dittoLocal?.stopSync()
        }
    }
}
