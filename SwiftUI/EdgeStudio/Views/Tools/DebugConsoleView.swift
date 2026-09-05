import SwiftUI

/// The DQL Console (SDK 5.1 `debug_socket`): full-syntax DQL against this app's
/// own embedded Ditto over a unix socket. Parity with the VS Code extension's
/// Debug Console panel.
///
/// Embedded as the **Console** tab of `QueryResultsView` rather than presented
/// modally — the console is a peer of Raw/Table/Profile in the Query Workbench,
/// and an always-visible segment is the only placement that stays discoverable.
/// There is deliberately no Close button: the socket outlives a tab switch (so
/// scrollback survives peeking at Table) and is torn down once per studio
/// session by `MainStudioViewModel.closeSelectedApp`.
struct DebugConsoleView: View {
    let service: DebugConsoleService

    @State private var statement = ""
    @State private var confirming: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

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

            inputRow
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .accessibilityIdentifier("DebugConsoleView")
        // Mutation confirmation (extension parity: confirm modal). Matters more
        // as a tab than it did as a sheet — the console now sits one click away
        // from casually browsing results.
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

    /// Live-mutation warning (extension parity: 5.1 defaults
    /// `dql_enable_remote_full_syntax` to true) plus the Clear affordance that
    /// used to live in the sheet's toolbar.
    private var header: some View {
        HStack(spacing: 8) {
            Label(
                "Full-syntax DQL — INSERT/UPDATE/DELETE/EVICT/ALTER SYSTEM apply immediately.",
                systemImage: "exclamationmark.triangle"
            )
            .font(.caption)
            .foregroundStyle(.orange)
            .frame(maxWidth: .infinity, alignment: .leading)

            Button("Clear") { service.clear() }
                .font(.caption)
                .buttonStyle(.borderless)
                .disabled(service.entries.isEmpty || service.isRunning)
                .accessibilityIdentifier("DebugConsoleClearButton")
        }
        .padding(8)
        .background(Color.orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var inputRow: some View {
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
