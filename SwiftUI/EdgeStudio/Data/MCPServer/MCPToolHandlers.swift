#if os(macOS)
import Foundation

// MARK: - Tool Definition

/// Immutable tool-manifest entry. `@unchecked Sendable` because `inputSchema`
/// is a constant JSON-schema dictionary built once in `allTools` and never
/// mutated, so sharing across concurrency domains is safe.
struct MCPTool: @unchecked Sendable {
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

/// Defines and executes all 15 MCP tools.
enum MCPToolHandlers {
    // MARK: Tool Manifest

    static let allTools: [MCPTool] = [
        MCPTool(
            name: "execute_dql",
            description: "Execute a DQL query against the currently active Ditto database in Edge Studio. Supports SELECT, INSERT, UPDATE, EVICT, and other DQL statements. By default queries run against the local embedded database. Set transport to 'http' to route through the HTTP API (requires httpApiUrl and httpApiKey configured on the database).",
            inputSchema: [
                "type": "object",
                "properties": [
                    "query": [
                        "type": "string",
                        "description": "The DQL query to execute (e.g. 'SELECT * FROM myCollection LIMIT 10')"
                    ],
                    "transport": [
                        "type": "string",
                        "enum": ["local", "http"],
                        "description": "Execution transport. 'local' (default) uses the embedded Ditto database. 'http' routes through the HTTP API — requires httpApiUrl and httpApiKey to be set on the database configuration."
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
            description: "Get the full configuration of the currently active (selected) Ditto database: name, ID, auth mode, endpoint URLs, transport protocol toggles (Bluetooth LE, LAN, AWDL, cloud sync), log level, and TLS settings. Credentials (token, API key, secret key) are not included.",
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
            description: "Drop an existing index by name. The owning collection is resolved automatically from the database's index metadata; pass 'collection' to disambiguate when several collections have an index with the same name.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "index_name": [
                        "type": "string",
                        "description": "The index name to drop (e.g. 'idx_myCollection_name')"
                    ],
                    "collection": [
                        "type": "string",
                        "description": "Optional collection that owns the index. Required only when the same index name exists on multiple collections."
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
                    ]
                ]
            ]
        ),
        MCPTool(
            name: "insert_documents_from_file",
            description: "Insert documents from a local JSON file into a Ditto collection. The file must contain a JSON array of objects; each object must have an '_id' field. Use mode 'insert' (default) to upsert on conflict, or 'insert_initial' to skip documents whose '_id' already exists. The path must be readable by the app — under the macOS app sandbox, the user's Downloads folder (~/Downloads) is the reliable location; other paths may work if the sandbox permits reading them.",
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
        ),
        MCPTool(
            name: "set_sync",
            description: "Start or stop sync for the currently selected database. Use this to pause sync before bulk operations or resume it after transport configuration changes.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "enabled": [
                        "type": "boolean",
                        "description": "true to start sync, false to stop sync"
                    ]
                ],
                "required": ["enabled"]
            ]
        ),
        MCPTool(
            name: "get_peers",
            description: "Get a one-time snapshot of all currently connected remote peers and their full details — device name, OS, SDK version, connection types, and metadata. Returns an empty peers array if no peers are connected.",
            inputSchema: [
                "type": "object",
                "properties": [String: Any]()
            ]
        ),
        MCPTool(
            name: "list_indexes",
            description: "List all indexes across every collection in the active database. Returns a flat array with each index's name, full name, collection, and indexed field paths. Useful for auditing index coverage without iterating collection by collection.",
            inputSchema: [
                "type": "object",
                "properties": [String: Any]()
            ]
        ),
        MCPTool(
            name: "get_app_logs",
            description: "Read the most recent Edge Studio application log entries (written by Log.info/warning/error/debug). Use the 'filter' parameter to search for specific tags like '[Peers]' or '[Transport]'.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "lines": [
                        "type": "integer",
                        "description": "Maximum number of most-recent log lines to return (default: 200)"
                    ],
                    "filter": [
                        "type": "string",
                        "description": "Case-insensitive substring to filter log lines (e.g. '[Peers]', 'error')"
                    ]
                ]
            ]
        ),
        MCPTool(
            name: "get_ditto_logs",
            description: "Read Ditto SDK log entries from the active database's log files (.log and .log.gz). Returns structured JSON with timestamp, level, component, and message fields.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "lines": [
                        "type": "integer",
                        "description": "Maximum number of most-recent entries to return (default: 200)"
                    ],
                    "filter": [
                        "type": "string",
                        "description": "Case-insensitive substring filter on the message field"
                    ],
                    "level": [
                        "type": "string",
                        "enum": ["error", "warning", "info", "debug", "verbose"],
                        "description": "Minimum log level to include (default: all levels)"
                    ]
                ]
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
        case "set_sync": return try await setSync(arguments: arguments)
        case "get_peers": return try await getPeers()
        case "list_indexes": return try await listIndexes()
        case "get_app_logs": return try await getAppLogs(arguments: arguments)
        case "get_ditto_logs": return try await getDittoLogs(arguments: arguments)
        default:
            throw MCPError.unknownTool(toolName)
        }
    }

    // MARK: execute_dql

    private static func executeDQL(arguments: [String: Any]) async throws -> String {
        guard let query = arguments["query"] as? String, !query.isEmpty else {
            throw MCPError.missingArgument("query")
        }

        let transport = arguments["transport"] as? String ?? "local"

        if transport == "http" {
            // HTTP path — validate config before attempting the call
            guard let config = await DittoManager.shared.dittoSelectedAppConfig else {
                throw MCPError.noActiveDatabase
            }
            let httpUrl = config.httpApiUrl
            let httpKey = config.httpApiKey
            guard !httpUrl.isEmpty, !httpKey.isEmpty else {
                let errorResponse: [String: Any] = [
                    "error": "http_not_configured",
                    "message": "You asked to run this via HTTP, but this database hasn't been introduced to the cloud yet. Add httpApiUrl and httpApiKey to this database's configuration — then it'll know where to show up.",
                    "hint": "Open database configuration → set httpApiUrl and httpApiKey"
                ]
                guard let data = try? JSONSerialization.data(withJSONObject: errorResponse, options: .prettyPrinted),
                      let json = String(data: data, encoding: .utf8) else
                {
                    return "{\"error\": \"http_not_configured\"}"
                }
                return json
            }
            let results = try await QueryService.shared.executeSelectedAppQueryHttp(query: query)
            return formatQueryResults(results)
        } else {
            // EXISTING local path — unchanged
            let results = try await QueryService.shared.executeSelectedAppQuery(query: query)
            return formatQueryResults(results)
        }
    }

    /// Formats DQL result strings into a JSON array response.
    private static func formatQueryResults(_ results: [String]) -> String {
        if results == ["No results found"] || results == ["No Ditto app selected"] {
            return results.joined(separator: "\n")
        }
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
            "url": config.url,
            "httpApiUrl": config.httpApiUrl,
            "httpApiConfigured": !config.httpApiUrl.isEmpty && !config.httpApiKey.isEmpty,
            "allowUntrustedCerts": config.allowUntrustedCerts,
            "logLevel": config.logLevel,
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

        // Trim before use so the reported name matches the one the repository
        // actually creates (the repository trims field names before naming).
        let trimmedField = field.trimmingCharacters(in: .whitespaces)
        let fields = [IndexField(name: trimmedField, ascending: true)]
        let safeName = CollectionsRepository.makeIndexName(collection: collection, fields: fields)

        // CREATE INDEX IF NOT EXISTS is an idempotent no-op when an identical
        // index already exists — detect that case so the message is accurate.
        // A same-named index with a different definition still throws from the
        // repository, so pre-checking does not mask the conflict error.
        // Match via indexMatches (known-prefix strip), not displayName, so
        // collection names containing dots compare correctly.
        let alreadyExists = try await CollectionsRepository.shared.refreshCollections()
            .first { $0.name == collection }?
            .indexes.contains { Self.indexMatches(_id: $0._id, collection: collection, name: safeName) } ?? false

        try await CollectionsRepository.shared.createIndex(collection: collection, fields: fields)

        if alreadyExists {
            return "Index '\(safeName)' already exists on \(collection)(\(trimmedField)) — no changes made"
        }
        return "Index '\(safeName)' created successfully on \(collection)(\(trimmedField))"
    }

    // MARK: drop_index

    private static func dropIndex(arguments: [String: Any]) async throws -> String {
        guard let indexName = arguments["index_name"] as? String, !indexName.isEmpty else {
            throw MCPError.missingArgument("index_name")
        }
        let requestedCollection = arguments["collection"] as? String

        // DQL requires DROP INDEX <name> ON <collection> — resolve the owning
        // collection from the index metadata (system:indexes stores _id as
        // "collection.indexName"). Match by bare name or full _id via
        // indexMatches — DittoIndex.displayName strips at the FIRST dot and
        // would mis-match when the collection name itself contains dots.
        let matches = try await CollectionsRepository.shared.refreshCollections()
            .flatMap { col in col.indexes.map { (collection: col.name, index: $0) } }
            .filter { Self.indexMatches(_id: $0.index._id, collection: $0.collection, name: indexName) }

        let candidates = requestedCollection.map { wanted in
            matches.filter { $0.collection == wanted }
        } ?? matches

        guard let match = candidates.first else {
            if let requestedCollection, !matches.isEmpty {
                throw MCPError.executionFailed(
                    "Index '\(indexName)' does not exist on collection '\(requestedCollection)' "
                        + "(found on: \(matches.map(\.collection).sorted().joined(separator: ", ")))"
                )
            }
            throw MCPError.executionFailed(
                "Index '\(indexName)' not found in the active database. "
                    + "Use list_indexes to see available indexes."
            )
        }
        guard candidates.count == 1 else {
            let owners = candidates.map(\.collection).sorted().joined(separator: ", ")
            throw MCPError.executionFailed(
                "Index '\(indexName)' exists on multiple collections (\(owners)). "
                    + "Pass the 'collection' argument to disambiguate."
            )
        }

        // Derive the bare index name by stripping the known "<collection>."
        // prefix from the stored _id. DittoIndex.displayName strips at the
        // FIRST dot, which corrupts the name when the collection itself
        // contains dots (_id "my.col.idx_x" → displayName "col.idx_x").
        let bareIndexName = Self.indexNameByStrippingCollectionPrefix(
            _id: match.index._id,
            collection: match.collection
        )

        let results = try await QueryService.shared.executeSelectedAppQuery(
            query: "DROP INDEX \(quoteIdentifier(bareIndexName)) ON \(quoteIdentifier(match.collection))"
        )
        let output = results.joined(separator: "\n")

        if output.lowercased().contains("error") {
            return "Failed to drop index '\(indexName)': \(output)"
        }
        return "Index '\(indexName)' dropped successfully from '\(match.collection)'"
    }

    /// Backtick-quotes a single DQL identifier, escaping embedded backticks by
    /// doubling (mirrors `CollectionsRepository.quoteIdentifier`, which is not
    /// shared with this file).
    private static func quoteIdentifier(_ name: String) -> String {
        "`\(name.replacingOccurrences(of: "`", with: "``"))`"
    }

    /// Derives the bare index name from a `system:indexes` `_id` of the form
    /// `"<collection>.<indexName>"` by stripping the known collection prefix.
    /// Unlike `DittoIndex.displayName` (which strips at the FIRST dot), this
    /// is correct when the collection name itself contains dots.
    static func indexNameByStrippingCollectionPrefix(_id: String, collection: String) -> String {
        let prefix = "\(collection)."
        if _id.hasPrefix(prefix) {
            return String(_id.dropFirst(prefix.count))
        }
        // Unexpected format — fall back to the first-dot strip (displayName).
        guard let dot = _id.firstIndex(of: ".") else { return _id }
        return String(_id[_id.index(after: dot)...])
    }

    /// True when `name` refers to the index stored as `_id` on `collection`,
    /// accepting either the full `_id` ("my.col.idx_x") or the bare index
    /// name ("idx_x"). Uses the known-prefix strip, so it stays correct when
    /// the collection name contains dots (where `DittoIndex.displayName`
    /// strips at the first dot and mis-matches).
    static func indexMatches(_id: String, collection: String, name: String) -> Bool {
        _id == name
            || indexNameByStrippingCollectionPrefix(_id: _id, collection: collection) == name
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

        // `remotePeers` is the FULL MESH, including peers this device has never
        // communicated with (docs/PRESENCE_GRAPH.md). Reporting that count as
        // "connectedPeers" inflated it and made this tool disagree with the app's own
        // peers screen, which has always filtered correctly.
        let (directPeerCount, meshPeerCount) = await Task.detached(priority: .utility) {
            let graph = ditto.presence.graph
            let localKey = graph.localPeer.peerKeyString
            let direct = graph.remotePeers.count { peer in
                peer.connections.contains { $0.peer1 == localKey || $0.peer2 == localKey }
            }
            return (direct, graph.remotePeers.count)
        }.value

        let status: [String: Any] = [
            "database": config.name,
            // Peers with a link to THIS device. Both counts are reported: an agent
            // debugging a mesh wants to know the difference between "nobody is talking
            // to me" and "I can see a mesh but reach none of it through my own links".
            "connectedPeers": directPeerCount,
            "meshPeers": meshPeerCount,
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

        // Step 1: Stop sync
        await DittoManager.shared.selectedDatabaseStopSync()
        await SystemRepository.shared.stopObserver()

        // Step 2: Apply config
        try await DittoManager.shared.applyTransportConfig(
            isBluetoothLeEnabled: newBluetooth,
            isLanEnabled: newLan,
            isAwdlEnabled: newAwdl
        )

        // Update persisted config. `DittoConfigForDatabase` is `@unchecked Sendable`
        // under the contract that its properties are only ever *mutated* on the
        // MainActor (actors/repositories read but never write them). This handler
        // runs in a nonisolated async context, so the mutation must hop to the
        // MainActor to avoid racing the @MainActor SwiftUI views that read these
        // same properties. See DittoConfigForDatabase's Sendable note.
        await MainActor.run {
            config.isBluetoothLeEnabled = newBluetooth
            config.isLanEnabled = newLan
            config.isAwdlEnabled = newAwdl
        }
        try await DatabaseRepository.shared.updateDittoAppConfig(config)

        // Step 3: Restart sync
        // Restarting sync re-applies the Advanced Configuration and is fail-closed on
        // sync scopes, so it can throw. Restart the observers regardless — otherwise a
        // scope failure leaves the session with sync off AND no observers running.
        var syncStartError: Error?
        do {
            try await DittoManager.shared.selectedDatabaseStartSync()
        } catch {
            syncStartError = error
        }
        try? await SystemRepository.shared.registerSyncStatusObserver()
        try? await SystemRepository.shared.registerConnectionsPresenceObserver()
        if let syncStartError {
            throw syncStartError
        }

        let summary: [String: Any] = [
            "applied": [
                "bluetoothLE": newBluetooth,
                "lan": newLan,
                "awdl": newAwdl
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

    // MARK: set_sync

    private static func setSync(arguments: [String: Any]) async throws -> String {
        guard let enabled = arguments["enabled"] as? Bool else {
            throw MCPError.missingArgument("enabled")
        }
        guard await DittoManager.shared.dittoSelectedApp != nil else {
            throw MCPError.noActiveDatabase
        }

        if enabled {
            try await DittoManager.shared.selectedDatabaseStartSync()
            let result: [String: Any] = ["sync": "started", "enabled": true]
            guard let data = try? JSONSerialization.data(withJSONObject: result, options: .prettyPrinted),
                  let json = String(data: data, encoding: .utf8) else
            {
                return "{\"sync\": \"started\", \"enabled\": true}"
            }
            return json
        } else {
            await DittoManager.shared.selectedDatabaseStopSync()
            let result: [String: Any] = ["sync": "stopped", "enabled": false]
            guard let data = try? JSONSerialization.data(withJSONObject: result, options: .prettyPrinted),
                  let json = String(data: data, encoding: .utf8) else
            {
                return "{\"sync\": \"stopped\", \"enabled\": false}"
            }
            return json
        }
    }

    // MARK: get_peers

    private static func getPeers() async throws -> String {
        guard await DittoManager.shared.dittoSelectedApp != nil else {
            throw MCPError.noActiveDatabase
        }

        let peers = await SystemRepository.shared.fetchPeersOnce()

        let output: [String: Any] = [
            "peers": peers,
            "count": peers.count
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: output, options: .prettyPrinted),
              let json = String(data: data, encoding: .utf8) else
        {
            return "{\"peers\": [], \"count\": 0}"
        }
        return json
    }

    // MARK: get_app_logs

    private static func getAppLogs(arguments: [String: Any]) async throws -> String {
        let maxLines = arguments["lines"] as? Int ?? 200
        let filterStr = (arguments["filter"] as? String ?? "").lowercased()

        let logFiles = LoggingService.shared.getAllLogFiles()
        var allLines: [String] = []
        for url in logFiles.reversed() { // reversed: oldest file first → chronological
            if let content = try? String(contentsOf: url, encoding: .utf8) {
                allLines.append(contentsOf: content.components(separatedBy: "\n")
                    .filter { !$0.isEmpty })
            }
        }

        let filtered = filterStr.isEmpty
            ? allLines
            : allLines.filter { $0.lowercased().contains(filterStr) }

        return Array(filtered.suffix(maxLines)).joined(separator: "\n")
    }

    // MARK: get_ditto_logs

    private static func getDittoLogs(arguments: [String: Any]) async throws -> String {
        let maxLines = arguments["lines"] as? Int ?? 200
        let filterStr = (arguments["filter"] as? String ?? "").lowercased()
        let levelStr = (arguments["level"] as? String ?? "").lowercased()

        guard let persistenceDir = await DittoManager.shared.activePersistenceDirectory else {
            throw MCPError.noActiveDatabase
        }

        // `parseDittoLogs`, NOT `parseDirectory`. The SDK writes to
        // `<persistenceDir>/ditto_logs/`, and `parseDirectory` is non-recursive — so
        // handing it the persistence root made this tool return `[]` on every build,
        // silently, for as long as it has shipped. The app's own log viewer already
        // probed for the subdirectory (`LoggingDetailView.exportDittoSDKLogs`); this
        // handler was the one reader that never got the same treatment.
        let entries = await Task.detached(priority: .utility) {
            LogFileParser.parseDittoLogs(persistenceDirectory: persistenceDir)
        }.value

        // An absent log directory is a real state (a database opened moments ago), and
        // is worth saying out loud rather than returning an empty array that reads
        // exactly like "this database logged nothing".
        if entries.isEmpty, LogFileParser.sdkLogDirectory(in: persistenceDir) == nil {
            return "No SDK log directory found under \(persistenceDir.path) — "
                + "expected one of \(LogFileParser.sdkLogDirectoryNames.joined(separator: ", "))."
        }

        // Level ordering (higher = more severe): error=4, warning=3, info=2, debug=1, verbose=0
        let levelOrder: [String: Int] = ["verbose": 0, "debug": 1, "info": 2, "warning": 3, "error": 4]
        let minOrder = levelOrder[levelStr] ?? 0

        var filtered = entries.filter { entry in
            let entryOrder = levelOrder[entry.level.storageString] ?? 0
            guard entryOrder >= minOrder else { return false }
            guard filterStr.isEmpty || entry.message.lowercased().contains(filterStr) else { return false }
            return true
        }
        filtered = Array(filtered.suffix(maxLines))

        let formatter = ISO8601DateFormatter()
        let dicts: [[String: Any]] = filtered.map { entry in [
            "timestamp": formatter.string(from: entry.timestamp),
            "level": entry.level.storageString,
            "component": "\(entry.component)",
            "message": entry.message
        ] }

        guard let data = try? JSONSerialization.data(withJSONObject: dicts, options: .prettyPrinted),
              let json = String(data: data, encoding: .utf8) else { return "[]" }
        return json
    }

    // MARK: list_indexes

    private static func listIndexes() async throws -> String {
        guard await DittoManager.shared.dittoSelectedApp != nil else {
            return "[]"
        }

        let collections = try await CollectionsRepository.shared.refreshCollections()

        let allIndexes = collections.flatMap { col in
            col.indexes.map { idx -> [String: Any] in
                [
                    "name": idx.displayName,
                    "fullName": idx._id,
                    "collection": idx.collection,
                    "fields": idx.fields.map(\.strippingBackticks)
                ]
            }
        }

        guard let data = try? JSONSerialization.data(withJSONObject: allIndexes, options: .prettyPrinted),
              let json = String(data: data, encoding: .utf8) else
        {
            return "[]"
        }
        return json
    }
}
#endif
