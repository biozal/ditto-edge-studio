import SwiftUI

/// Displays connected peers in a responsive adaptive grid layout.
///
/// **Layout**: `GridItem(.adaptive(minimum: 260, maximum: 520))` — column count adjusts
/// automatically to available width (1 on small screens, 2-3+ on larger Mac/iPad displays).
///
/// **Backpressure**: Observer updates throttled to match UI render capacity (see SystemRepository).
///
/// **Stable Ordering**: Peers appear in consistent order (no ORDER BY in DQL query).
struct ConnectedPeersView: View {
    @Bindable var viewModel: MainStudioView.ViewModel
    @State private var networkInterfaces: [NetworkInterfaceInfo] = []
    @State private var copiedText: String?

    var body: some View {
        let hasLocalPeer = viewModel.syncVM.localPeerDeviceName != nil
        let isEmpty = viewModel.syncVM.syncStatusItems.isEmpty && !hasLocalPeer && networkInterfaces.isEmpty

        VStack(alignment: .leading) {
            if isEmpty {
                ContentUnavailableView(
                    "No Sync Status Available",
                    systemImage: "arrow.trianglehead.2.clockwise.rotate.90",
                    description: Text("Enable sync to see connected peers and their status")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.blurReplace)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        // Peer cards grid — bottom padding handled by VStack below
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 260, maximum: 520))],
                            spacing: 16
                        ) {
                            ForEach(viewModel.syncVM.syncStatusItems) { statusInfo in
                                // `.equatable()` gives SwiftUI a comparison point
                                // it did not previously have: `syncStatusCard` was
                                // a *function*, so there was no child-view boundary
                                // and every visible card rebuilt its whole tree —
                                // ~9 `Font.custom` resolutions, a gradient, a drawn
                                // shadow, two DisclosureGroups — on every presence
                                // tick. Now a card whose `SyncStatusInfo` is
                                // unchanged skips its body.
                                PeerCard(
                                    status: statusInfo,
                                    copiedText: copiedText,
                                    // The card's copy affordances are macOS-only
                                    // (double-click to copy), so the handler is
                                    // too — `copyToClipboard` does not exist on
                                    // iOS. The closure keeps `PeerCard` itself
                                    // platform-agnostic.
                                    onCopy: { text in
                                        #if os(macOS)
                                        copyToClipboard(text)
                                        #endif
                                    }
                                )
                                .equatable()
                                .transition(.asymmetric(
                                    insertion: .scale(scale: 0.88).combined(with: .opacity),
                                    removal: .opacity
                                ))
                            }

                            // Local Peer Info Card (included in same grid)
                            if let deviceName = viewModel.syncVM.localPeerDeviceName,
                               let sdkLanguage = viewModel.syncVM.localPeerSDKLanguage,
                               let sdkPlatform = viewModel.syncVM.localPeerSDKPlatform,
                               let sdkVersion = viewModel.syncVM.localPeerSDKVersion
                            {
                                LocalPeerInfoCard(
                                    deviceName: deviceName,
                                    sdkLanguage: sdkLanguage,
                                    sdkPlatform: sdkPlatform,
                                    sdkVersion: sdkVersion
                                )
                            }
                        }
                        // Keyed to *membership*, not to the whole array. Keyed to
                        // the array it re-armed on every sync tick, because
                        // `syncedUpToLocalCommitId` advances constantly and is part
                        // of `==` — so a 0.5s spring was being written into the
                        // transaction for this subtree many times a second. The
                        // animation exists to soften peers joining and leaving,
                        // which is exactly what the id list expresses.
                        .animation(
                            .spring(duration: 0.5, bounce: 0.2),
                            value: viewModel.syncVM.syncStatusItems.map(\.id)
                        )
                        .padding()

                        // Network interface cards — shown below peer cards with a divider
                        if !networkInterfaces.isEmpty {
                            HStack {
                                Rectangle()
                                    .fill(Color.secondary.opacity(0.25))
                                    .frame(height: 1)
                                Text("Local Network")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize()
                                Rectangle()
                                    .fill(Color.secondary.opacity(0.25))
                                    .frame(height: 1)
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 16)

                            LazyVGrid(
                                columns: [GridItem(.adaptive(minimum: 260, maximum: 520))],
                                spacing: 16
                            ) {
                                ForEach(networkInterfaces) { iface in
                                    NetworkInterfaceCard(info: iface)
                                        .transition(.asymmetric(
                                            insertion: .scale(scale: 0.88).combined(with: .opacity),
                                            removal: .opacity
                                        ))
                                }
                            }
                            .padding(.horizontal)
                            .padding(.bottom)
                        }
                    }
                    // Extra bottom clearance so the last card is never hidden behind
                    // the DetailBottomBar overlay (~56pt tall). Covers both the
                    // network-interfaces case and the peers-only case.
                    .padding(.bottom, 72)
                }
                .transition(.blurReplace)
            }
        }
        .animation(.smooth(duration: 0.45), value: viewModel.syncVM.syncStatusItems.isEmpty)
        .padding(.bottom, 28)
        .task {
            await loadNetworkDiagnostics()
        }
    }

    // MARK: - Helper Views

    #if os(macOS)
    /// Copies `text` to the system clipboard and briefly flashes the text green as confirmation.
    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copiedText = text
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            await MainActor.run {
                if copiedText == text {
                    copiedText = nil
                }
            }
        }
    }
    #endif

    private func loadNetworkDiagnostics() async {
        await NetworkDiagnosticsService.shared.requestLocationPermissionIfNeeded()
        let interfaces = await NetworkDiagnosticsService.shared.fetchAllInterfaces()
        withAnimation(.spring(duration: 0.5, bounce: 0.2)) {
            networkInterfaces = interfaces
        }
    }
}

