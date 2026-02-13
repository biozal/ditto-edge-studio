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
    @State private var columnCount: Int = 2

    var body: some View {
        VStack(alignment: viewModel.syncStatusItems.isEmpty ? .center : .leading) {
            // Header with last update time
            HStack(alignment: .top, spacing: 12) {
                // Left: Title
                Text("Connected Peers")
                    .font(.title2)
                    .bold()

                Spacer()

                // Right: Timestamp only (filter removed - always shows connected peers)
                VStack(alignment: .trailing, spacing: 4) {
                    // Timestamp
                    if let statusInfo = viewModel.syncStatusItems.first {
                        Text("Last updated: \(statusInfo.formattedLastUpdate)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top)

            if viewModel.syncStatusItems.isEmpty {
                Spacer()
                HStack {
                    Spacer()
                    ContentUnavailableView(
                        "No Sync Status Available",
                        systemImage: "arrow.trianglehead.2.clockwise.rotate.90",
                        description: Text("Enable sync to see connected peers and their status")
                    )
                    Spacer()
                }
                Spacer()
            } else {
                GeometryReader { geometry in
                    ScrollView {
                        LazyVGrid(
                            columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: columnCount),
                            spacing: 16
                        ) {
                            ForEach(viewModel.syncStatusItems) { statusInfo in
                                syncStatusCard(for: statusInfo)
                            }

                            // Local Peer Info Card (included in same grid)
                            if let deviceName = viewModel.localPeerDeviceName,
                               let sdkLanguage = viewModel.localPeerSDKLanguage,
                               let sdkPlatform = viewModel.localPeerSDKPlatform,
                               let sdkVersion = viewModel.localPeerSDKVersion {
                                LocalPeerInfoCard(
                                    deviceName: deviceName,
                                    sdkLanguage: sdkLanguage,
                                    sdkPlatform: sdkPlatform,
                                    sdkVersion: sdkVersion
                                )
                            }
                        }
                        .padding()
                    }
                    .onAppear {
                        updateColumnCount(for: geometry.size.width)
                    }
                    .onChange(of: geometry.size.width) { oldValue, newValue in
                        updateColumnCount(for: newValue)
                    }
                }
            }
        }
        .padding(.bottom, 28)  // Add padding for status bar height
    }

    // MARK: - Helper Views

    private func syncStatusCard(for status: SyncStatusInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with peer type and connection status
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    // Show device name if available, otherwise peer type
                    Text(status.deviceName ?? status.peerType)
                        .font(.headline)
                        .bold()

                    // Show OS info if available
                    if let osInfo = status.osInfo {
                        HStack(spacing: 4) {
                            FontAwesomeText(icon: osIcon(for: osInfo), size: 12, color: .secondary)
                            Text(osInfo.displayName)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Text(status.id)
                        .font(.caption2)
                        .foregroundColor(.secondary)
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
                        .foregroundColor(statusColor(for: status.syncSessionStatus))
                }
            }

            Divider()

            // Peer information (new enrichment fields)
            VStack(alignment: .leading, spacing: 8) {
                // SDK Version
                if let sdkVersion = status.dittoSDKVersion {
                    HStack {
                        FontAwesomeText(icon: SystemIcon.sdk, size: 12, color: .secondary)
                        Text("Ditto SDK: \(sdkVersion)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // Connection address
                if let addressInfo = status.addressInfo {
                    HStack {
                        FontAwesomeText(icon: connectionIcon(for: addressInfo.connectionType), size: 12, color: .secondary)
                        Text(addressInfo.displayText)
                            .font(.caption)
                            .foregroundColor(.secondary)
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
                                .foregroundColor(.secondary)
                                .textSelection(.enabled)
                                .padding(.vertical, 4)
                        }
                        .frame(maxHeight: 150)
                    } label: {
                        HStack {
                            FontAwesomeText(icon: SystemIcon.circleInfo, size: 12, color: .secondary)
                            Text("Identity Metadata")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // Active connections (always visible)
                if let connections = status.connections, !connections.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            FontAwesomeText(icon: SystemIcon.link, size: 12, color: .secondary)
                            Text("Active Connections (\(connections.count))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        ForEach(connections) { connection in
                            connectionBadge(for: connection, currentPeerId: status.id)
                        }
                    }
                }

                // Existing sync information
                if let commitId = status.syncedUpToLocalCommitId {
                    HStack {
                        FontAwesomeText(icon: SystemIcon.circleCheck, size: 12, color: .green)
                        Text("Synced to commit: \(commitId)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                HStack {
                    FontAwesomeText(icon: SystemIcon.clock, size: 12, color: .secondary)
                    Text("Last update: \(status.formattedLastUpdate)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding()
        .frame(minHeight: 280, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
        )
    }

    private func connectionBadge(for connection: ConnectionInfo, currentPeerId: String) -> some View {
        HStack(spacing: 6) {
            FontAwesomeText(icon: connection.type.icon, size: 12, color: .secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(connection.type.displayName)
                    .font(.caption)
                    .foregroundColor(.primary)

                if let distance = connection.displayDistance {
                    Text("Distance: \(distance)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
        )
    }

    // MARK: - Helper Functions

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
        let newColumnCount: Int

        // Breakpoint: < 900px = 2 columns, >= 900px = 3 columns
        // Minimum comfortable card width: ~350px
        if width < 900 {
            newColumnCount = 2
        } else {
            newColumnCount = 3
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
}
