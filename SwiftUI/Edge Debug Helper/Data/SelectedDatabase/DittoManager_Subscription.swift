//
//  DittoManager_Subscription.swift
//  Edge Studio
//
//  Created by Aaron LaBeau on 6/4/25.
//

import DittoSwift
import Foundation

// MARK: Ditto Selected App - Subscription Operations
extension DittoManager {
    
    func saveDittoSubscription(_ subscription: DittoSubscription) async throws {
        if let ditto = dittoLocal,
           let selectedAppConfig = dittoSelectedAppConfig
        {
            let query =
            "INSERT INTO dittosubscriptions DOCUMENTS (:newSubscription) ON ID CONFLICT DO UPDATE"
            var arguments: [String: Any] = [
                "newSubscription": [
                    "_id": subscription.id,
                    "name": subscription.name,
                    "query": subscription.query,
                    "selectedApp_id": selectedAppConfig._id,
                    "args": "",
                ]
            ]
            if let args = subscription.args {
                if var newSub = arguments["newSubscription"] as? [String: Any] {
                    newSub["args"] = args
                    arguments["newSubscription"] = newSub
                }
            }
            try await ditto.store.execute(
                query: query,
                arguments: arguments
            )
            
            //handle edge case where subscription exists in the cache
            removeDittoSubscriptionFromCache(subscription)
            
            //setup the subscription now - need to make it mutable, regiser the subscription
            
            //TODO fix arguments serialization from string to [String: Any]?
            var sub = subscription
            sub.syncSubscription = try dittoSelectedApp?.sync
                .registerSubscription(
                    query: subscription.query
                )
            
            //add to the local cache of observable objects to show in the UI
            dittoSubscriptions.append(sub)
        }
    }
    
    func removeDittoSubscription(_ subscription: DittoSubscription) async throws
    {
        if let ditto = dittoLocal {
            let query = "DELETE FROM dittosubscriptions WHERE _id = :id"
            let argument = ["id": subscription.id]
            try await ditto.store.execute(
                query: query,
                arguments: argument
            )
            removeDittoSubscriptionFromCache(subscription)
        }
    }
    
    private func removeDittoSubscriptionFromCache(
        _ subscription: DittoSubscription
    ) {
        
        //handle edge case where this is an add but it already exists
        if let sub = dittoSubscriptions.first(where: {
            $0.id == subscription.id
        }) {
            if let dittoSub = sub.syncSubscription {
                dittoSub.cancel()
            }
            dittoSubscriptions.removeAll { $0.id == subscription.id }
        }
    }
}
