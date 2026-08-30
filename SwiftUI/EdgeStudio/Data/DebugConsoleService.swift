import Foundation

/// Drives the Debug Console (SDK 5.1 `debug_socket`): enables the listener via
/// runtime `ALTER SYSTEM` on the app's own Ditto instance, and serializes
/// newline-DQL exchanges through [DebugSocketClient].
@MainActor @Observable
final class DebugConsoleService {
    struct ConsoleEntry: Identifiable {
        let id = UUID()
        let statement: String
        let response: String
        let isError: Bool
    }

    private(set) var entries: [ConsoleEntry] = []
    private(set) var isActive = false
    private(set) var isRunning = false

    private let client = DebugSocketClient()

    /// Short + inside the sandbox container (PoC findings: sun_path ≤104 chars;
    /// binds outside the container are denied; the debug bundle id is 6 chars
    /// longer, so keep the leaf minimal — plan recommends `ditto-debug.sock`).
    private let socketPath = FileManager.default.temporaryDirectory
        .appendingPathComponent("ditto-debug.sock").path

    /// Enables the socket and connects the client. Idempotent.
    func open() async throws {
        guard !isActive else { return }
        guard let ditto = await DittoManager.shared.dittoSelectedApp else {
            throw AppError.error(message: "No active database — open a database first.")
        }
        _ = try await ditto.store.execute(query: "ALTER SYSTEM SET debug_socket = '\(socketPath)'")
        try await client.connect(path: socketPath)
        isActive = true
    }

    /// Runs one DQL statement over the debug socket (opens on demand).
    func execute(_ statement: String) async {
        isRunning = true
        defer { isRunning = false }
        do {
            if !isActive {
                try await open()
            }
            let response = try await client.execute(statement)
            entries.append(ConsoleEntry(
                statement: statement,
                response: prettyPrint(response),
                isError: response.hasPrefix("ERROR")
            ))
        } catch {
            entries.append(ConsoleEntry(
                statement: statement,
                response: error.localizedDescription,
                isError: true
            ))
        }
    }

    func clear() {
        entries.removeAll()
    }

    /// Idempotent (sheet dismiss + view Close both funnel here).
    func close() async {
        guard isActive else { return }
        await client.close()
        isActive = false
        if let ditto = await DittoManager.shared.dittoSelectedApp {
            _ = try? await ditto.store.execute(query: "ALTER SYSTEM SET debug_socket = ''")
        }
    }

    private func prettyPrint(_ raw: String) -> String {
        guard let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(
                  withJSONObject: obj,
                  options: [.prettyPrinted, .sortedKeys]
              ) else { return raw }
        return String(decoding: pretty, as: UTF8.self)
    }
}

/// True when the statement mutates (extension parity: the console confirms
/// INSERT/UPDATE/DELETE/EVICT/ALTER/CREATE/DROP before running them).
func isMutatingDqlStatement(_ statement: String) -> Bool {
    let first = statement.drop(while: { $0.isWhitespace })
        .prefix(while: { $0.isLetter })
        .uppercased()
    return ["INSERT", "UPDATE", "DELETE", "EVICT", "ALTER", "CREATE", "DROP"].contains(first)
}
