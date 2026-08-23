import SwiftUI

/// Bottom bar for all detail views — transport pills on the left,
/// optional middle content (e.g. pagination controls), and total connection count on the right.
struct DetailBottomBar<MiddleContent: View>: View {
    let connections: ConnectionsByTransport
    let middleContent: MiddleContent
    @State private var isCollapsed = false
    @State private var isShowingPopover = false

    var body: some View {
        HStack {
            if isCollapsed {
                Spacer()
                GlassEffectContainer {
                    // Hit-target fix: padding + .glassEffect live INSIDE the label so
                    // the entire glass pill is the button's hit region. Previously the
                    // padding was applied AFTER `.buttonStyle(.plain)`, which put it
                    // outside the button's tap region — users had to land on the
                    // chevron pixels themselves to expand the toolbar. `.contentShape`
                    // makes the full padded rectangle hit-test as one piece, and the
                    // 44×44 minimum frame matches Apple's HIG touch-target guidance.
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            isCollapsed = false
                        }
                    } label: {
                        Image(systemName: "chevron.left.chevron.left.dotted")
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 44, minHeight: 44)
                            .padding(.horizontal, 8)
                            .contentShape(Rectangle())
                            .glassEffect(in: RoundedRectangle(cornerRadius: 20))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Expand toolbar")
                    .help("Expand toolbar")
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
        // Same hit-target fix as the collapsed-state expand button: pad inside the
        // label and lock a 44×44 minimum, with .contentShape unifying the rectangle
        // so taps near the chevron register on the button (not pass through).
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { isCollapsed = true }
        } label: {
            Image(systemName: "chevron.right.dotted.chevron.right")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Collapse toolbar")
        .help("Collapse toolbar")
    }

    private var connectionsMenu: some View {
        // .contentShape ensures the full label rectangle (icon + count + min frame)
        // hit-tests as the button. Without it, taps that hit the gap between the
        // antenna glyph and the digit fall through to the toolbar background.
        Button {
            isShowingPopover = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                Text("\(connections.totalConnections)")
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundStyle(.primary)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Active connections: \(connections.totalConnections)")
        .popover(isPresented: $isShowingPopover, arrowEdge: .bottom) {
            connectionsPopoverContent
        }
    }

    @ViewBuilder
    private var connectionsPopoverContent: some View {
        if connections.hasActiveConnections {
            VStack(alignment: .leading, spacing: 0) {
                Text("Connections")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .padding(.bottom, 4)
                Divider()
                ForEach(connections.activeTransports, id: \.name) { transport in
                    Label {
                        Text("\(transport.name): \(transport.count)")
                            .foregroundStyle(.primary)
                    } icon: {
                        Image(systemName: "circle.fill")
                            .foregroundStyle(transport.color)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
            }
            .padding(.bottom, 6)
        } else {
            Label {
                Text("No Active Connections")
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: "antenna.radiowaves.left.and.right.slash")
                    .foregroundStyle(.secondary)
            }
            .padding(12)
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
