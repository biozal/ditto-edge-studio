import SwiftUI

struct SubscriptionObserverEditor: View {
    @Environment(AppState.self) private var appState

    let title: String
    @State private var name: String
    @State private var query: String

    let onSave: (String, String, AppState) -> Void
    let onCancel: () -> Void

    init(
        title: String = "",
        name: String = "",
        query: String = "",
        onSave: @escaping (String, String, AppState) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.title = title
        _name = State(initialValue: name)
        _query = State(initialValue: query)

        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Basic Information") {
                    TextField("Name", text: $name)
                        .padding(.bottom, 20)
                }
                Section("Query") {
                    TextEditor(text: $query)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 120)
                        .padding(6)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    Text("Ex: SELECT * FROM collectionName")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 20)
                }
            }
            #if os(macOS)
            .padding()
            #endif
            .navigationTitle(title)
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            onCancel()
                        } label: {
                            Label("Cancel", systemImage: "xmark")
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            Task {
                                onSave(name, query, appState)
                            }
                        }
                        .disabled(name.isEmpty || query.isEmpty)
                    }
                }
        }
    }
}

#Preview {
    let onSave: (String, String, AppState) -> Void = { _, _, _ in }
    let onCancel: () -> Void = {}

    SubscriptionObserverEditor(
        title: "Test Title",
        name: "test Query",
        query: "SELECT * FROM test",
        onSave: onSave,
        onCancel: onCancel
    )
    .environment(AppState())
}
