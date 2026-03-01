import SwiftUI

/// Bottom bar for all detail views — transport pills on the left,
/// optional middle content (e.g. pagination controls), and total connection count on the right.
struct DetailBottomBar<MiddleContent: View>: View {
    let connections: ConnectionsByTransport
    let middleContent: MiddleContent
    @State private var isCollapsed = false

    var body: some View {
        HStack {
            if isCollapsed {
                Spacer()
                GlassEffectContainer {
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            isCollapsed = false
                        }
                    } label: {
                        Image(systemName: "chevron.left.chevron.left.dotted")
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                    .glassEffect(in: RoundedRectangle(cornerRadius: 20))
                }
                .subtleShadow()
            } else {
                GlassEffectContainer {
                    HStack(spacing: 16) {
                        connectionsMenu
                        Spacer()
                        middleContent
                        collapseButton
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .glassEffect(in: RoundedRectangle(cornerRadius: 20))
                }
                .subtleShadow()
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isCollapsed)
    }

    private var collapseButton: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { isCollapsed = true }
        } label: {
            Image(systemName: "chevron.right.dotted.chevron.right")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help("Collapse toolbar")
    }

    private var connectionsMenu: some View {
        Menu {
            if connections.hasActiveConnections {
                Section("Connections") {
                    ForEach(connections.activeTransports, id: \.name) { transport in
                        Label(
                            title: { Text("\(transport.name): \(transport.count)") },
                            icon: { Image(systemName: "circle.fill").foregroundStyle(transport.color) }
                        )
                    }
                }
            } else {
                Label(
                    "No Active Connections",
                    systemImage: "antenna.radiowaves.left.and.right.slash"
                )
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                Text("\(connections.totalConnections)")
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundStyle(.primary)
            }
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
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
