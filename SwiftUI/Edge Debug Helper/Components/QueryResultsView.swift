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
    @State private var selectedUniqueField = "_id"

    // Field uniqueness tracking (lazy computed)
    @State private var fieldUniquenessCache: [String: FieldUniquenessInfo] = [:]

    struct FieldUniquenessInfo {
        let isUnique: Bool
        let uniqueCount: Int
        let totalCount: Int
    }

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
            guard let data = jsonString.data(using: .utf8) else {
                continue
            }

            // Try to parse as JSON object
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                parsed.append(json)
                keys.formUnion(json.keys)
            } else if let jsonValue = try? JSONSerialization.jsonObject(with: data) {
                // Handle non-object JSON (arrays, strings, numbers, etc.)
                // Wrap them in an object with a "value" key
                let wrappedJson: [String: Any] = ["value": jsonValue]
                parsed.append(wrappedJson)
                keys.insert("value")
            } else {
                // If JSON parsing fails entirely, treat as raw string
                let wrappedJson: [String: Any] = ["value": jsonString]
                parsed.append(wrappedJson)
                keys.insert("value")
            }
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

    private func handleDeleteAll(options: DeleteDocumentsModal.DeleteAllOptions) async {
        guard let collection = collectionName else {
            return
        }

        do {
            if options.mode == .entireCollection {
                try await QueryService.shared.deleteEntireCollection(collection: collection)

                // Remove collection from Edge Studio if requested
                if options.removeCollectionFromStudio {
                    print("DEBUG: Attempting to remove collection '\(collection)' from Edge Studio")
                    try await CollectionsRepository.shared.removeCollection(name: collection)
                    print("DEBUG: Successfully removed collection '\(collection)' from Edge Studio")
                }
            } else {
                let documentIds = extractFieldValues(fieldName: options.uniqueField)
                guard !documentIds.isEmpty else {
                    return
                }

                try await QueryService.shared.deleteDocumentsByField(
                    fieldValues: documentIds,
                    fieldName: options.uniqueField,
                    collection: collection
                )
            }

            // Re-execute the query to refresh results
            if let onRefreshQuery = onRefreshQuery {
                await onRefreshQuery()
            } else {
                jsonResults = []
            }
        } catch {
            print("DEBUG: Error in handleDeleteAll: \(error)")
            // Error already logged by QueryService
        }
    }

    // Check if a field has unique values across all results
    private func checkFieldUniqueness(fieldName: String) -> FieldUniquenessInfo {
        // Check cache first
        if let cached = fieldUniquenessCache[fieldName] {
            return cached
        }

        var uniqueValues = Set<String>()
        var totalCount = 0

        for jsonString in jsonResults {
            guard let data = jsonString.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            totalCount += 1

            // Extract field value and convert to string
            var valueString: String?
            if let value = json[fieldName] as? String {
                valueString = value
            } else if let value = json[fieldName] as? Int {
                valueString = String(value)
            } else if let value = json[fieldName] as? Double {
                valueString = String(Int(value))
            } else if let valueObj = json[fieldName] as? [String: Any] {
                // Handle MongoDB extended JSON formats
                if let oidValue = valueObj["$oid"] as? String {
                    valueString = oidValue
                }
            }

            if let valueString = valueString {
                uniqueValues.insert(valueString)
            }
        }

        let uniqueCount = uniqueValues.count
        let isUnique = uniqueCount == totalCount && totalCount > 0

        let info = FieldUniquenessInfo(
            isUnique: isUnique,
            uniqueCount: uniqueCount,
            totalCount: totalCount
        )

        // Cache the result
        fieldUniquenessCache[fieldName] = info

        return info
    }

    private func extractFieldValues(fieldName: String) -> [Any] {
        var values: [Any] = []
        for jsonString in jsonResults {
            guard let data = jsonString.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            // Extract field value preserving its original type
            if let value = json[fieldName] as? String {
                values.append(value)
            } else if let value = json[fieldName] as? Int {
                values.append(value)
            } else if let value = json[fieldName] as? Double {
                values.append(value)
            } else if let valueObj = json[fieldName] as? [String: Any] {
                // For objects (like MongoDB ObjectId), pass the entire object
                // DQL requires the full object: {'$oid': 'value'}
                values.append(valueObj)
            }
        }

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
                ids.append(id)
            } else if let id = json["_id"] as? Int {
                ids.append(String(id))
            } else if let id = json["_id"] as? Double {
                ids.append(String(Int(id)))
            } else if let idObj = json["_id"] as? [String: Any], let oidValue = idObj["$oid"] as? String {
                ids.append(oidValue)
            }
        }
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

                // Delete button - permanently removes from database
                Button {
                    showDeleteAllModal = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "trash.fill")
                        Text("Delete")
                    }
                }
                .buttonStyle(.borderless)
                .disabled(collectionName == nil)
                .padding(.trailing, 4)
                .help("Delete documents or entire collection from the database")

                // Clear button - only clears local results view
                Button {
                    jsonResults = []
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark.circle")
                        Text("Clear Results")
                    }
                }
                .buttonStyle(.borderless)
                .disabled(jsonResults.isEmpty)
                .padding(.trailing, 16)
                .help("Clear query results from view (does not delete from database)")
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
            // Clear uniqueness cache when results change
            fieldUniquenessCache.removeAll()
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
            DeleteDocumentsModal(
                isPresented: $showDeleteAllModal,
                collectionName: collectionName ?? "",
                resultsCount: jsonResults.count,
                availableFields: allKeys.isEmpty ? ["_id"] : allKeys,
                selectedUniqueField: $selectedUniqueField,
                checkFieldUniqueness: checkFieldUniqueness,
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
