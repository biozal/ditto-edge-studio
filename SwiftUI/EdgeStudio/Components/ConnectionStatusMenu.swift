import SwiftUI

// Compact connection status + page size menu for iPhone bottom toolbar.
//
// Shows total peer count as its label. Tapping reveals:
// - Per-transport connection breakdown
// - Optional page size section (hidden when `pageSizes` is empty or has only one option)
#if os(iOS)
struct ConnectionStatusMenu: View {
    let connections: ConnectionsByTransport
    @Binding var pageSize: Int
    let pageSizes: [Int]
    let onPageSizeChange: (Int) -> Void

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
            if pageSizes.count > 1 {
                Section("Page Size") {
                    ForEach(pageSizes, id: \.self) { size in
                        Button {
                            onPageSizeChange(size)
                        } label: {
                            Label(
                                "Show \(size) per page",
                                systemImage: pageSize == size ? "checkmark" : ""
                            )
                        }
                    }
                }
            }
        } label: {
            Label {
                Text("\(connections.totalConnections)")
                    .font(.caption.monospacedDigit())
            } icon: {
                Image(systemName: "antenna.radiowaves.left.and.right")
            }
        }
    }
}
#endif
