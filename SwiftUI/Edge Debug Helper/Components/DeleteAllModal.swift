//
//  DeleteAllModal.swift
//  Edge Debug Helper
//
//  Modal for confirming and configuring delete all operations
//

import SwiftUI

struct DeleteAllModal: View {
    @Binding var isPresented: Bool
    let collectionName: String
    let resultsCount: Int
    let availableFields: [String]
    @Binding var selectedUniqueField: String
    let checkFieldUniqueness: (String) -> QueryResultsView.FieldUniquenessInfo
    let onDelete: (DeleteAllOptions) async -> Void

    @State private var deleteMode: DeleteMode = .resultsOnly
    @State private var fieldUniquenessInfo: [String: QueryResultsView.FieldUniquenessInfo] = [:]
    @State private var showFieldMismatchWarning: Bool = false
    @State private var removeCollectionFromStudio: Bool = false

    enum DeleteMode {
        case resultsOnly
        case entireCollection
    }

    struct DeleteAllOptions {
        let mode: DeleteMode
        let uniqueField: String
        let removeCollectionFromStudio: Bool
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Text("Delete Documents")
                .font(.title2)
                .bold()
                .frame(maxWidth: .infinity)
                .padding(.bottom, 20)

            // Content
            VStack(alignment: .leading, spacing: 16) {
                // Delete mode selection
                VStack(alignment: .leading, spacing: 8) {
                    Text("Delete Mode")
                        .font(.headline)

                    Picker("", selection: $deleteMode) {
                        Text("Delete Retrieved Results Only").tag(DeleteMode.resultsOnly)
                        Text("Delete Entire Collection").tag(DeleteMode.entireCollection)
                    }
                    .pickerStyle(.radioGroup)
                    .onChange(of: deleteMode) { _, _ in
                        updateWarning()
                    }
                }

                // Mode explanation
                if deleteMode == .resultsOnly {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle")
                            .foregroundColor(.blue)
                            .help("This will only delete documents that you've queried and are currently visible in Edge Studio. It will NOT affect other records in the Ditto database that are not in your current results.")
                        Text("Will delete only the \(resultsCount) document(s) currently in the results using the unique field constraint.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.blue.opacity(0.1))
                    )

                    // Unique field selection
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Unique Field")
                            .font(.headline)

                        HStack {
                            Text("Unique field to use for identifying documents:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Picker("", selection: $selectedUniqueField) {
                                ForEach(availableFields, id: \.self) { field in
                                    let info = getFieldInfo(field)
                                    if info.isUnique {
                                        Text(field).tag(field)
                                    } else {
                                        Text("\(field) (not unique)").tag(field)
                                    }
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 200)
                            .onChange(of: selectedUniqueField) { _, _ in
                                updateWarning()
                            }
                        }

                        let currentFieldInfo = getFieldInfo(selectedUniqueField)
                        Text("Selected \(currentFieldInfo.uniqueCount) of \(resultsCount) documents for deletion")
                            .font(.caption)
                            .foregroundColor(currentFieldInfo.isUnique ? .green : .orange)
                    }

                    // Warning if field is not unique
                    if !getFieldInfo(selectedUniqueField).isUnique {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Field is not unique")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                let info = getFieldInfo(selectedUniqueField)
                                Text("Could only extract \(info.uniqueCount) unique IDs from \(info.totalCount) results. Try selecting a different unique field like '_id'.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.orange.opacity(0.1))
                        )
                    }
                } else {
                    // Entire collection mode
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text("Will delete ALL documents in the '\(collectionName)' collection, including any added since the query was run. This action cannot be undone.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.red.opacity(0.1))
                    )

                    // Remove collection checkbox - indented to show it's related to the delete mode
                    HStack(spacing: 8) {
                        Spacer()
                            .frame(width: 20) // Indent to show relationship
                        Toggle(isOn: $removeCollectionFromStudio) {
                            Text("Also remove collection from Edge Studio")
                                .font(.subheadline)
                        }
                        .toggleStyle(.checkbox)

                        Button(action: {}) {
                            Image(systemName: "info.circle")
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(.plain)
                        .help("This will unregister the collection from Edge Studio's local database.\n\nNote: Collections in Ditto never truly disappear - they exist as long as documents reference them. This only removes the collection from Edge Studio's tracking.")

                        Spacer()
                    }
                    .padding(.top, 8)
                }
            }
            .padding(.bottom, 20)

            Divider()

            // Footer buttons
            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.escape)

                Spacer()

                Button(deleteMode == .entireCollection ? "Delete Entire Collection" : "Delete Results") {
                    Task {
                        await onDelete(DeleteAllOptions(
                            mode: deleteMode,
                            uniqueField: selectedUniqueField,
                            removeCollectionFromStudio: removeCollectionFromStudio
                        ))
                        isPresented = false
                    }
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
                .tint(deleteMode == .entireCollection ? .red : .blue)
                .disabled(deleteMode == .resultsOnly && !getFieldInfo(selectedUniqueField).isUnique)
            }
            .padding(.top, 12)
        }
        .padding(30)
        .frame(width: 550)
        .task {
            // Pre-compute all field info to avoid state modifications during view updates
            for field in availableFields {
                let info = checkFieldUniqueness(field)
                fieldUniquenessInfo[field] = info
            }

            // Pre-select _id if available and unique
            if let idInfo = fieldUniquenessInfo["_id"], idInfo.isUnique {
                selectedUniqueField = "_id"
            } else if let firstUniqueField = availableFields.first(where: {
                fieldUniquenessInfo[$0]?.isUnique == true
            }) {
                selectedUniqueField = firstUniqueField
            } else if let firstField = availableFields.first {
                selectedUniqueField = firstField
            }

            // Update warning after field info is computed
            if let info = fieldUniquenessInfo[selectedUniqueField] {
                showFieldMismatchWarning = !info.isUnique
            }
        }
    }

    private func getFieldInfo(_ field: String) -> QueryResultsView.FieldUniquenessInfo {
        // Return cached info or default (should always be cached after .task runs)
        return fieldUniquenessInfo[field] ?? QueryResultsView.FieldUniquenessInfo(
            isUnique: false,
            uniqueCount: 0,
            totalCount: 0
        )
    }

    private func updateWarning() {
        let info = getFieldInfo(selectedUniqueField)
        showFieldMismatchWarning = !info.isUnique
    }
}

#Preview {
    DeleteAllModal(
        isPresented: .constant(true),
        collectionName: "books",
        resultsCount: 431,
        availableFields: ["_id", "isbn", "title", "author"],
        selectedUniqueField: .constant("_id"),
        checkFieldUniqueness: { field in
            // Mock implementation for preview
            // _id and isbn are unique, title and author are not
            QueryResultsView.FieldUniquenessInfo(
                isUnique: field == "_id" || field == "isbn",
                uniqueCount: field == "_id" || field == "isbn" ? 431 : 200,
                totalCount: 431
            )
        },
        onDelete: { _ in }
    )
}
