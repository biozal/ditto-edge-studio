import SwiftUI

/// Status bar component displaying sync state and real-time connection statistics by transport type
/// Uses Ditto Rainbow colors: WebSocket (Purple), Bluetooth (Blue), P2P WiFi (Pink), Access Point (Green)
struct ConnectionStatusBar: View {
    let connections: ConnectionsByTransport
    let isSyncEnabled: Bool

    var body: some View {
        HStack(spacing: 16) {
            // Left: Sync status indicator
            HStack(spacing: 6) {
                Circle()
                    .fill(isSyncEnabled ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)

                Text(isSyncEnabled ? "Sync Active" : "Sync Disabled")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Divider()
                .frame(height: 16)

            // Middle: Connection transport pills
            if connections.hasActiveConnections {
                HStack(spacing: 8) {
                    ForEach(connections.activeTransports, id: \.name) { transport in
                        HStack(spacing: 4) {
                            FontAwesomeText(icon: transport.icon, size: 10, color: transport.color)

                            Text(transport.name)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)

                            Text("\(transport.count)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.primary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .clipShape(Capsule())
                        .liquidGlassPill(color: transport.color)
                    }
                }
            } else {
                Text("No Active Connections")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Right: Total connections count
            HStack(spacing: 6) {
                Image(systemName: "link")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

                Text("\(connections.totalConnections)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 28)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.secondary.opacity(0.2))
                .frame(height: 0.5)
        }
    }
}

// MARK: - Preview

#Preview("Active Connections") {
    ConnectionStatusBar(
        connections: ConnectionsByTransport(
            accessPoint: 2,
            bluetooth: 1,
            p2pWiFi: 3,
            webSocket: 4
        ),
        isSyncEnabled: true
    )
    .frame(width: 800)
}

#Preview("No Connections") {
    ConnectionStatusBar(
        connections: .empty,
        isSyncEnabled: false
    )
    .frame(width: 800)
}

#Preview("WebSocket Only") {
    ConnectionStatusBar(
        connections: ConnectionsByTransport(
            accessPoint: 0,
            bluetooth: 0,
            p2pWiFi: 0,
            webSocket: 5
        ),
        isSyncEnabled: true
    )
    .frame(width: 800)
}
