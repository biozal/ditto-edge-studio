import SwiftUI

struct AddIndexView: View {
    let collections: [DittoCollection]
    let onCancel: () -> Void
    let onCreated: () -> Void

    @Environment(AppState.self) var appState
    @State private var selectedCollection = ""
    @State private var fields: [FieldDraft] = [FieldDraft()]
    @State private var isCreating = false
    @State private var errorMessage: String?

    /// Editable row state for one index key. Two or more rows produce a
    /// composite index (Ditto SDK 5.1+).
    private struct FieldDraft: Identifiable {
        let id = UUID()
        var name = ""
        var ascending = true
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Collection", selection: $selectedCollection) {
                    ForEach(collections, id: \.name) { c in
                        Text(c.name).tag(c.name)
                    }
                }
                Section("Fields") {
                    ForEach(Array($fields.enumerated()), id: \.element.id) { index, $field in
                        HStack(spacing: 12) {
                            TextField("Field \(index + 1)", text: $field.name)
                                .autocorrectionDisabled()
                            Picker("Direction", selection: $field.ascending) {
                                Text("ASC").tag(true)
                                Text("DESC").tag(false)
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .frame(width: 140)
                            if fields.count > 1 {
                                Button {
                                    fields.removeAll { $0.id == field.id }
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Remove field")
                            }
                        }
                    }
                    Button {
                        fields.append(FieldDraft())
                    } label: {
                        Label("Add Field", systemImage: "plus.circle")
                    }
                    if hasBlankFieldRows {
                        Text("Blank field rows are ignored — fill them in or remove them.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(
                            "An index covers one or more fields on a collection. Adding multiple fields creates a composite index."
                        )
                        Text(
                            "Field order matters in a composite index: put fields used in equality filters first, followed by fields used for range filters or sorting. Queries that skip the leading field generally benefit less from the index."
                        )
                        Text(
                            "DQL also supports union and intersect scans for queries with OR, IN, and AND operators, allowing the query optimizer to use multiple single-field indexes simultaneously in a single query."
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
                .frame(minWidth: 420, minHeight: 280)
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
                                fieldSpecs.isEmpty ||
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

    /// True when at least one row is filled in AND at least one row is blank
    /// (or whitespace-only). Blank rows are silently dropped by `fieldSpecs`,
    /// so once the user has started entering fields we surface a hint instead
    /// of letting them think the blank row was indexed. (A single untouched
    /// blank row — the initial state — doesn't trigger this; Create is
    /// already disabled in that case.)
    private var hasBlankFieldRows: Bool {
        let blanks = fields.filter { $0.name.trimmingCharacters(in: .whitespaces).isEmpty }
        return !blanks.isEmpty && blanks.count < fields.count
    }

    /// Trimmed, non-empty field specs in row order.
    private var fieldSpecs: [IndexField] {
        fields
            .map {
                IndexField(
                    name: $0.name.trimmingCharacters(in: .whitespaces),
                    ascending: $0.ascending
                )
            }
            .filter { !$0.name.isEmpty }
    }

    private func createIndex() async {
        isCreating = true
        errorMessage = nil
        let specs = fieldSpecs
        let names = specs.map(\.name)
        if let duplicate = names.first(where: { name in names.filter { $0 == name }.count > 1 }) {
            errorMessage = "Duplicate field '\(duplicate)' — each field can appear only once in an index."
            isCreating = false
            return
        }
        do {
            try await CollectionsRepository.shared.createIndex(
                collection: selectedCollection,
                fields: specs
            )
            onCreated()
        } catch {
            errorMessage = error.localizedDescription
            Log.error("Failed to create index: \(error.localizedDescription)")
        }
        isCreating = false
    }
}
