//
//  DittoManager_Observable.swift
//  Edge Studio
//
//  Created by Aaron LaBeau on 6/4/25.
//

import DittoSwift
import Foundation

// MARK: Ditto Selected App - Observable Operations
extension DittoManager {

    func saveDittoObservable(_ observable: DittoObservable) async throws {
        if let ditto = dittoLocal,
            let selectedAppConfig = dittoSelectedAppConfig
        {
            let dittoObservable = observable
            let query =
                "INSERT INTO dittoobservations DOCUMENTS (:newObservable) ON ID CONFLICT DO UPDATE"
            let arguments: [String: Any] = [
                "newObservable": [
                    "_id": observable.id,
                    "name": observable.name,
                    "query": observable.query,
                    "selectedApp_id": selectedAppConfig._id,
                    "args": observable.args ?? "",
                ]
            ]
            try await ditto.store.execute(
                query: query,
                arguments: arguments
            )
            //handle edge case where observable exists in the cache
            removeDittoObservableFromCache(observable)

            dittoObservables.append(dittoObservable)
        }
    }

    func registerDittoStoreObserver(_ observable: DittoObservable) async throws -> DittoStoreObserver? {
        guard let ditto = dittoSelectedApp,
            let index = dittoObservables.firstIndex(where: {
                $0.id == observable.id
            })
        else {
            throw InvalidStoreState(message: "Observable not found")
        }
        if dittoObservables[index].storeObserver != nil {
            throw InvalidStoreState(message: "Observer already registered")
        }

        //used for calculating the diffs
        let dittoDiffer = DittoDiffer()

        //TODO: fix arguments serialization
        let observer = try ditto.store.registerObserver(
            query: observable.query,
            arguments: [:]
        ) { [weak self] results in
            //required to show the end user when the event fired
            var event = DittoObserveEvent.new(observeId: observable.id)

            let diff = dittoDiffer.diff(results.items)

            event.eventTime = Date().ISO8601Format()

            //set diff information
            event.insertIndexes = Array(diff.insertions)
            event.deletedIndexes = Array(diff.deletions)
            event.updatedIndexes = Array(diff.updates)
            event.movedIndexes = Array(diff.moves)

            event.data = results.items.compactMap { $0.jsonString() }

            Task { [weak self] in
                await self?.addObservableEvent(event)
            }
        }
        dittoObservables[index].storeObserver = observer
        return observer
    }

    func removeDittoStoreObserver(_ observable: DittoObservable) async throws {
        if let index = dittoObservables.firstIndex(where: {
            $0.id == observable.id
        }) {
            dittoObservables[index].storeObserver?.cancel()
            dittoObservables[index].storeObserver = nil
        }
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
                arguments: argument
            )
            removeDittoObservableFromCache(observable)
        }
    }

    private func removeDittoObservableFromCache(_ observable: DittoObservable) {
        if let observer = dittoObservables.first(where: {
            $0.id == observable.id
        }) {
            if let storeObserver = observer.storeObserver {
                storeObserver.cancel()
            }
            dittoObservables.removeAll { $0.id == observable.id }
        }
    }
}
