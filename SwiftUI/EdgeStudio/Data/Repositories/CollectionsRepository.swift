import DittoSwift
import Foundation

actor CollectionsRepository {
    static let shared = CollectionsRepository()

    private let dittoManager = DittoManager.shared
    private var appState: AppState?
    private var collectionsObserver: DittoStoreObserver?

    // Store the callback inside the actor
    private var onCollectionsUpdate: (@MainActor @Sendable ([DittoCollection]) -> Void)?
    private let decoder = JSONDecoder()

    private init() {}

    // No deinit: this is a singleton actor (`static let shared`), so it never
    // deallocates — observer cleanup happens via stopObserver() at session close.

    func hydrateCollections() async throws -> [DittoCollection] {
        guard let ditto = await dittoManager.dittoSelectedApp,
              let appState else
        {
            throw InvalidStateError(message: "No Ditto selected app or app state available")
        }

        let query = "SELECT * FROM __collections"

        do {
            // Hydrate the initial data from the database
            let results = try await ditto.store.execute(query: query)
            var collections = results.items.compactMap { item in
                do {
                    // Serialize from the item's value dictionary (catchable)
                    // instead of item.jsonData(), which traps on documents it
                    // can't serialize.
                    let cleaned = item.value.compactMapValues { $0 }
                    let json = try JSONSerialization.data(withJSONObject: cleaned, options: [.fragmentsAllowed])
                    let decodedItem = try decoder.decode(DittoCollection.self, from: json)
                    item.dematerialize()
                    return decodedItem
                } catch {
                    item.dematerialize()
                    Task { @MainActor in appState.setError(error) }
                    return nil
                }
            }.filter { !$0.name.hasPrefix("__") } // Filter out system collections

            // Fetch document counts as dictionary: [collectionName: count]
            let counts = try await fetchDocumentCounts(for: collections)

            // Enrich each collection with its count by looking up the collection name in the dictionary
            for i in collections.indices {
                let collectionName = collections[i].name
                collections[i].documentCount = counts[collectionName]
            }

            // Fetch indexes and attach to each collection
            let indexesByCollection = try await fetchIndexes(for: collections)
            for i in collections.indices {
                collections[i].indexes = indexesByCollection[collections[i].name] ?? []
            }

            // Register for any changes in the database. Cancel the previous
            // observer first: hydrateCollections is reachable twice per
            // session (MainStudioViewModel.performLoad and
            // ImportDataView.loadExistingCollections), and re-assigning
            // without cancelling leaks the first observer and double-fans-out
            // every __collections change (same stop-before-replace discipline
            // as SystemRepository).
            collectionsObserver?.cancel()
            collectionsObserver = try ditto.store.registerObserver(query: query) { [weak self] results in
                Task { [weak self] in
                    guard let self else { return }

                    var updatedCollections = results.items.compactMap { item -> DittoCollection? in
                        do {
                            let cleaned = item.value.compactMapValues { $0 }
                            let json = try JSONSerialization.data(withJSONObject: cleaned, options: [.fragmentsAllowed])
                            let decodedItem = try self.decoder.decode(DittoCollection.self, from: json)
                            item.dematerialize()
                            return decodedItem
                        } catch {
                            item.dematerialize()
                            Task { @MainActor in appState.setError(error) }
                            return nil
                        }
                    }.filter { !$0.name.hasPrefix("__") } // Filter out system collections

                    // Fetch counts on every update as dictionary: [collectionName: count]
                    if let counts = try? await fetchDocumentCounts(for: updatedCollections) {
                        // Match counts to collections by name (dictionary lookup)
                        for i in updatedCollections.indices {
                            let collectionName = updatedCollections[i].name
                            updatedCollections[i].documentCount = counts[collectionName]
                        }
                    }

                    // Fetch indexes and attach to each collection
                    if let indexesByCollection = try? await fetchIndexes(for: updatedCollections) {
                        for i in updatedCollections.indices {
                            updatedCollections[i].indexes = indexesByCollection[updatedCollections[i].name] ?? []
                        }
                    }

                    // Call the callback to update collections on main actor
                    await notifyCollectionsUpdate(updatedCollections.sorted { $0.name < $1.name })
                }
            }

            return collections.sorted { $0.name < $1.name }
        } catch {
            await self.appState?.setError(error)
            throw error
        }
    }

    private func fetchIndexes(for collections: [DittoCollection]) async throws -> [String: [DittoIndex]] {
        guard let ditto = await dittoManager.dittoSelectedApp else {
            throw InvalidStateError(message: "No Ditto selected app available")
        }
        let results = try await ditto.store.execute(query: "SELECT * FROM system:indexes")
        var indexesByCollection: [String: [DittoIndex]] = [:]
        for item in results.items {
            // Use the item's value dictionary directly instead of item.jsonData(),
            // which traps on documents it can't serialize.
            let json = item.value.compactMapValues { $0 }
            item.dematerialize()
            guard let id = json["_id"] as? String,
                  let collection = json["collection"] as? String else
            {
                Log.warning("Skipping index item: missing _id or collection field")
                continue
            }

            // SDK returns fields as [{"direction": "asc", "key": ["fieldName"]}]
            // (older SDKs wrapped segments in backticks — parseIndexKeys strips them).
            // Keep the full IndexField so consumers can show ASC/DESC direction.
            let fields = Self.parseIndexKeys(from: json)

            let index = DittoIndex(id: id, collection: collection, fields: fields)
            indexesByCollection[collection, default: []].append(index)
        }
        return indexesByCollection
    }

    private func fetchDocumentCounts(for collections: [DittoCollection]) async throws -> [String: Int] {
        guard let ditto = await dittoManager.dittoSelectedApp else {
            throw InvalidStateError(message: "No Ditto selected app available")
        }

        // Execute the per-collection COUNT queries concurrently rather than
        // serially — this previously issued N sequential SDK round-trips on every
        // __collections change. 'count' is a reserved word in DQL, so we alias it.
        return try await withThrowingTaskGroup(of: (String, Int?).self) { group in
            for collection in collections {
                group.addTask {
                    let query = Self.makeDocumentCountQuery(collection: collection.name)
                    do {
                        let results = try await ditto.store.execute(query: query, arguments: [:])
                        if let firstItem = results.items.first {
                            let count = firstItem.value["numDocs"] as? Int
                            firstItem.dematerialize()
                            return (collection.name, count)
                        }
                    } catch {
                        // Continue with other collections even if one fails
                    }
                    return (collection.name, nil)
                }
            }

            var countsByCollection: [String: Int] = [:]
            for try await (name, count) in group {
                if let count {
                    countsByCollection[name] = count
                }
            }
            return countsByCollection
        }
    }

    func refreshCollections() async throws -> [DittoCollection] {
        guard let ditto = await dittoManager.dittoSelectedApp,
              let appState else
        {
            throw InvalidStateError(message: "No Ditto selected app or app state available")
        }

        // Fetch current collections from the database
        let query = "SELECT * FROM __collections"
        let results = try await ditto.store.execute(query: query)

        var collections = results.items.compactMap { item -> DittoCollection? in
            do {
                let cleaned = item.value.compactMapValues { $0 }
                let json = try JSONSerialization.data(withJSONObject: cleaned, options: [.fragmentsAllowed])
                let decodedItem = try decoder.decode(DittoCollection.self, from: json)
                item.dematerialize()
                return decodedItem
            } catch {
                item.dematerialize()
                Task { @MainActor in appState.setError(error) }
                return nil
            }
        }.filter { !$0.name.hasPrefix("__") } // Filter out system collections

        // Fetch fresh document counts
        let counts = try await fetchDocumentCounts(for: collections)

        // Enrich collections with updated counts
        for i in collections.indices {
            let collectionName = collections[i].name
            collections[i].documentCount = counts[collectionName]
        }

        // Fetch indexes and attach to each collection
        let indexesByCollection = try await fetchIndexes(for: collections)
        for i in collections.indices {
            collections[i].indexes = indexesByCollection[collections[i].name] ?? []
        }

        // Trigger the update callback to refresh UI on main actor
        let sorted = collections.sorted { $0.name < $1.name }
        await notifyCollectionsUpdate(sorted)

        return sorted
    }

    func createIndex(collection: String, fields: [IndexField]) async throws {
        guard let ditto = await dittoManager.dittoSelectedApp else {
            throw InvalidStateError(message: "No Ditto selected app available")
        }
        let cleaned = try Self.normalizedFields(fields)
        let safeName = Self.makeIndexName(collection: collection, fields: cleaned)

        // IF NOT EXISTS only compares index NAMES — it silently succeeds without
        // changing anything when an index of the same name exists with a different
        // definition (e.g. flipped sort direction, or a field-name collision after
        // sanitization). Detect that case and surface it instead of no-oping.
        let existing = try await ditto.store.execute(
            query: "SELECT * FROM system:indexes WHERE _id = :id",
            arguments: ["id": "\(collection).\(safeName)"]
        )
        if let item = existing.items.first {
            let existingKeys = Self.parseIndexKeys(from: item.value)
            item.dematerialize()
            if Self.indexKeysMatch(existing: existingKeys, requested: cleaned) {
                return // identical index already exists — idempotent success
            }
            throw InvalidStateError(
                message: "An index named '\(safeName)' already exists on '\(collection)' "
                    + "with a different field definition. Drop it before re-creating."
            )
        }

        // `cleaned` is already normalized, so this cannot throw — but the
        // signature is throwing for direct use with unvalidated input.
        let query = try Self.makeCreateIndexQuery(collection: collection, fields: cleaned)
        _ = try await ditto.store.execute(query: query)
    }

    // MARK: - Pure DQL builders

    /// Trims whitespace and drops blank field names. Throws when nothing remains.
    nonisolated static func normalizedFields(_ fields: [IndexField]) throws -> [IndexField] {
        let cleaned = fields
            .map { IndexField(name: $0.name.trimmingCharacters(in: .whitespaces), ascending: $0.ascending) }
            .filter { !$0.name.isEmpty }
        guard !cleaned.isEmpty else {
            throw InvalidStateError(message: "At least one field is required to create an index")
        }
        return cleaned
    }

    /// Builds the `idx_{collection}_{field…}` name for an index. Dots, spaces and
    /// dashes are replaced with underscores because they are not valid in DQL
    /// identifiers (dots separate collection from index name).
    nonisolated static func makeIndexName(collection: String, fields: [IndexField]) -> String {
        let raw = "idx_" + ([collection] + fields.map(\.name)).joined(separator: "_")
        return raw
            .replacingOccurrences(of: ".", with: "_")
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "-", with: "_")
    }

    /// Backtick-quotes a single DQL identifier, escaping embedded backticks by
    /// doubling — per the DQL tokenizer grammar.
    nonisolated static func quoteIdentifier(_ name: String) -> String {
        "`\(name.replacingOccurrences(of: "`", with: "``"))`"
    }

    /// Backtick-quotes one field path for DQL. Each dot-separated segment is
    /// quoted individually (`address.city` → `` `address`.`city` ``).
    nonisolated static func quoteFieldPath(_ name: String) -> String {
        name.split(separator: ".", omittingEmptySubsequences: false)
            .map { quoteIdentifier(String($0)) }
            .joined(separator: ".")
    }

    /// Builds the per-collection COUNT query used by fetchDocumentCounts.
    /// The collection name is backtick-quoted so names with spaces or dashes
    /// parse instead of failing per-collection (and being swallowed to nil).
    nonisolated static func makeDocumentCountQuery(collection: String) -> String {
        "SELECT COUNT(*) as numDocs FROM \(quoteIdentifier(collection))"
    }

    /// Builds the CREATE INDEX statement for one or more fields. Multiple
    /// fields produce a composite index; each key is emitted with an explicit
    /// ASC/DESC direction. Blank field names are dropped. The index name,
    /// collection and field names are all backtick-quoted so names with
    /// spaces, dashes or other punctuation parse (an unquoted dash in the
    /// index name is a hard DQL parse error on SDK 5.1).
    nonisolated static func makeCreateIndexQuery(collection: String, fields: [IndexField]) throws -> String {
        let cleaned = try normalizedFields(fields)
        let keys = cleaned
            .map { "\(quoteFieldPath($0.name)) \($0.ascending ? "ASC" : "DESC")" }
            .joined(separator: ", ")
        let safeName = makeIndexName(collection: collection, fields: cleaned)
        return "CREATE INDEX IF NOT EXISTS \(quoteIdentifier(safeName)) ON \(quoteIdentifier(collection)) (\(keys))"
    }

    /// Undoes DQL backtick-quoting for one stored path segment. Only segments
    /// that are actually quoted (older SDKs wrapped them; 5.1 stores raw values)
    /// are unwrapped, and escaped double-backticks inside them are collapsed.
    /// Raw segments pass through untouched.
    nonisolated static func unquoteSegment(_ segment: String) -> String {
        guard segment.count >= 2, segment.hasPrefix("`"), segment.hasSuffix("`") else {
            return segment
        }
        return String(segment.dropFirst().dropLast())
            .replacingOccurrences(of: "``", with: "`")
    }

    /// Parses the `fields` array of a `system:indexes` row into index keys.
    /// Each entry is `{"direction": "asc"|"desc", "key": [path segments]}`;
    /// segments are joined with dots. Backtick-quoting around segments
    /// (emitted by older SDKs) is undone. A plain string array is accepted
    /// as a legacy fallback.
    nonisolated static func parseIndexKeys(from json: [String: Any]) -> [IndexField] {
        if let rawFields = json["fields"] as? [[String: Any]] {
            return rawFields.compactMap { dict -> IndexField? in
                guard let segments = dict["key"] as? [String], !segments.isEmpty else { return nil }
                let name = segments.map { unquoteSegment($0) }.joined(separator: ".")
                let ascending = (dict["direction"] as? String)?.lowercased() != "desc"
                return IndexField(name: name, ascending: ascending)
            }
        }
        if let stringFields = json["fields"] as? [String] {
            return stringFields.map { IndexField(name: unquoteSegment($0), ascending: true) }
        }
        return []
    }

    /// Whether an existing index's keys exactly match the requested definition
    /// (same fields, same order, same directions).
    nonisolated static func indexKeysMatch(existing: [IndexField], requested: [IndexField]) -> Bool {
        existing == requested
    }

    private func notifyCollectionsUpdate(_ collections: [DittoCollection]) async {
        await onCollectionsUpdate?(collections)
    }

    func setAppState(_ appState: AppState) {
        self.appState = appState
    }

    func setOnCollectionsUpdate(_ callback: @escaping @MainActor @Sendable ([DittoCollection]) -> Void) {
        onCollectionsUpdate = callback
    }

    func stopObserver() {
        // Synchronous: callers reach this through `await` because we're inside
        // an actor. The previous `Task.detached` opened a race where the new
        // session's observer could be cancelled by the previous session's
        // cleanup task. Actor isolation already serialises access — no
        // priority inversion here because callers are already off the main
        // thread by the time they `await` into the actor.
        collectionsObserver?.cancel()
        collectionsObserver = nil
    }
}

// MARK: - Protocol Conformance

extension CollectionsRepository: CollectionsRepositoryProtocol {}
