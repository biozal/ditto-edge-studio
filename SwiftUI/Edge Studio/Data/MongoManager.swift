//
//  MongoManager.swift
//  Edge Studio
//
//  Created by Aaron LaBeau on 6/10/25.
//

import Foundation
import MongoKitten

enum MongoManagerError: Error {
    case notConnected
}

actor MongoManager: ObservableObject {
    
    var isConnected: Bool = false
    
    var app: DittoApp?
    var connectionString: String = ""
    var mongoDatabase: MongoDatabase?
    
    @Published var collections: [String] = []
    
    private init() {}
    
    static var shared = MongoManager()
    
    func initializeConnection(connectionString: String, dittoApp: DittoApp) async {
        self.app = dittoApp
        do {
            mongoDatabase = try await MongoDatabase.connect(to: connectionString)
            if let collectionsList = try await mongoDatabase?.listCollections() {
                collections = collectionsList.compactMap { $0.name }
                    .filter { !$0.hasPrefix("__ditto_connector_sessions")}
                
                isConnected = true
            }
        } catch {
            self.app?.setError(error)
        }
    }
    
    func getCollectionDocuments(_ collectionName: String) async throws -> [String] {
        guard let mongoDatabase = mongoDatabase else {
            throw MongoManagerError.notConnected
        }
        let collection = mongoDatabase[collectionName]
        let documents = try await collection.find().drain()
        let jsonStrings = documents.map { document in
            String(data: document.makeData(), encoding: .utf8) ?? ""
        }
        return jsonStrings
    }
}
