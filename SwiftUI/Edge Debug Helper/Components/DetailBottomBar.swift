import SwiftUI

/// Bottom bar for all detail views — transport pills on the left,
/// optional middle content (e.g. pagination controls), and total connection count on the right.
struct DetailBottomBar<MiddleContent: View>: View {
    let connections: ConnectionsByTransport
    let middleContent: MiddleContent

    var body: some View {
        HStack(spacing: 16) {
            // Left: Transport pills
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
            middleContent
            Spacer()

            // Right: Total connections count
            HStack(spacing: 6) {
                FontAwesomeText(icon: SystemIcon.link, size: 10, color: .secondary)

                Text("\(connections.totalConnections)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 36)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.secondary.opacity(0.2))
                .frame(height: 0.5)
        }
    }
}

// MARK: - Convenience inits

extension DetailBottomBar where MiddleContent == EmptyView {
    /// No middle content — used by sync tabs view and previews.
    init(connections: ConnectionsByTransport) {
        self.connections = connections
        middleContent = EmptyView()
    }
}

extension DetailBottomBar {
    /// Middle content injected via @ViewBuilder — used by query and observer views.
    init(
        connections: ConnectionsByTransport,
        @ViewBuilder middleContent: () -> MiddleContent
    ) {
        self.connections = connections
        self.middleContent = middleContent()
    }
}

// MARK: - Preview

#Preview("Active Connections") {
    DetailBottomBar(
        connections: ConnectionsByTransport(
            accessPoint: 2,
            bluetooth: 1,
            p2pWiFi: 3,
            webSocket: 4
        )
    )
    .frame(width: 800)
}

#Preview("No Connections") {
    DetailBottomBar(connections: .empty)
        .frame(width: 800)
}

#Preview("WebSocket Only") {
    DetailBottomBar(
        connections: ConnectionsByTransport(
            accessPoint: 0,
            bluetooth: 0,
            p2pWiFi: 0,
            webSocket: 5
        )
    )
    .frame(width: 800)
}
