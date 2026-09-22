import SwiftUI

/// Floating bottom bar for detail views — transport pills on the left,
/// optional middle content (e.g. pagination controls), and total connection
/// count on the right.
///
/// macOS-only in practice: iOS detail views declare a native `.bottomBar`
/// toolbar instead, because only standard system bars are relocated to the
/// vertical side bar on iPhone Duo (see "Designing for iPhone Duo" — the HIG
/// explicitly says not to override the system's bar placement, which is why
/// there is no custom right-edge position here).
struct DetailBottomBar<MiddleContent: View>: View {
    let connections: ConnectionsByTransport
    let middleContent: MiddleContent
    @State private var isCollapsed = false
    @State private var isShowingPopover = false

    init(
        connections: ConnectionsByTransport,
        middleContent: MiddleContent
    ) {
        self.connections = connections
        self.middleContent = middleContent
    }

    var body: some View {
        HStack {
            if isCollapsed {
                Spacer()
                GlassEffectContainer {
                    expandButton
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

    /// Expand pill shown when collapsed. Padding + .glassEffect live INSIDE the
    /// label so the entire glass pill is the button's hit region (44×44 minimum
    /// per Apple HIG touch-target guidance).
    private var expandButton: some View {
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

    private var collapseButton: some View {
        // Same hit-target fix as the expand button: pad inside the label and lock
        // a 44×44 minimum, with .contentShape unifying the rectangle so taps near
        // the chevron register on the button (not pass through).
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
    /// `middleContent` is last so trailing-closure call sites match it.
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
