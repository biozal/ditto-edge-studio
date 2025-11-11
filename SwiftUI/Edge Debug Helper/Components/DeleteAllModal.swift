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
    let onDelete: (DeleteAllOptions) async -> Void

    @State private var deleteMode: DeleteMode = .resultsOnly
    @State private var uniqueField: String = "_id"
    @State private var extractedIdsCount: Int = 0
    @State private var showFieldMismatchWarning: Bool = false

    enum DeleteMode {
        case resultsOnly
        case entireCollection
    }

    struct DeleteAllOptions {
        let mode: DeleteMode
        let uniqueField: String
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
                        Text("Delete Results Only").tag(DeleteMode.resultsOnly)
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
                            Text("Field to use for identifying documents:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Picker("", selection: $uniqueField) {
                                ForEach(availableFields, id: \.self) { field in
                                    Text(field).tag(field)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 150)
                        }

                        Text("Extracted \(extractedIdsCount) of \(resultsCount) document IDs")
                            .font(.caption)
                            .foregroundColor(extractedIdsCount == resultsCount ? .green : .orange)
                    }

                    // Warning if counts don't match
                    if showFieldMismatchWarning {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Field mismatch detected")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                Text("Could only extract \(extractedIdsCount) unique IDs from \(resultsCount) results. Try selecting a different unique field.")
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
                        await onDelete(DeleteAllOptions(mode: deleteMode, uniqueField: uniqueField))
                        isPresented = false
                    }
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
                .tint(deleteMode == .entireCollection ? .red : .blue)
                .disabled(deleteMode == .resultsOnly && extractedIdsCount == 0)
            }
            .padding(.top, 12)
        }
        .padding(30)
        .frame(width: 550)
        .onAppear {
            // Pre-select _id if available
            if availableFields.contains("_id") {
                uniqueField = "_id"
            } else if let firstField = availableFields.first {
                uniqueField = firstField
            }
            updateWarning()
        }
        .onChange(of: uniqueField) { _, _ in
            updateWarning()
        }
    }

    private func updateWarning() {
        // This will be updated by the parent when field changes
        // For now, just reset the warning state
        showFieldMismatchWarning = extractedIdsCount != resultsCount && extractedIdsCount > 0
    }
}

#Preview {
    DeleteAllModal(
        isPresented: .constant(true),
        collectionName: "books",
        resultsCount: 431,
        availableFields: ["_id", "isbn", "title"],
        onDelete: { _ in }
    )
}
