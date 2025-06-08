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
                var dittoObservable = observable
                let query = "INSERT INTO dittoobservations DOCUMENTS (:newObservable) ON ID CONFLICT DO UPDATE"
                let arguments: [String: Any] = [
                    "newObservable": [
                        "_id": observable.id,
                        "name": observable.name,
                        "query": observable.query,
                        "selectedApp_id": selectedAppConfig._id,
                        "args": observable.args ?? "",
                    ]
                ]
                try await ditto.store.execute(query: query,
                                              arguments: arguments)
                //handle edge case where observable exists in the cache
                removeDittoObservableFromCache(observable)
                
                //register the observer
                dittoObservable.storeObserver = try await registerDittoObservable(observable)
                
                dittoObservables.append(dittoObservable)
            }
    }
    
    private func registerDittoObservable(_  observable: DittoObservable)
        async throws -> DittoStoreObserver? {
            if let ditto = dittoSelectedApp {
                
                //used for calculating the diffs
                let dittoDiffer = DittoDiffer()
                
                //TODO: fix arguments serialization
                let observer = try ditto.store.registerObserver(
                    query: observable.query,
                    arguments: [:]
                ) { [weak self] results in
                    //required to show the end user when the event fired
                    var event =  DittoObserveEvent.new(observeId: observable.id)
                    
                    event.data = results.items.compactMap { $0.jsonString() }
                    let diff = dittoDiffer.diff(results.items)
                    
                    event.eventTime = Date().ISO8601Format()
                    
                    //set diff information
                    event.deleteCount = diff.deletions.count
                    event.insertCount = diff.insertions.count
                    event.updateCount = diff.updates.count
                    event.moveCount = diff.moves.count
                    event.dataCount = results.items.count
                    
                    event.deletedIndexes = Array(diff.deletions)
                    
                    diff.insertions.forEach { index in
                        let item = event.data[index]
                        event.insertedJson.append(item)
                    }
                    
                    diff.updates.forEach { index in
                        let item = event.data[index]
                        event.updatedJson.append(item)
                    }
                  
                    Task { [weak self] in
                        await self?.addObservableEvent(event)
                    }
                }
                return observer
            }
            return nil
    }
    
    private func addObservableEvent(_ event: DittoObserveEvent) async {
        dittoObservableEvents.append(event)
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
