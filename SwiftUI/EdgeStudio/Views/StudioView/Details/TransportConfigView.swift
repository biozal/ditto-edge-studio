import SwiftUI

@MainActor
struct TransportConfigView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel: ViewModel

    init() {
        _viewModel = State(initialValue: ViewModel())
    }

    var body: some View {
        Form {
            // Banner Section: warning at rest, replaced by status during/after apply
            Section {
                HStack(alignment: .top, spacing: 12) {
                    if viewModel.currentStep == .idle {
                        FontAwesomeText(
                            icon: StatusIcon.triangleExclamation,
                            size: 16,
                            color: .orange
                        )
                    } else if viewModel.currentStep.isInProgress {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.8)
                    } else if viewModel.currentStep.isComplete {
                        FontAwesomeText(
                            icon: StatusIcon.circleCheck,
                            size: 16,
                            color: .green
                        )
                    } else if viewModel.currentStep.isError {
                        FontAwesomeText(
                            icon: StatusIcon.triangleExclamation,
                            size: 16,
                            color: .red
                        )
                    }

                    Text(viewModel.currentStep == .idle
                        ? "Changing transport settings will temporarily stop sync and disconnect all peers. Active sync operations will be interrupted."
                        : viewModel.currentStep.message
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .listRowBackground(bannerBackgroundColor)
                .listRowInsets(EdgeInsets())
                .animation(.easeInOut(duration: 0.3), value: viewModel.currentStep)
            }

            // Peer-to-Peer Transports Section
            Section("Peer-to-Peer Transports") {
                // Bluetooth LE
                Toggle(isOn: $viewModel.isBluetoothLeEnabled) {
                    HStack(spacing: 8) {
                        FontAwesomeText(
                            icon: ConnectivityIcon.bluetooth,
                            size: 14,
                            color: viewModel.isBluetoothLeEnabled ? .blue : .secondary
                        )
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Bluetooth LE")
                                .font(.body)
                            Text("Direct peer-to-peer sync via Bluetooth Low Energy")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // LAN
                Toggle(isOn: $viewModel.isLanEnabled) {
                    HStack(spacing: 8) {
                        FontAwesomeText(
                            icon: ConnectivityIcon.ethernet,
                            size: 14,
                            color: viewModel.isLanEnabled ? .green : .secondary
                        )
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Local Area Network")
                                .font(.body)
                            Text("Sync with peers on the same WiFi or wired network")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // AWDL
                Toggle(isOn: $viewModel.isAwdlEnabled) {
                    HStack(spacing: 8) {
                        FontAwesomeText(
                            icon: ConnectivityIcon.wifi,
                            size: 14,
                            color: viewModel.isAwdlEnabled ? .purple : .secondary
                        )
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Apple Wireless Direct Link")
                                .font(.body)
                            Text("High-speed peer-to-peer WiFi (Apple devices only)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Multicast (beta)
                Toggle(isOn: $viewModel.isMulticastEnabled) {
                    HStack(spacing: 8) {
                        FontAwesomeText(
                            icon: ConnectivityIcon.broadcast,
                            size: 14,
                            color: viewModel.isMulticastEnabled ? Color(red: 0.667, green: 0.49, blue: 0.0) : .secondary
                        )
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Multicast (beta)")
                                .font(.body)
                            Text("Reliable UDP multicast — all peers on the same Wi-Fi segment")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Advanced multicast settings (only meaningful when enabled)
                if viewModel.isMulticastEnabled {
                    TextField("Group Address", text: $viewModel.multicastGroupAddress)
                        .textFieldStyle(.roundedBorder)
                    if !viewModel.isMulticastGroupValid {
                        Text("Must be a class-D IPv4 address (224.0.0.0–239.255.255.255)")
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }

                    TextField("Port", text: $viewModel.multicastPortText)
                        .textFieldStyle(.roundedBorder)
                    #if os(macOS)
                        .frame(maxWidth: 120)
                    #endif
                    if !viewModel.isMulticastPortValid {
                        Text("UDP port 1–65535 (all peers must match)")
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }

                    TextField("Interface Name (optional)", text: $viewModel.multicastInterfaceName)
                        .textFieldStyle(.roundedBorder)
                    Text("Blank lets the OS pick the interface")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            // Apply Button Section
            Section {
                Button {
                    Task {
                        await viewModel.applyTransportConfig(appState: appState)
                    }
                } label: {
                    HStack {
                        if viewModel.currentStep.isInProgress {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .scaleEffect(0.8)
                                .padding(.trailing, 4)
                        }
                        Text(buttonText)
                    }
                    .frame(maxWidth: .infinity)
                }
                .disabled(viewModel.currentStep.isInProgress || !viewModel.hasChanges || !viewModel.isMulticastInputValid)
                .buttonStyle(.glassProminent)
                .tint(.dittoYellow)
                .foregroundStyle(.black)
            }
        }
        .formStyle(.grouped)
        .task {
            await viewModel.loadCurrentSettings()
        }
    }

    // MARK: - Helper Properties

    private var buttonText: String {
        if viewModel.currentStep.isInProgress {
            return "Applying Changes..."
        }
        return "Apply Transport Settings"
    }

    private var bannerBackgroundColor: Color {
        if viewModel.currentStep == .idle {
            return Color.orange.opacity(0.1)
        } else if viewModel.currentStep.isInProgress {
            return Color.blue.opacity(0.1)
        } else if viewModel.currentStep.isComplete {
            return Color.green.opacity(0.1)
        } else if viewModel.currentStep.isError {
            return Color.red.opacity(0.1)
        }
        return Color.orange.opacity(0.1)
    }
}

// MARK: - ViewModel

extension TransportConfigView {
    @MainActor
    @Observable
    class ViewModel {
        // Current UI state (bound to toggles)
        var isBluetoothLeEnabled = true
        var isLanEnabled = true
        var isAwdlEnabled = true
        var isMulticastEnabled = false
        var multicastGroupAddress = MulticastConfig.defaultGroupAddress
        var multicastPortText = String(MulticastConfig.defaultPort)
        var multicastInterfaceName = ""

        // Original settings (for change detection)
        private var originalBluetoothLeEnabled = true
        private var originalLanEnabled = true
        private var originalAwdlEnabled = true
        private var originalMulticastEnabled = false
        private var originalMulticastGroupAddress = MulticastConfig.defaultGroupAddress
        private var originalMulticastPortText = String(MulticastConfig.defaultPort)
        private var originalMulticastInterfaceName = ""

        /// Multicast field validation — Apply stays disabled while an enabled
        /// multicast config is invalid (port 0 is rejected: the SDK reads it as
        /// "any port" and group rendezvous silently breaks).
        var isMulticastGroupValid: Bool {
            MulticastConfig.isValidGroupAddress(multicastGroupAddress)
        }

        var isMulticastPortValid: Bool {
            MulticastConfig.parsePort(multicastPortText) != nil
        }

        var isMulticastInputValid: Bool {
            !isMulticastEnabled || (isMulticastGroupValid && isMulticastPortValid)
        }

        /// The current UI state as a validated multicast config.
        var multicastConfig: MulticastConfig {
            let interface = multicastInterfaceName.trimmingCharacters(in: .whitespaces)
            return MulticastConfig(
                isEnabled: isMulticastEnabled,
                groupAddress: multicastGroupAddress.trimmingCharacters(in: .whitespaces),
                port: MulticastConfig.parsePort(multicastPortText) ?? MulticastConfig.defaultPort,
                interfaceName: interface.isEmpty ? nil : interface
            )
        }

        /// Progress tracking
        enum OperationStep: Equatable {
            case idle
            case stoppingSync
            case applyingConfig
            case restartingSync
            case complete
            case error(String)

            var message: String {
                switch self {
                case .idle: return ""
                case .stoppingSync: return "Stopping sync and cleaning up observers..."
                case .applyingConfig: return "Applying transport configuration..."
                case .restartingSync: return "Restarting sync and reconnecting..."
                case .complete: return "Configuration applied successfully"
                case let .error(msg): return msg
                }
            }

            var isInProgress: Bool {
                switch self {
                case .stoppingSync, .applyingConfig, .restartingSync:
                    return true
                default:
                    return false
                }
            }

            var isError: Bool {
                if case .error = self {
                    return true
                }
                return false
            }

            var isComplete: Bool {
                if case .complete = self {
                    return true
                }
                return false
            }
        }

        var currentStep: OperationStep = .idle

        private let dittoManager = DittoManager.shared

        /// Detects if user has made changes from original settings
        var hasChanges: Bool {
            isBluetoothLeEnabled != originalBluetoothLeEnabled ||
                isLanEnabled != originalLanEnabled ||
                isAwdlEnabled != originalAwdlEnabled ||
                isMulticastEnabled != originalMulticastEnabled ||
                multicastGroupAddress != originalMulticastGroupAddress ||
                multicastPortText != originalMulticastPortText ||
                multicastInterfaceName != originalMulticastInterfaceName
        }

        init() {}

        /// Loads current transport settings from selected app config atomically,
        /// assigning each `is*` and `original*` pair together so `hasChanges` never
        /// transiently flips to `true` during load.
        func loadCurrentSettings() async {
            guard let appConfig = await dittoManager.dittoSelectedAppConfig else { return }
            let ble = appConfig.isBluetoothLeEnabled
            let lan = appConfig.isLanEnabled
            let awdl = appConfig.isAwdlEnabled
            isBluetoothLeEnabled = ble; originalBluetoothLeEnabled = ble
            isLanEnabled = lan; originalLanEnabled = lan
            isAwdlEnabled = awdl; originalAwdlEnabled = awdl
            let mc = appConfig.isMulticastEnabled
            let mcGroup = appConfig.multicastGroupAddress
            let mcPort = String(appConfig.multicastPort)
            let mcInterface = appConfig.multicastInterfaceName ?? ""
            isMulticastEnabled = mc; originalMulticastEnabled = mc
            multicastGroupAddress = mcGroup; originalMulticastGroupAddress = mcGroup
            multicastPortText = mcPort; originalMulticastPortText = mcPort
            multicastInterfaceName = mcInterface; originalMulticastInterfaceName = mcInterface
        }

        /// Applies transport configuration changes with proper sync and observer lifecycle
        /// Follows the MainStudioView.toggleSync() pattern for observer management
        func applyTransportConfig(appState: AppState) async {
            guard currentStep == .idle else { return }
            currentStep = .stoppingSync

            do {
                // STEP 1: STOP SYNC
                await DittoManager.shared.selectedDatabaseStopSync()

                // Stop observers to prevent stale data updates
                await SystemRepository.shared.stopObserver()

                // STEP 2: APPLY CONFIGURATION
                currentStep = .applyingConfig

                try await DittoManager.shared.applyTransportConfig(
                    isBluetoothLeEnabled: isBluetoothLeEnabled,
                    isLanEnabled: isLanEnabled,
                    isAwdlEnabled: isAwdlEnabled,
                    multicast: multicastConfig
                )

                // Update stored app config in database for persistence. Revert the
                // in-memory mutation if the persist fails, so the live config never
                // diverges from disk on the error path.
                if let appConfig = await dittoManager.dittoSelectedAppConfig {
                    let multicast = multicastConfig
                    let previous = (
                        appConfig.isBluetoothLeEnabled, appConfig.isLanEnabled, appConfig.isAwdlEnabled,
                        appConfig.isMulticastEnabled, appConfig.multicastGroupAddress,
                        appConfig.multicastPort, appConfig.multicastInterfaceName
                    )
                    appConfig.isBluetoothLeEnabled = isBluetoothLeEnabled
                    appConfig.isLanEnabled = isLanEnabled
                    appConfig.isAwdlEnabled = isAwdlEnabled
                    appConfig.isMulticastEnabled = multicast.isEnabled
                    appConfig.multicastGroupAddress = multicast.groupAddress
                    appConfig.multicastPort = multicast.port
                    appConfig.multicastInterfaceName = multicast.interfaceName
                    do {
                        try await DatabaseRepository.shared.updateDittoAppConfig(appConfig)
                    } catch {
                        (
                            appConfig.isBluetoothLeEnabled, appConfig.isLanEnabled, appConfig.isAwdlEnabled,
                            appConfig.isMulticastEnabled, appConfig.multicastGroupAddress,
                            appConfig.multicastPort, appConfig.multicastInterfaceName
                        ) = previous
                        throw error
                    }
                }

                // STEP 3: RESTART SYNC
                currentStep = .restartingSync

                // Restarting sync re-applies the Advanced Configuration, which is
                // fail-closed on sync scopes and can therefore throw. The observers must
                // be restarted either way: letting the throw skip them left the Sync tab
                // dead (sync off, no status or presence updates) until the database was
                // closed and reopened.
                var syncStartError: Error?
                do {
                    try await DittoManager.shared.selectedDatabaseStartSync()
                } catch {
                    syncStartError = error
                }

                // Restart observers with fresh connections
                do {
                    try await SystemRepository.shared.registerSyncStatusObserver()
                    try await SystemRepository.shared.registerConnectionsPresenceObserver()
                } catch {
                    Log.warning("Failed to restart observers: \(error.localizedDescription)")
                }

                if let syncStartError {
                    throw syncStartError
                }

                // STEP 4: SUCCESS
                currentStep = .complete

                originalBluetoothLeEnabled = isBluetoothLeEnabled
                originalLanEnabled = isLanEnabled
                originalAwdlEnabled = isAwdlEnabled
                originalMulticastEnabled = isMulticastEnabled
                originalMulticastGroupAddress = multicastGroupAddress
                originalMulticastPortText = multicastPortText
                originalMulticastInterfaceName = multicastInterfaceName
            } catch {
                currentStep = .error(error.localizedDescription)
                appState.setError(error)
            }
        }
    }
}
