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
            let query =
                "INSERT INTO dittoobservations DOCUMENTS (:newObservable) ON ID CONFLICT DO MERGE"
            let arguments: [String: Any] = [
                "newObservable": [
                    "_id": observable.id,
                    "name": observable.name,
                    "query": observable.query,
                    "selectedApp_id": selectedAppConfig._id,
                    "lastUpdated": Date().ISO8601Format(),
                    "args": observable.args ?? "",
                ]
            ]
            try await ditto.store.execute(
                query: query,
                arguments: arguments
            )
        }
    }

    func removeDittoObservable(_ observable: DittoObservable) async throws {
        if let ditto = dittoLocal {
            let query = "DELETE FROM dittoobservations WHERE _id = :id"
            let argument = ["id": observable.id]
            try await ditto.store.execute(
                query: query,
                arguments: argument
            )
        }
    }
}
