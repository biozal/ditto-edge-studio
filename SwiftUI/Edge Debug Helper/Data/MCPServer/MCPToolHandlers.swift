#if os(macOS)
import Foundation

// MARK: - Tool Definition

struct MCPTool {
    let name: String
    let description: String
    let inputSchema: [String: Any]
}

// MARK: - MCP Errors

enum MCPError: Error, LocalizedError {
    case unknownTool(String)
    case missingArgument(String)
    case noActiveDatabase
    case executionFailed(String)

    var errorDescription: String? {
        switch self {
        case let .unknownTool(name):
            "Unknown tool: \(name)"
        case let .missingArgument(arg):
            "Missing required argument: \(arg)"
        case .noActiveDatabase:
            "No active database. Select a database in Edge Studio first."
        case let .executionFailed(msg):
            msg
        }
    }
}

// MARK: - Tool Handlers

/// Defines and executes all 9 MCP tools.
enum MCPToolHandlers {
    // MARK: Tool Manifest

    static let allTools: [MCPTool] = [
        MCPTool(
            name: "execute_dql",
            description: "Execute a DQL query against the currently active Ditto database in Edge Studio. Supports SELECT, INSERT, UPDATE, EVICT, and other DQL statements.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "query": [
                        "type": "string",
                        "description": "The DQL query to execute (e.g. 'SELECT * FROM myCollection LIMIT 10')"
                    ]
                ],
                "required": ["query"]
            ]
        ),
        MCPTool(
            name: "list_databases",
            description: "List all Ditto databases configured in Edge Studio (name, ID, and auth mode). Does not include credentials.",
            inputSchema: [
                "type": "object",
                "properties": [String: Any]()
            ]
        ),
        MCPTool(
            name: "get_active_database",
            description: "Get details about the currently active (selected) Ditto database including name, ID, auth mode, and transport configuration.",
            inputSchema: [
                "type": "object",
                "properties": [String: Any]()
            ]
        ),
        MCPTool(
            name: "list_collections",
            description: "List all collections in the active database including document counts and index information.",
            inputSchema: [
                "type": "object",
                "properties": [String: Any]()
            ]
        ),
        MCPTool(
            name: "create_index",
            description: "Create an index on a field in a collection to speed up queries.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "collection": [
                        "type": "string",
                        "description": "The collection name to create the index on"
                    ],
                    "field": [
                        "type": "string",
                        "description": "The field path to index (e.g. 'name', 'address.city')"
                    ]
                ],
                "required": ["collection", "field"]
            ]
        ),
        MCPTool(
            name: "drop_index",
            description: "Drop an existing index by name.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "index_name": [
                        "type": "string",
                        "description": "The index name to drop (e.g. 'idx_myCollection_name')"
                    ]
                ],
                "required": ["index_name"]
            ]
        ),
        MCPTool(
            name: "get_query_metrics",
            description: "Get recent query metrics including execution times, result counts, and EXPLAIN output. Returns up to 200 most recent query records. Only available when metrics are enabled in Settings.",
            inputSchema: [
                "type": "object",
                "properties": [String: Any]()
            ]
        ),
        MCPTool(
            name: "get_sync_status",
            description: "Get the current sync status of the active database: connected peer count, transport configuration, and whether sync is active.",
            inputSchema: [
                "type": "object",
                "properties": [String: Any]()
            ]
        ),
        MCPTool(
            name: "configure_transport",
            description: "Configure transport settings for the active database. Only provided parameters are changed; omitted parameters retain their current values. Stops and restarts sync automatically.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "bluetooth": [
                        "type": "boolean",
                        "description": "Enable or disable Bluetooth LE transport"
                    ],
                    "lan": [
                        "type": "boolean",
                        "description": "Enable or disable LAN (Local Area Network) transport"
                    ],
                    "awdl": [
                        "type": "boolean",
                        "description": "Enable or disable AWDL (Apple Wireless Direct Link) transport"
                    ],
                    "cloud": [
                        "type": "boolean",
                        "description": "Enable or disable cloud sync via WebSocket"
                    ]
                ]
            ]
        ),
        MCPTool(
            name: "insert_documents_from_file",
            description: "Insert documents from a local JSON file into a Ditto collection. The file must contain a JSON array of objects; each object must have an '_id' field. Use mode 'insert' (default) to upsert on conflict, or 'insert_initial' to skip documents whose '_id' already exists. The file must be in the user's Downloads folder (~/Downloads) due to macOS sandbox restrictions.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "file_path": [
                        "type": "string",
                        "description": "Absolute path to the JSON file on the local filesystem (e.g. '/Users/you/tasks.json')"
                    ],
                    "collection": [
                        "type": "string",
                        "description": "Target collection name — letters, numbers, and underscores only"
                    ],
                    "mode": [
                        "type": "string",
                        "enum": ["insert", "insert_initial"],
                        "description": "'insert' upserts on conflict (default). 'insert_initial' skips documents whose _id already exists."
                    ]
                ],
                "required": ["file_path", "collection"]
            ]
        )
    ]

    // MARK: Dispatch

    static func execute(toolName: String, arguments: [String: Any]) async throws -> String {
        switch toolName {
        case "execute_dql": return try await executeDQL(arguments: arguments)
        case "list_databases": return try await listDatabases()
        case "get_active_database": return try await getActiveDatabase()
        case "list_collections": return try await listCollections()
        case "create_index": return try await createIndex(arguments: arguments)
        case "drop_index": return try await dropIndex(arguments: arguments)
        case "get_query_metrics": return try await getQueryMetrics()
        case "get_sync_status": return try await getSyncStatus()
        case "configure_transport": return try await configureTransport(arguments: arguments)
        case "insert_documents_from_file": return try await insertDocumentsFromFile(arguments: arguments)
        default:
            throw MCPError.unknownTool(toolName)
        }
    }

    // MARK: execute_dql

    private static func executeDQL(arguments: [String: Any]) async throws -> String {
        guard let query = arguments["query"] as? String, !query.isEmpty else {
            throw MCPError.missingArgument("query")
        }

        let results = try await QueryService.shared.executeSelectedAppQuery(query: query)

        if results == ["No results found"] || results == ["No Ditto app selected"] {
            return results.joined(separator: "\n")
        }

        // Format as JSON array for structured output
        guard let data = try? JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .withoutEscapingSlashes]),
              let json = String(data: data, encoding: .utf8) else
        {
            return results.joined(separator: "\n")
        }
        return json
    }

    // MARK: list_databases

    private static func listDatabases() async throws -> String {
        let configs = try await DatabaseRepository.shared.loadDatabaseConfigs()

        let safeConfigs = configs.map { config -> [String: Any] in
            [
                "id": config._id,
                "name": config.name,
                "databaseId": config.databaseId,
                "mode": config.mode.rawValue
            ]
        }

        guard let data = try? JSONSerialization.data(withJSONObject: safeConfigs, options: .prettyPrinted),
              let json = String(data: data, encoding: .utf8) else
        {
            return "[]"
        }
        return json
    }

    // MARK: get_active_database

    private static func getActiveDatabase() async throws -> String {
        guard let config = await DittoManager.shared.dittoSelectedAppConfig else {
            throw MCPError.noActiveDatabase
        }

        let info: [String: Any] = [
            "name": config.name,
            "databaseId": config.databaseId,
            "mode": config.mode.rawValue,
            "transport": [
                "bluetoothLE": config.isBluetoothLeEnabled,
                "lan": config.isLanEnabled,
                "awdl": config.isAwdlEnabled,
                "cloudSync": config.isCloudSyncEnabled
            ]
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: info, options: .prettyPrinted),
              let json = String(data: data, encoding: .utf8) else
        {
            return "{}"
        }
        return json
    }

    // MARK: list_collections

    private static func listCollections() async throws -> String {
        let collections = try await CollectionsRepository.shared.refreshCollections()

        let items = collections.map { col -> [String: Any] in
            let indexList = col.indexes.map { idx -> [String: Any] in
                [
                    "name": idx.displayName,
                    "fullName": idx._id,
                    "collection": idx.collection,
                    "fields": idx.fields.map(\.strippingBackticks)
                ]
            }
            return [
                "name": col.name,
                "documentCount": col.documentCount ?? 0,
                "indexes": indexList
            ]
        }

        guard let data = try? JSONSerialization.data(withJSONObject: items, options: .prettyPrinted),
              let json = String(data: data, encoding: .utf8) else
        {
            return "[]"
        }
        return json
    }

    // MARK: create_index

    private static func createIndex(arguments: [String: Any]) async throws -> String {
        guard let collection = arguments["collection"] as? String, !collection.isEmpty else {
            throw MCPError.missingArgument("collection")
        }
        guard let field = arguments["field"] as? String, !field.isEmpty else {
            throw MCPError.missingArgument("field")
        }

        try await CollectionsRepository.shared.createIndex(collection: collection, fieldName: field)

        let safeName = "idx_\(collection)_\(field)"
            .replacingOccurrences(of: ".", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        return "Index '\(safeName)' created successfully on \(collection)(\(field))"
    }

    // MARK: drop_index

    private static func dropIndex(arguments: [String: Any]) async throws -> String {
        guard let indexName = arguments["index_name"] as? String, !indexName.isEmpty else {
            throw MCPError.missingArgument("index_name")
        }

        let results = try await QueryService.shared.executeSelectedAppQuery(
            query: "DROP INDEX \(indexName)"
        )
        let output = results.joined(separator: "\n")

        if output.lowercased().contains("error") {
            return "Failed to drop index '\(indexName)': \(output)"
        }
        return "Index '\(indexName)' dropped successfully"
    }

    // MARK: get_query_metrics

    private static func getQueryMetrics() async throws -> String {
        let isEnabled = UserDefaults.standard.bool(forKey: "metricsEnabled")
        guard isEnabled else {
            return "Query metrics are disabled. Enable them in Settings → General → Metrics."
        }

        let records = await QueryMetricsRepository.shared.allRecords()
        if records.isEmpty {
            return "No query metrics recorded yet. Execute some queries first."
        }

        let items = records.map { record -> [String: Any] in
            [
                "id": record.id.uuidString,
                "timestamp": record.formattedTimestamp,
                "dql": record.dql,
                "executionTimeMs": record.executionTimeMs,
                "formattedTime": record.formattedExecutionTime,
                "resultCount": record.resultCount,
                "usedIndex": record.usedIndex,
                "explainOutput": record.explainOutput
            ]
        }

        guard let data = try? JSONSerialization.data(withJSONObject: items, options: [.prettyPrinted, .withoutEscapingSlashes]),
              let json = String(data: data, encoding: .utf8) else
        {
            return "[]"
        }
        return json
    }

    // MARK: get_sync_status

    private static func getSyncStatus() async throws -> String {
        guard let ditto = await DittoManager.shared.dittoSelectedApp,
              let config = await DittoManager.shared.dittoSelectedAppConfig else
        {
            throw MCPError.noActiveDatabase
        }

        let peerCount = await Task.detached(priority: .utility) {
            ditto.presence.graph.remotePeers.count
        }.value

        let status: [String: Any] = [
            "database": config.name,
            "connectedPeers": peerCount,
            "transport": [
                "bluetoothLE": config.isBluetoothLeEnabled,
                "lan": config.isLanEnabled,
                "awdl": config.isAwdlEnabled,
                "cloudSync": config.isCloudSyncEnabled
            ]
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: status, options: .prettyPrinted),
              let json = String(data: data, encoding: .utf8) else
        {
            return "{}"
        }
        return json
    }

    // MARK: configure_transport

    private static func configureTransport(arguments: [String: Any]) async throws -> String {
        guard let config = await DittoManager.shared.dittoSelectedAppConfig else {
            throw MCPError.noActiveDatabase
        }

        // Apply only the parameters that were provided; fall back to current config
        let newBluetooth = arguments["bluetooth"] as? Bool ?? config.isBluetoothLeEnabled
        let newLan = arguments["lan"] as? Bool ?? config.isLanEnabled
        let newAwdl = arguments["awdl"] as? Bool ?? config.isAwdlEnabled
        let newCloud = arguments["cloud"] as? Bool ?? config.isCloudSyncEnabled

        // Step 1: Stop sync
        await DittoManager.shared.selectedDatabaseStopSync()
        await SystemRepository.shared.stopObserver()

        // Step 2: Apply config
        try await DittoManager.shared.applyTransportConfig(
            isBluetoothLeEnabled: newBluetooth,
            isLanEnabled: newLan,
            isAwdlEnabled: newAwdl,
            isCloudSyncEnabled: newCloud
        )

        // Update persisted config
        config.isBluetoothLeEnabled = newBluetooth
        config.isLanEnabled = newLan
        config.isAwdlEnabled = newAwdl
        config.isCloudSyncEnabled = newCloud
        try await DatabaseRepository.shared.updateDittoAppConfig(config)

        // Step 3: Restart sync
        try await DittoManager.shared.selectedDatabaseStartSync()
        try? await SystemRepository.shared.registerSyncStatusObserver()
        try? await SystemRepository.shared.registerConnectionsPresenceObserver()

        let summary: [String: Any] = [
            "applied": [
                "bluetoothLE": newBluetooth,
                "lan": newLan,
                "awdl": newAwdl,
                "cloudSync": newCloud
            ]
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: summary, options: .prettyPrinted),
              let json = String(data: data, encoding: .utf8) else
        {
            return "Transport configuration applied successfully"
        }
        return json
    }

    // MARK: insert_documents_from_file

    private static func insertDocumentsFromFile(arguments: [String: Any]) async throws -> String {
        guard let filePath = arguments["file_path"] as? String, !filePath.isEmpty else {
            throw MCPError.missingArgument("file_path")
        }
        guard let collection = arguments["collection"] as? String, !collection.isEmpty else {
            throw MCPError.missingArgument("collection")
        }
        let modeString = arguments["mode"] as? String ?? "insert"
        let insertType: ImportService.InsertType = modeString == "insert_initial" ? .initial : .regular

        // Read file on a background thread — never blocks the main thread
        let fileData = try await Task.detached(priority: .utility) {
            do {
                return try Data(contentsOf: URL(fileURLWithPath: filePath))
            } catch {
                throw MCPError.executionFailed("Could not read file '\(filePath)': \(error.localizedDescription)")
            }
        }.value

        let result = try await ImportService.shared.importData(
            documentData: fileData,
            to: collection,
            insertType: insertType
        )

        let summary: [String: Any] = [
            "inserted": result.successCount,
            "failed": result.failureCount,
            "mode": modeString,
            "collection": collection,
            "errors": result.errors
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: summary, options: .prettyPrinted),
              let json = String(data: data, encoding: .utf8) else
        {
            return "Inserted \(result.successCount) documents into '\(collection)', \(result.failureCount) failed."
        }
        return json
    }
}
#endif
