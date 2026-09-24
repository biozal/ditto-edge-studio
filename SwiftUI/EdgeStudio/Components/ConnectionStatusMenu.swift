import SwiftUI

// Connection status + optional page size menu for iOS bottom toolbars.
//
// Shows a badged network icon. Tapping reveals:
// - Per-transport connection breakdown
// - Optional page size section (hidden when `pageSize` is nil, `pageSizes` is
//   empty, or has only one option)
#if os(iOS)
struct ConnectionStatusMenu: View {
    let connections: ConnectionsByTransport
    /// Nil for views without pagination (e.g. Presence) — hides the page-size section.
    var pageSize: Binding<Int>?
    var pageSizes: [Int] = []
    var onPageSizeChange: ((Int) -> Void)?

    var body: some View {
        Menu {
            // Connection breakdown section
            if connections.hasActiveConnections {
                Section("Connections") {
                    ForEach(connections.activeTransports, id: \.name) { transport in
                        Label("\(transport.name): \(transport.count)", systemImage: "circle.fill")
                    }
                }
            } else {
                Section {
                    Label("No Active Connections", systemImage: "antenna.radiowaves.left.and.right.slash")
                        .foregroundStyle(.secondary)
                }
            }

            // Page size section — only shown when there is more than one option
            if let pageSize, let onPageSizeChange, pageSizes.count > 1 {
                Section("Page Size") {
                    ForEach(pageSizes, id: \.self) { size in
                        Button {
                            onPageSizeChange(size)
                        } label: {
                            Label(
                                "Show \(size) per page",
                                systemImage: pageSize.wrappedValue == size ? "checkmark" : ""
                            )
                        }
                    }
                }
            }
        } label: {
            Label("Network Connections", systemImage: "antenna.radiowaves.left.and.right")
                .badge(connections.totalConnections)
        }
        .accessibilityIdentifier("ConnectionStatusMenu")
        .accessibilityValue("\(connections.totalConnections) active connections")
    }
}
#endif
