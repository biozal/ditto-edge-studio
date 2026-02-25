#if os(macOS)
import SwiftUI

/// Root view for the macOS Settings window.
///
/// Opened via app menu → Settings… (⌘,). Declared as a `Settings` scene in
/// `Ditto_Edge_StudioApp`. Additional tabs can be added here as the app grows.
struct AppPreferencesView: View {
    var body: some View {
        TabView {
            GeneralPreferencesTab()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
        }
        // Frame sets the initial window size. Width chosen to comfortably fit
        // the Form; height grows as more preferences are added.
        .frame(width: 460, height: 260)
    }
}

// MARK: - General Tab

private struct GeneralPreferencesTab: View {
    @AppStorage("metricsEnabled") private var metricsEnabled = true
    @AppStorage("mcpServerEnabled") private var mcpServerEnabled = false
    @AppStorage("mcpServerPort") private var mcpServerPort = 65269
    @State private var isServerActuallyRunning = false

    var body: some View {
        Form {
            Section {
                Toggle("Collect Metrics", isOn: $metricsEnabled)
                Text("When disabled, no performance data is collected and the Metrics section is hidden from the navigation menu.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Label("Metrics", systemImage: "chart.line.uptrend.xyaxis")
            }

            Section {
                Toggle("Enable MCP Server", isOn: $mcpServerEnabled)
                if mcpServerEnabled {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(isServerActuallyRunning ? Color.green : Color.orange)
                            .frame(width: 8, height: 8)
                        Text(isServerActuallyRunning
                            ? "Running on port \(mcpServerPort)"
                            : "Starting…"
                        )
                        .foregroundStyle(.secondary)
                    }
                }
                Text("Allows AI agents (Claude Code, Cursor, etc.) to query the active database via MCP. See docs/MCP_SERVER.md for setup.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Label("MCP Server", systemImage: "network")
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
        .task {
            // Poll server status while the view is visible
            while !Task.isCancelled {
                isServerActuallyRunning = await MCPServerService.shared.isRunning
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }
}
#endif
