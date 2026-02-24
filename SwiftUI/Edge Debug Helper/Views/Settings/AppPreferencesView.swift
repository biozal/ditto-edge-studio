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
        // the Form; height will grow if more preferences are added.
        .frame(width: 460, height: 160)
    }
}

// MARK: - General Tab

private struct GeneralPreferencesTab: View {
    @AppStorage("metricsEnabled") private var metricsEnabled = true

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
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
    }
}
#endif
