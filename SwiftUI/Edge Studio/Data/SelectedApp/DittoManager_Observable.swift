//
//  DittoManager_Observable.swift
//  Edge Studio
//
//  Created by Aaron LaBeau on 6/4/25.
//

import Foundation
import DittoSwift

// MARK: Ditto Selected App - Observable Operations
extension DittoManager {
    
    func activateDittoObservable(_ observable: DittoObservable) async throws {
        
        //calculate if we have a dittoIntialObservationData set, if not we need to load that so we can compare changes
        //that were observed
        
        //create a new store observer
        
        
    }
    
    func deactivateDittoObservable(_ observable: DittoObservable) async throws {
        //deactivate the store observer
        
    }
    
    func saveDittoObservable(_ observable: DittoObservable) async throws {
            if let ditto = dittoLocal,
               let selectedAppConfig = dittoSelectedAppConfig {
                let query = "INSERT INTO dittoobservations DOCUMENTS (:newObservable) ON ID CONFLICT DO UPDATE"
                var arguments: [String: Any] = [
                    "newObservable": [
                        "_id": observable.id,
                        "name": observable.name,
                        "query": observable.query,
                        "selectedApp_id": selectedAppConfig._id,
                        "args": "",
                    ]
                ]
                if let args = observable.args {
                    arguments["args"] = args
                }
                try await ditto.store.execute(query: query,
                                              arguments: arguments)
                
                //handle edge case where observable exists in the cache
                removeDittoObservableFromCache(observable)
                
                dittoObservables.append(observable)
            }
    }
    
    func removeDittoObservable(_ observable: DittoObservable) async throws {
        if let ditto = dittoLocal {
            
            //cancel the store observer if it exists
            if let storeObserver = observable.storeObserver {
                storeObserver.cancel()
            }
                
            let query = "DELETE FROM dittoobservations WHERE _id = :id"
            let argument = ["id": observable.id]
            try await ditto.store.execute(
                query: query,
                arguments: argument)
            removeDittoObservableFromCache(observable)
        }
    }
    
    private func removeDittoObservableFromCache(_ observable: DittoObservable) {
        if let observer = dittoObservables.first(where: { $0.id == observable.id }) {
            if let storeObserver = observer.storeObserver {
                storeObserver.cancel()
            }
            dittoObservables.removeAll{ $0.id == observable.id }
        }
    }
}