/// One peer card.
///
/// This is a `View` **struct** rather than a method on `ConnectedPeersView`, and
/// that distinction is the point. As a method there was no child-view boundary,
/// so SwiftUI had nowhere to compare and every visible card rebuilt its entire
/// tree — roughly nine `Font.custom` resolutions, a gradient, a drawn shadow and
/// two `DisclosureGroup`s — on every presence tick, of which there are many per
/// second while a mesh is syncing. With `Equatable` + `.equatable()` at the call
/// site, a card whose peer did not change now skips its body outright.
///
/// `copiedText` is passed by value rather than as a `Binding` so it can take part
/// in equality; the copy action arrives as a closure, which `==` ignores.
private struct PeerCard: View, Equatable {
    let status: SyncStatusInfo
    let copiedText: String?
    let onCopy: (String) -> Void

    /// `nonisolated` because SwiftUI compares views off the main actor. The
    /// compared properties are plain value types, so this is safe.
    nonisolated static func == (lhs: PeerCard, rhs: PeerCard) -> Bool {
        lhs.status == rhs.status && lhs.copiedText == rhs.copiedText
    }

    var body: some View {
        let (startColor, endColor) = connectionGradient(for: status)
        return VStack(alignment: .leading, spacing: 12) {
            // Header with peer type and connection status
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    // Show device name if available, otherwise peer type
                    Text(status.deviceName ?? status.peerType)
                        .font(.headline)
                        .bold()
                        .foregroundStyle(.white)

                    // Show OS info if available
                    if let osInfo = status.osInfo {
                        HStack(spacing: 4) {
                            FontAwesomeText(icon: osIcon(for: osInfo), size: 12, color: .white.opacity(0.80))
                            Text(osInfo.displayName)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.80))
                        }
                    }

