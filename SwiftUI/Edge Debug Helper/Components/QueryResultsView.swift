//
//  QueryResultsView.swift
//  Ditto Edge Studio
//
//  Created by Aaron LaBeau on 5/23/25.
//

import SwiftUI

struct QueryResultsView: View {
    @Binding var jsonResults: [String]
    var queryText: String = ""
    var hasExecutedQuery: Bool = false
    var appId: String = ""

    @State private var viewMode: QueryResultViewMode = .raw
    @State private var isExporting = false
    @State private var resultsCount: Int = 0
    @AppStorage("autoFetchAttachments") private var autoFetchAttachments = false

    // Shared pagination state across all view modes
    @State private var currentPage: Int = 1
    @State private var pageSize: Int = 10

    // PERFORMANCE: Parse JSON once and share across all views
    @State private var parsedResults: [[String: Any]] = []
    @State private var allKeys: [String] = []
    @State private var parseCacheKey: Int = 0

    // Map field mapping state
    @State private var latitudeField: String = "lat"
    @State private var longitudeField: String = "lon"
    @State private var availableFields: [String] = []

    // Cached collection name to avoid recomputing on every view update
    @State private var collectionName: String? = nil

    // Delete all modal state
    @State private var showDeleteAllModal = false
    @State private var extractedIdsCount = 0

    // Access singleton repository directly
    private var mappingRepository: MapFieldMappingRepository {
        MapFieldMappingRepository.shared
    }

    private var attachmentFields: [String] {
        AttachmentQueryParser.extractAttachmentFields(from: queryText)
    }

    // PERFORMANCE: Parse JSON once when results change
    private func parseResults() {
        let newCacheKey = jsonResults.count
        guard newCacheKey != parseCacheKey else { return }

        parseCacheKey = newCacheKey

        var parsed: [[String: Any]] = []
        var keys = Set<String>()

        for jsonString in jsonResults {
            guard let data = jsonString.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            parsed.append(json)
            keys.formUnion(json.keys)
        }

        parsedResults = parsed
        allKeys = Array(keys).sorted()
    }

    private func updateCollectionName() {
        let extracted = DQLQueryParser.extractCollectionName(from: queryText)
        if extracted != collectionName {
            collectionName = extracted
        }
    }

