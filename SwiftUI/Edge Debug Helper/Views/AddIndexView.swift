import SwiftUI

struct AddIndexView: View {
    let collections: [DittoCollection]
    let onCancel: () -> Void
    let onCreated: () -> Void

    @EnvironmentObject var appState: AppState
    @State private var selectedCollection = ""
    @State private var fieldName = ""
    @State private var isCreating = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Picker("Collection", selection: $selectedCollection) {
                    ForEach(collections, id: \.name) { c in
                        Text(c.name).tag(c.name)
                    }
                }
                TextField("Field", text: $fieldName)
                    .autocorrectionDisabled()
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("DQL limits indexes to a single field on a collection. You can create multiple indexes on a single collection.")
                        Text(
                            "DQL supports union and intersect scans for queries with OR, IN, and AND operators. This allows the query optimizer to use multiple indexes simultaneously in a single query. For example, a query like WHERE status = 'active' OR priority = 'high' can leverage separate indexes on both status and priority fields, combining results through a union scan."
                        )
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                if let error = errorMessage {
                    Section {
                        Text(error).foregroundStyle(.red).font(.caption)
                    }
                }
            }
            .navigationTitle("Add Index")
            #if os(macOS)
                .formStyle(.columns)
                .frame(minWidth: 380, minHeight: 240)
            #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", action: onCancel)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Create") {
                            Task { await createIndex() }
                        }
                        .disabled(
                            selectedCollection.isEmpty ||
                                fieldName.trimmingCharacters(in: .whitespaces).isEmpty ||
                                isCreating
                        )
                    }
                }
        }
        .onAppear {
            if selectedCollection.isEmpty, let first = collections.first {
                selectedCollection = first.name
            }
        }
    }

    private func createIndex() async {
        isCreating = true
        errorMessage = nil
        do {
            try await CollectionsRepository.shared.createIndex(
                collection: selectedCollection,
                fieldName: fieldName.trimmingCharacters(in: .whitespaces)
            )
            onCreated()
        } catch {
            errorMessage = error.localizedDescription
            Log.error("Failed to create index: \(error.localizedDescription)")
        }
        isCreating = false
    }
}