                    Text(status.id)
                        .font(.caption2)
                        .foregroundStyle(copiedText == status.id ? .green : .white.opacity(0.80))
                    #if os(macOS)
                        .help("Double-click to copy ID")
                        .onTapGesture(count: 2) { onCopy(status.id) }
                    #endif
                }

                Spacer()

                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor(for: status.syncSessionStatus))
                        .frame(width: 8, height: 8)
                    Text(status.syncSessionStatus)
                        .font(.subheadline)
                        .foregroundStyle(.white)
                }
            }

            Rectangle()
                .fill(Color.white.opacity(0.25))
                .frame(height: 1)

            // Peer information (new enrichment fields)
            VStack(alignment: .leading, spacing: 8) {
                // SDK Version
                if let sdkVersion = status.dittoSDKVersion {
                    HStack {
                        FontAwesomeText(icon: SystemIcon.sdk, size: 12, color: .white.opacity(0.80))
                        Text("Ditto SDK: \(sdkVersion)")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.80))
                    }
                }

                // Connection address
                if let addressInfo = status.addressInfo {
                    HStack {
                        FontAwesomeText(icon: connectionIcon(for: addressInfo.connectionType), size: 12, color: .white.opacity(0.80))
                        Text(addressInfo.displayText)
                            .font(.caption)
                            .foregroundStyle(copiedText == addressInfo.displayText ? .green : .white.opacity(0.80))
                        #if os(macOS)
                            .help("Double-click to copy address")
                            .onTapGesture(count: 2) { onCopy(addressInfo.displayText) }
                        #endif
                    }
                }

                // Identity metadata (collapsible with chevron)
                if let metadata = status.identityMetadata {
                    DisclosureGroup {
                        ScrollView {
                            Text(metadata)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.80))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 4)
                        }
                        .frame(maxHeight: 150)
                    } label: {
                        HStack {
                            FontAwesomeText(icon: SystemIcon.circleInfo, size: 12, color: .white.opacity(0.80))
                            Text("Identity Metadata")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.80))
                        }
                    }
                    .tint(.white)
                }

                // Peer metadata (collapsible with chevron)
                if let metadata = status.peerMetadata {
                    DisclosureGroup {
                        ScrollView {
                            Text(metadata)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.80))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 4)
                        }
                        .frame(maxHeight: 150)
                    } label: {
                        HStack {
                            FontAwesomeText(icon: SystemIcon.circleInfo, size: 12, color: .white.opacity(0.80))
                            Text("Peer Metadata")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.80))
                        }
                    }
                    .tint(.white)
                }

                // Active connections (always visible)
                if let connections = status.connections, !connections.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            FontAwesomeText(icon: SystemIcon.link, size: 12, color: .white.opacity(0.80))
                            Text("Active Connections (\(connections.count))")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.80))
                        }

                        ForEach(connections) { connection in
                            connectionBadge(for: connection, currentPeerId: status.id)
                        }
                    }
                }

                // Existing sync information
                if let commitId = status.syncedUpToLocalCommitId {
                    HStack {
                        FontAwesomeText(icon: SystemIcon.circleCheck, size: 12, color: .white)
                        Text("Synced to commit: \(commitId)")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.80))
                    }
                }

                HStack {
                    FontAwesomeText(icon: SystemIcon.clock, size: 12, color: .white.opacity(0.80))
                    Text("Last update: \(status.formattedLastUpdate)")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.80))
                }
            }

            Spacer(minLength: 0)
        }
        .padding()
        .frame(minHeight: 280, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(LinearGradient(
                    colors: [startColor, endColor],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .shadow(color: Color.black.opacity(0.25), radius: 4, x: 0, y: 2)
        )
        .animation(.easeInOut(duration: 0.4), value: dominantTypeKey(for: status))
    }

    private func connectionBadge(for connection: ConnectionInfo, currentPeerId: String) -> some View {
        HStack(spacing: 6) {
            FontAwesomeText(icon: connection.type.icon, size: 12, color: .white.opacity(0.80))

            VStack(alignment: .leading, spacing: 2) {
                Text(connection.type.displayName)
                    .font(.caption)
                    .foregroundStyle(.white)

                if let distance = connection.displayDistance {
                    Text("Distance: \(distance)")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.80))
                }
            }

            Spacer()
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white.opacity(0.12))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.20)))
        )
    }

    // MARK: - Helper Functions

    private func connectionGradient(for status: SyncStatusInfo) -> (Color, Color) {
        switch status.dominantConnectionType {
        case "cloud": return (SyncStatusInfo.cloudCardColor, SyncStatusInfo.cloudCardDarkColor)
        case "websocket": return (ConnectionType.webSocket.cardColor, ConnectionType.webSocket.cardDarkColor)
        case "lan": return (ConnectionType.accessPoint.cardColor, ConnectionType.accessPoint.cardDarkColor)
        case "p2p": return (ConnectionType.p2pWiFi.cardColor, ConnectionType.p2pWiFi.cardDarkColor)
        case "multicast": return (ConnectionType.multicast.cardColor, ConnectionType.multicast.cardDarkColor)
        case "bluetooth": return (ConnectionType.bluetooth.cardColor, ConnectionType.bluetooth.cardDarkColor)
        default: return (ConnectionType.unknown("").cardColor, ConnectionType.unknown("").cardDarkColor)
        }
    }

    private func dominantTypeKey(for status: SyncStatusInfo) -> String {
        status.dominantConnectionType
    }

    private func statusColor(for status: String) -> Color {
        switch status {
        case "Connected":
            return .green
        case "Connecting":
            return .orange
        case "Disconnected":
            return .red
        default:
            return .gray
        }
    }

    private func osIcon(for os: PeerOS) -> FAIcon {
        switch os {
        case .iOS:
            return PlatformIcon.iOS
        case .android:
            return PlatformIcon.android
        case .macOS:
            return PlatformIcon.apple
        case .linux:
            return PlatformIcon.linux
        case .windows:
            return PlatformIcon.windows
        case .unknown:
            return SystemIcon.question
        }
    }

    private func connectionIcon(for connectionType: String) -> FAIcon {
        let type = connectionType.lowercased()
        if type.contains("wifi") || type.contains("wireless") {
            return ConnectivityIcon.wifi
        } else if type.contains("bluetooth") || type.contains("ble") {
            return ConnectivityIcon.bluetooth
        } else if type.contains("websocket") || type.contains("internet") {
            return ConnectivityIcon.network
        } else if type.contains("lan") || type.contains("ethernet") {
            return ConnectivityIcon.ethernet
        } else {
            return ConnectivityIcon.broadcastTower
        }
    }
}
