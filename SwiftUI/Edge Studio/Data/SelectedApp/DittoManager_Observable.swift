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
                
                dittoObservables.append(observable)
                
                //handle edge case where observable exists in the cache
                removeDittoObservableFromCache(observable)
            }
    }
    
    func removeDittoObservable(_ observable: DittoObservable) async throws {
        if let ditto = dittoLocal {
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
