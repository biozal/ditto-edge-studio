import SwiftUI

/// Displays connected peers in a responsive grid layout (2-3 columns based on window width).
///
/// **Layout**:
/// - < 900px width: 2 columns
/// - >= 900px width: 3 columns
/// - Uses LazyVGrid for efficient rendering of large peer lists
///
/// **Backpressure**: Observer updates throttled to match UI render capacity (see SystemRepository).
///
/// **Stable Ordering**: Peers appear in consistent order (no ORDER BY in DQL query).
struct ConnectedPeersView: View {
    @Bindable var viewModel: MainStudioView.ViewModel
    @State private var availableWidth: CGFloat = 0
    @State private var columnCount = 2
    @State private var networkInterfaces: [NetworkInterfaceInfo] = []

    var body: some View {
        VStack(alignment: .leading) {
            GeometryReader { geometry in
                let hasLocalPeer = viewModel.localPeerDeviceName != nil
                let isEmpty = viewModel.syncStatusItems.isEmpty && !hasLocalPeer && networkInterfaces.isEmpty

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
                            // Peer cards grid
                            LazyVGrid(
                                columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: columnCount),
                                spacing: 16
                            ) {
                                ForEach(viewModel.syncStatusItems) { statusInfo in
                                    syncStatusCard(for: statusInfo)
                                        .transition(.asymmetric(
                                            insertion: .scale(scale: 0.88).combined(with: .opacity),
                                            removal: .opacity
                                        ))
                                }

                                // Local Peer Info Card (included in same grid)
                                if let deviceName = viewModel.localPeerDeviceName,
                                   let sdkLanguage = viewModel.localPeerSDKLanguage,
                                   let sdkPlatform = viewModel.localPeerSDKPlatform,
                                   let sdkVersion = viewModel.localPeerSDKVersion
                                {
                                    LocalPeerInfoCard(
                                        deviceName: deviceName,
                                        sdkLanguage: sdkLanguage,
                                        sdkPlatform: sdkPlatform,
                                        sdkVersion: sdkVersion
                                    )
                                }
                            }
                            .animation(.spring(duration: 0.5, bounce: 0.2), value: viewModel.syncStatusItems)
                            .padding()

                            // Network interface cards — shown below peer cards with a divider
                            if !networkInterfaces.isEmpty {
                                HStack {
                                    Rectangle()
                                        .fill(Color.secondary.opacity(0.25))
                                        .frame(height: 1)
                                    Text("Local Network")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .fixedSize()
                                    Rectangle()
                                        .fill(Color.secondary.opacity(0.25))
                                        .frame(height: 1)
                                }
                                .padding(.horizontal)
                                .padding(.top, 16)
                                .padding(.bottom, 8)

                                LazyVGrid(
                                    columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: columnCount),
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
                    }
                    .transition(.blurReplace)
                    .onAppear {
                        updateColumnCount(for: geometry.size.width)
                    }
                    .onChange(of: geometry.size.width) { _, newValue in
                        updateColumnCount(for: newValue)
                    }
                }
            }
            .animation(.smooth(duration: 0.45), value: viewModel.syncStatusItems.isEmpty)
        }
        .padding(.bottom, 28) // Add padding for status bar height
        .task {
            await loadNetworkDiagnostics()
        }
    }

    // MARK: - Helper Views

    private func syncStatusCard(for status: SyncStatusInfo) -> some View {
        let (startColor, endColor) = connectionGradient(for: status)
        return VStack(alignment: .leading, spacing: 12) {
            // Header with peer type and connection status
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    // Show device name if available, otherwise peer type
                    Text(status.deviceName ?? status.peerType)
                        .font(.headline)
                        .bold()
                        .foregroundColor(.white)

                    // Show OS info if available
                    if let osInfo = status.osInfo {
                        HStack(spacing: 4) {
                            FontAwesomeText(icon: osIcon(for: osInfo), size: 12, color: .white.opacity(0.80))
                            Text(osInfo.displayName)
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.80))
                        }
                    }

                    Text(status.id)
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.80))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor(for: status.syncSessionStatus))
                        .frame(width: 8, height: 8)
                    Text(status.syncSessionStatus)
                        .font(.subheadline)
                        .foregroundColor(.white)
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
                            .foregroundColor(.white.opacity(0.80))
                    }
                }

                // Connection address
                if let addressInfo = status.addressInfo {
                    HStack {
                        FontAwesomeText(icon: connectionIcon(for: addressInfo.connectionType), size: 12, color: .white.opacity(0.80))
                        Text(addressInfo.displayText)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.80))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                // Identity metadata (collapsible with chevron)
                if let metadata = status.identityMetadata {
                    DisclosureGroup {
                        ScrollView {
                            Text(metadata)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.white.opacity(0.80))
                                .textSelection(.enabled)
                                .padding(.vertical, 4)
                        }
                        .frame(maxHeight: 150)
                    } label: {
                        HStack {
                            FontAwesomeText(icon: SystemIcon.circleInfo, size: 12, color: .white.opacity(0.80))
                            Text("Identity Metadata")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.80))
                        }
                    }
                }

                // Peer metadata (collapsible with chevron)
                if let metadata = status.peerMetadata {
                    DisclosureGroup {
                        ScrollView {
                            Text(metadata)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.white.opacity(0.80))
                                .textSelection(.enabled)
                                .padding(.vertical, 4)
                        }
                        .frame(maxHeight: 150)
                    } label: {
                        HStack {
                            FontAwesomeText(icon: SystemIcon.circleInfo, size: 12, color: .white.opacity(0.80))
                            Text("Peer Metadata")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.80))
                        }
                    }
                }

                // Active connections (always visible)
                if let connections = status.connections, !connections.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            FontAwesomeText(icon: SystemIcon.link, size: 12, color: .white.opacity(0.80))
                            Text("Active Connections (\(connections.count))")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.80))
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
                            .foregroundColor(.white.opacity(0.80))
                    }
                }

                HStack {
                    FontAwesomeText(icon: SystemIcon.clock, size: 12, color: .white.opacity(0.80))
                    Text("Last update: \(status.formattedLastUpdate)")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.80))
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
                    .foregroundColor(.white)

                if let distance = connection.displayDistance {
                    Text("Distance: \(distance)")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.80))
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
        if status.isDittoServer {
            return (SyncStatusInfo.cloudCardColor, SyncStatusInfo.cloudCardDarkColor)
        }
        let connections = status.connections ?? []
        if connections
            .contains(where: { $0.type == .webSocket }) { return (ConnectionType.webSocket.cardColor, ConnectionType.webSocket.cardDarkColor) }
        if connections.contains(where: { $0.type == .accessPoint }) { return (
            ConnectionType.accessPoint.cardColor,
            ConnectionType.accessPoint.cardDarkColor
        ) }
        if connections.contains(where: { $0.type == .p2pWiFi }) { return (ConnectionType.p2pWiFi.cardColor, ConnectionType.p2pWiFi.cardDarkColor) }
        if connections
            .contains(where: { $0.type == .bluetooth }) { return (ConnectionType.bluetooth.cardColor, ConnectionType.bluetooth.cardDarkColor) }
        return (ConnectionType.unknown("").cardColor, ConnectionType.unknown("").cardDarkColor)
    }

    private func dominantTypeKey(for status: SyncStatusInfo) -> String {
        if status.isDittoServer { return "cloud" }
        let connections = status.connections ?? []
        if connections.contains(where: { $0.type == .webSocket }) { return "websocket" }
        if connections.contains(where: { $0.type == .accessPoint }) { return "lan" }
        if connections.contains(where: { $0.type == .p2pWiFi }) { return "p2p" }
        if connections.contains(where: { $0.type == .bluetooth }) { return "bluetooth" }
        return "unknown"
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

    private func updateColumnCount(for width: CGFloat) {
        let newColumnCount

            // Breakpoint: < 900px = 2 columns, >= 900px = 3 columns
            // Minimum comfortable card width: ~350px
            = if width < 900
        {
            2
        } else {
            3
        }

        if columnCount != newColumnCount {
            columnCount = newColumnCount
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

    private func loadNetworkDiagnostics() async {
        await NetworkDiagnosticsService.shared.requestLocationPermissionIfNeeded()
        let interfaces = await NetworkDiagnosticsService.shared.fetchAllInterfaces()
        withAnimation(.spring(duration: 0.5, bounce: 0.2)) {
            networkInterfaces = interfaces
        }
    }
}
