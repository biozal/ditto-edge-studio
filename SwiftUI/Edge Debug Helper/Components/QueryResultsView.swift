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

    // Pagination parameters
    var currentPage: Int = 0
    var pageSize: Int = 100
    var isLoadingPage: Bool = false
    var onNextPage: (() async -> Void)? = nil
    var onPreviousPage: (() async -> Void)? = nil
    var onFirstPage: (() async -> Void)? = nil

    @State private var viewMode: QueryResultViewMode = .table
    @State private var isExporting = false
    @State private var resultsCount: Int = 0
    @AppStorage("autoFetchAttachments") private var autoFetchAttachments = false

    // Map field mapping state
    @State private var latitudeField: String = "lat"
    @State private var longitudeField: String = "lon"
    @State private var availableFields: [String] = []

    // Cached collection name to avoid recomputing on every view update
    @State private var collectionName: String? = nil

    // Confirmation alert state
    @State private var showDeleteAllConfirmation = false

    // Access singleton repository directly
    private var mappingRepository: MapFieldMappingRepository {
        MapFieldMappingRepository.shared
    }

    private var attachmentFields: [String] {
        AttachmentQueryParser.extractAttachmentFields(from: queryText)
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
                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let id = json["_id"] as? String else {
                        return false
                    }
                    return id == documentId
                }
            } catch {
                // Errors are already handled by QueryService
            }
        }
    }

    private func handleDeleteAll() {
        guard let collection = collectionName else {
            return
        }

        Task {
            do {
                // Extract all document IDs from results
                let documentIds = extractAllDocumentIds()
                guard !documentIds.isEmpty else {
                    return
                }

                // Create DELETE query with WHERE _id IN clause
                try await QueryService.shared.deleteDocuments(documentIds: documentIds, collection: collection)

                // Clear results after successful deletion
                jsonResults = []
            } catch {
                // Errors are already handled by QueryService
            }
        }
    }

    private func extractAllDocumentIds() -> [String] {
        var ids: [String] = []
        for jsonString in jsonResults {
            guard let data = jsonString.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = json["_id"] as? String else {
                continue
            }
            ids.append(id)
        }
        return ids
    }

    init(
        jsonResults: Binding<[String]>,
        queryText: String = "",
        hasExecutedQuery: Bool = false,
        appId: String = "",
        currentPage: Int = 0,
        pageSize: Int = 100,
        isLoadingPage: Bool = false,
        onNextPage: (() async -> Void)? = nil,
        onPreviousPage: (() async -> Void)? = nil,
        onFirstPage: (() async -> Void)? = nil
    ) {
        _jsonResults = jsonResults
        self.queryText = queryText
        self.hasExecutedQuery = hasExecutedQuery
        self.appId = appId
        self.currentPage = currentPage
        self.pageSize = pageSize
        self.isLoadingPage = isLoadingPage
        self.onNextPage = onNextPage
        self.onPreviousPage = onPreviousPage
        self.onFirstPage = onFirstPage
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
                    showDeleteAllConfirmation = true
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

            // Pagination controls
            if hasExecutedQuery && !jsonResults.isEmpty {
                HStack {
                    // Page info
                    Text("Page \(currentPage + 1)")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("•")
                        .foregroundColor(.secondary)

                    Text("\(jsonResults.count) results")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    // Loading indicator
                    if isLoadingPage {
                        ProgressView()
                            .scaleEffect(0.7)
                            .padding(.trailing, 8)
                    }

                    // Navigation buttons
                    Button {
                        Task {
                            await onFirstPage?()
                        }
                    } label: {
                        Image(systemName: "chevron.left.2")
                    }
                    .buttonStyle(.borderless)
                    .disabled(currentPage == 0 || isLoadingPage)
                    .help("Go to first page")

                    Button {
                        Task {
                            await onPreviousPage?()
                        }
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(.borderless)
                    .disabled(currentPage == 0 || isLoadingPage)
                    .help("Previous page")

                    Button {
                        Task {
                            await onNextPage?()
                        }
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .buttonStyle(.borderless)
                    .disabled(jsonResults.count < pageSize || isLoadingPage)
                    .help("Next page")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.primary.opacity(0.03))

                Divider()
            }

            // Content based on selected view mode
            Group {
                switch viewMode {
                case .table:
                    ResultJsonViewer(
                        resultText: $jsonResults,
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
            updateCollectionName()
            loadFieldMapping()
        }
        .onChange(of: jsonResults) { _, _ in
            updateAvailableFields()
        }
        .onChange(of: queryText) { _, _ in
            updateCollectionName()
        }
        .onChange(of: collectionName) { _, _ in
            loadFieldMapping()
        }
        .alert("Delete All Documents", isPresented: $showDeleteAllConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete All", role: .destructive) {
                handleDeleteAll()
            }
        } message: {
            Text("Are you sure you want to delete all \(jsonResults.count) document(s) from the database? This action cannot be undone.")
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