    private func handleDelete(documentId: String, collection: String) {
        Task {
            do {
                try await QueryService.shared.deleteDocument(documentId: documentId, collection: collection)
                // Refresh results by removing the deleted item
                jsonResults.removeAll { jsonString in
                    guard let data = jsonString.data(using: .utf8),
                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                        return false
                    }

                    // Handle different _id formats
                    if let id = json["_id"] as? String {
                        return id == documentId
                    } else if let id = json["_id"] as? Int {
                        return String(id) == documentId
                    } else if let id = json["_id"] as? Double {
                        return String(Int(id)) == documentId
                    } else if let idObj = json["_id"] as? [String: Any], let oidValue = idObj["$oid"] as? String {
                        return oidValue == documentId
                    }
                    return false
                }
            } catch {
                // Errors are already handled by QueryService
            }
        }
    }

    private func handleDeleteAll(options: DeleteAllModal.DeleteAllOptions) async {
        guard let collection = collectionName else {
            print("DEBUG: No collection name found")
            return
        }

        print("DEBUG: handleDeleteAll called for collection: \(collection), mode: \(options.mode)")

        do {
            if options.mode == .entireCollection {
                // Delete entire collection - no WHERE clause
                print("DEBUG: Deleting entire collection")
                try await QueryService.shared.deleteEntireCollection(collection: collection)
                print("DEBUG: Entire collection deleted successfully")
            } else {
                // Delete only results using unique field
                print("DEBUG: Extracting IDs using field: \(options.uniqueField)")
                let documentIds = extractFieldValues(fieldName: options.uniqueField)
                print("DEBUG: Extracted \(documentIds.count) document IDs: \(documentIds.prefix(5))...")

                guard !documentIds.isEmpty else {
                    print("DEBUG: No document IDs to delete")
                    return
                }

                print("DEBUG: Calling deleteDocuments...")
                try await QueryService.shared.deleteDocumentsByField(
                    fieldValues: documentIds,
                    fieldName: options.uniqueField,
                    collection: collection
                )
                print("DEBUG: Delete completed successfully")
            }

            // Re-execute the query to refresh results
            if let onRefreshQuery = onRefreshQuery {
                print("DEBUG: Calling onRefreshQuery callback")
                await onRefreshQuery()
                print("DEBUG: onRefreshQuery completed")
            } else {
                print("DEBUG: No refresh callback, clearing results")
                jsonResults = []
            }
        } catch {
            print("DEBUG: Delete failed with error: \(error)")
        }
    }

    private func extractFieldValues(fieldName: String) -> [String] {
        var values: [String] = []
        for jsonString in jsonResults {
            guard let data = jsonString.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            // Extract field value and convert to string
            if let value = json[fieldName] as? String {
                values.append(value)
            } else if let value = json[fieldName] as? Int {
                values.append(String(value))
            } else if let value = json[fieldName] as? Double {
                values.append(String(Int(value)))
            } else if let valueObj = json[fieldName] as? [String: Any] {
                // Handle MongoDB extended JSON formats
                if let oidValue = valueObj["$oid"] as? String {
                    values.append(oidValue)
                }
            }
        }
        print("DEBUG: extractFieldValues(\(fieldName)) returning \(values.count) values")
        return values
    }

    private func extractAllDocumentIds() -> [String] {
        var ids: [String] = []
        for jsonString in jsonResults {
            guard let data = jsonString.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            // Handle different _id formats
            if let id = json["_id"] as? String {
                // Simple string ID
                ids.append(id)
            } else if let id = json["_id"] as? Int {
                // Numeric ID
                ids.append(String(id))
            } else if let id = json["_id"] as? Double {
                // Double ID
                ids.append(String(Int(id)))
            } else if let idObj = json["_id"] as? [String: Any] {
                // MongoDB extended JSON format like {"$oid": "..."}
                if let oidValue = idObj["$oid"] as? String {
                    ids.append(oidValue)
                } else {
                    print("DEBUG: Unknown _id object format: \(idObj)")
                }
            } else {
                print("DEBUG: Unknown _id type: \(type(of: json["_id"]))")
            }
        }
        print("DEBUG: extractAllDocumentIds returning \(ids.count) IDs")
        return ids
    }

    var onRefreshQuery: (() async -> Void)?

    init(
        jsonResults: Binding<[String]>,
        queryText: String = "",
        hasExecutedQuery: Bool = false,
        appId: String = "",
        onRefreshQuery: (() async -> Void)? = nil
    ) {
        _jsonResults = jsonResults
        self.queryText = queryText
        self.hasExecutedQuery = hasExecutedQuery
        self.appId = appId
        self.onRefreshQuery = onRefreshQuery
        resultsCount = _jsonResults.wrappedValue.count
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with view mode picker and action buttons
            HStack {
                ViewModePicker(selectedMode: $viewMode)
                    .padding(.leading, 16)
                    .padding(.vertical, 8)

                // Map field selector - only show when map mode is active
                if viewMode == .map && !availableFields.isEmpty {
                    MapFieldSelector(
                        latitudeField: $latitudeField,
                        longitudeField: $longitudeField,
                        availableFields: availableFields,
                        onApply: saveFieldMapping
                    )
                    .padding(.leading, 8)
                }

                Spacer()

                // Delete All button
                Button {
                    showDeleteAllModal = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "trash.fill")
                        Text("Delete All")
                    }
                }
                .buttonStyle(.borderless)
                .disabled(jsonResults.isEmpty || collectionName == nil)
                .help("Delete all documents in results from the database")

                // Clear button
                Button {
                    jsonResults = []
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                        Text("Clear")
                    }
                }
                .buttonStyle(.borderless)
                .disabled(jsonResults.isEmpty)
                .padding(.trailing, 16)
                .help("Clear all query results")
            }
            .background(Color.primary.opacity(0.05))

            Divider()

            // Content based on selected view mode
            // Note: Pagination state and parsed data shared across all view modes
            Group {
                switch viewMode {
                case .table:
                    ResultJsonViewer(
                        resultText: $jsonResults,
                        parsedItems: parsedResults,
                        allKeys: allKeys,
                        currentPage: $currentPage,
                        pageSize: $pageSize,
                        viewMode: .table,
                        attachmentFields: attachmentFields,
                        collectionName: collectionName,
                        onDelete: handleDelete,
                        hasExecutedQuery: hasExecutedQuery,
                        autoFetchAttachments: autoFetchAttachments
                    )
                case .raw:
                    ResultJsonViewer(
                        resultText: $jsonResults,
                        parsedItems: parsedResults,
                        allKeys: allKeys,
                        currentPage: $currentPage,
                        pageSize: $pageSize,
                        viewMode: .raw,
                        attachmentFields: attachmentFields,
                        hasExecutedQuery: hasExecutedQuery,
                        autoFetchAttachments: autoFetchAttachments
                    )
                case .map:
                    MapResultView(
                        jsonResults: $jsonResults,
                        hasExecutedQuery: hasExecutedQuery,
                        latitudeField: $latitudeField,
                        longitudeField: $longitudeField
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .onAppear {
            parseResults()
            updateCollectionName()
            loadFieldMapping()
        }
        .onChange(of: jsonResults) { _, _ in
            parseResults() // Parse once when results change
            updateAvailableFields()
            // Reset to first page when results change (new query executed)
            currentPage = 1
        }
        .onChange(of: queryText) { _, _ in
            updateCollectionName()
        }
        .onChange(of: collectionName) { _, _ in
            loadFieldMapping()
        }
        .sheet(isPresented: $showDeleteAllModal) {
            DeleteAllModal(
                isPresented: $showDeleteAllModal,
                collectionName: collectionName ?? "",
                resultsCount: jsonResults.count,
                availableFields: allKeys.isEmpty ? ["_id"] : allKeys,
                onDelete: { options in
                    await handleDeleteAll(options: options)
                }
            )
        }
    }

    // MARK: - Map Field Mapping Methods

    private func loadFieldMapping() {
        guard !appId.isEmpty, let collection = collectionName else {
            return
        }

        let mapping = mappingRepository.getMapping(appId: appId, collectionName: collection)
        latitudeField = mapping.latitudeField
        longitudeField = mapping.longitudeField

        updateAvailableFields()
    }

    private func updateAvailableFields() {
        availableFields = mappingRepository.extractPotentialCoordinateFields(from: jsonResults)

        // Auto-detect fields if this is a new mapping and we have results
        if !jsonResults.isEmpty && !appId.isEmpty && collectionName != nil {
            let currentMapping = mappingRepository.getMapping(appId: appId, collectionName: collectionName!)

            // If still using defaults, try auto-detection
            if currentMapping.latitudeField == "lat" && currentMapping.longitudeField == "lon" {
                if let detected = mappingRepository.detectCoordinateFields(from: jsonResults) {
                    latitudeField = detected.lat ?? "lat"
                    longitudeField = detected.lon ?? "lon"

                    // Save the auto-detected mapping
                    saveFieldMapping()
                }
            }
        }
    }

    private func saveFieldMapping() {
        guard !appId.isEmpty, let collection = collectionName else { return }

        let mapping = MapFieldMapping(
            appId: appId,
            collectionName: collection,
            latitudeField: latitudeField,
            longitudeField: longitudeField
        )

        mappingRepository.saveMapping(mapping)
    }

    private func flattenJsonResults() -> String {
        // If it's a single JSON object, just return it as is
        if jsonResults.count == 1 {
            return jsonResults.first ?? "[]"
        }
        // If it's multiple objects, wrap them in an array
        return "[\n" + jsonResults.joined(separator: ",\n") + "\n]"
    }
}

#Preview {
    QueryResultsView(jsonResults: .constant(["{\"key\": \"value\"}"]))
}
