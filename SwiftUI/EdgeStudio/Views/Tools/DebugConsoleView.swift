import SwiftUI

/// The Debug Console (SDK 5.1 `debug_socket`): full-syntax DQL against this
/// app's own embedded Ditto over a unix socket. Parity with the VS Code
/// extension's Debug Console panel.
struct DebugConsoleView: View {
    let service: DebugConsoleService
    let onClose: () -> Void

    @State private var statement = ""
    @State private var confirming: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                // Live-mutation warning (extension parity): 5.1 defaults
                // dql_enable_remote_full_syntax to true.
                Label(
                    "Full-syntax DQL — INSERT/UPDATE/DELETE/EVICT/ALTER SYSTEM apply immediately.",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(.orange)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6))

                // Response log
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            if service.entries.isEmpty {
                                Text("e.g. SELECT * FROM system:dual")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            ForEach(service.entries) { entry in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("❯ \(entry.statement)")
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                    Text(entry.response)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(entry.isError ? Color.red : Color.primary)
                                        .textSelection(.enabled)
                                }
                                .id(entry.id)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                    }
                    .onChange(of: service.entries.count) { _, _ in
                        if let last = service.entries.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Input row
                HStack(spacing: 8) {
                    TextField("SELECT * FROM …", text: $statement)
                        .font(.system(.body, design: .monospaced))
                        .textFieldStyle(.roundedBorder)
                        .disabled(service.isRunning)
                        .onSubmit { run() }
                        .accessibilityIdentifier("DebugConsoleInput")
                    Button(action: run) {
                        if service.isRunning {
                            ProgressView()
                        } else {
                            Label("Run", systemImage: "play.fill")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(service.isRunning || statement.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityIdentifier("DebugConsoleRunButton")
                }
            }
            .padding()
            .navigationTitle("Debug Console")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Clear") { service.clear() }
                        .disabled(service.entries.isEmpty || service.isRunning)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") {
                        Task {
                            await service.close()
                            onClose()
                        }
                    }
                    .accessibilityIdentifier("DebugConsoleCloseButton")
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 620, minHeight: 440)
        #endif
        // Mutation confirmation (extension parity: confirm modal).
        .alert(
            "Run mutating statement?",
            isPresented: Binding(
                get: { confirming != nil },
                set: {
                    if !$0 {
                        confirming = nil
                    }
                }
            ),
            presenting: confirming
        ) { statement in
            Button("Run") {
                confirming = nil
                Task { await service.execute(statement) }
            }
            Button("Cancel", role: .cancel) { confirming = nil }
        } message: { statement in
            Text(statement)
                .font(.system(.caption, design: .monospaced))
        }
    }

    private func run() {
        let query = statement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, !service.isRunning else { return }
        if isMutatingDqlStatement(query) {
            confirming = query
            return
        }
        Task { await service.execute(query) }
    }
}
