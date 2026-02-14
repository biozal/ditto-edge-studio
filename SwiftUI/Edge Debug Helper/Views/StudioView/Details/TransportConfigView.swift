import SwiftUI

struct TransportConfigView: View {
    @EnvironmentObject private var appState: AppState
    @State private var viewModel: ViewModel

    init() {
        self._viewModel = State(initialValue: ViewModel())
    }

    var body: some View {
        Form {
            // Warning Section
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        FontAwesomeText(
                            icon: StatusIcon.triangleExclamation,
                            size: 16,
                            color: .orange
                        )

                        Text("Changing transport settings will temporarily stop sync and disconnect all peers. Active sync operations will be interrupted.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(8)
                }
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
                                .foregroundColor(.secondary)
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
                                .foregroundColor(.secondary)
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
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            // Cloud Sync Section
            Section("Cloud Sync") {
                Toggle(isOn: $viewModel.isCloudSyncEnabled) {
                    HStack(spacing: 8) {
                        FontAwesomeText(
                            icon: ConnectivityIcon.cloud,
                            size: 14,
                            color: viewModel.isCloudSyncEnabled ? .cyan : .secondary
                        )
                        VStack(alignment: .leading, spacing: 2) {
                            Text("WebSocket Sync")
                                .font(.body)
                            Text("Sync via Ditto Big Peer cloud server")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            // Apply Button Section
            Section {
                VStack(spacing: 12) {
                    // Progress Status (shown when operation is in progress, complete, or error)
                    if viewModel.currentStep != .idle {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 12) {
                                // Icon based on state
                                if viewModel.currentStep.isInProgress {
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

                                // Status message
                                Text(viewModel.currentStep.message)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(12)
                            .background(backgroundColor)
                            .cornerRadius(8)
                        }
                        .transition(.opacity.combined(with: .scale))
                    }

                    // Apply Button
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
                    .disabled(viewModel.currentStep.isInProgress || !viewModel.hasChanges)
                    .buttonStyle(.borderedProminent)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: viewModel.currentStep)
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

    private var backgroundColor: Color {
        if viewModel.currentStep.isInProgress {
            return Color.blue.opacity(0.1)
        } else if viewModel.currentStep.isComplete {
            return Color.green.opacity(0.1)
        } else if viewModel.currentStep.isError {
            return Color.red.opacity(0.1)
        }
        return Color.clear
    }
}

// MARK: - ViewModel
extension TransportConfigView {
    @Observable
    class ViewModel {
        // Current UI state (bound to toggles)
        var isBluetoothLeEnabled: Bool = true
        var isLanEnabled: Bool = true
        var isAwdlEnabled: Bool = true
        var isCloudSyncEnabled: Bool = true

        // Original settings (for change detection)
        private var originalBluetoothLeEnabled: Bool = true
        private var originalLanEnabled: Bool = true
        private var originalAwdlEnabled: Bool = true
        private var originalCloudSyncEnabled: Bool = true

        // Progress tracking
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
                case .error(let msg): return msg
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
                if case .error = self { return true }
                return false
            }

            var isComplete: Bool {
                if case .complete = self { return true }
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
            isCloudSyncEnabled != originalCloudSyncEnabled
        }

        init() {}

        /// Loads current transport settings from selected app config
        func loadCurrentSettings() async {
            let appConfig = await dittoManager.dittoSelectedAppConfig
            guard let appConfig = appConfig else { return }

            // Load current settings into UI
            isBluetoothLeEnabled = appConfig.isBluetoothLeEnabled
            isLanEnabled = appConfig.isLanEnabled
            isAwdlEnabled = appConfig.isAwdlEnabled
            isCloudSyncEnabled = appConfig.isCloudSyncEnabled

            // Store originals for change detection
            originalBluetoothLeEnabled = appConfig.isBluetoothLeEnabled
            originalLanEnabled = appConfig.isLanEnabled
            originalAwdlEnabled = appConfig.isAwdlEnabled
            originalCloudSyncEnabled = appConfig.isCloudSyncEnabled
        }

        /// Applies transport configuration changes with proper sync and observer lifecycle
        /// Follows the MainStudioView.toggleSync() pattern for observer management
        func applyTransportConfig(appState: AppState) async {
            currentStep = .stoppingSync

            do {
                // STEP 1: STOP SYNC (following MainStudioView.stopSync pattern)
                await DittoManager.shared.selectedAppStopSync()

                // Stop observers to prevent stale data updates
                await SystemRepository.shared.stopObserver()

                // STEP 2: APPLY CONFIGURATION
                currentStep = .applyingConfig

                try await DittoManager.shared.applyTransportConfig(
                    isBluetoothLeEnabled: isBluetoothLeEnabled,
                    isLanEnabled: isLanEnabled,
                    isAwdlEnabled: isAwdlEnabled,
                    isCloudSyncEnabled: isCloudSyncEnabled
                )

                // Update stored app config in database for persistence
                if let appConfig = await dittoManager.dittoSelectedAppConfig {
                    appConfig.isBluetoothLeEnabled = isBluetoothLeEnabled
                    appConfig.isLanEnabled = isLanEnabled
                    appConfig.isAwdlEnabled = isAwdlEnabled
                    appConfig.isCloudSyncEnabled = isCloudSyncEnabled

                    try await DatabaseRepository.shared.updateDittoAppConfig(appConfig)
                }

                // STEP 3: RESTART SYNC (following MainStudioView.startSync pattern)
                currentStep = .restartingSync

                try await DittoManager.shared.selectedAppStartSync()

                // Restart observers with fresh connections
                do {
                    try await SystemRepository.shared.registerSyncStatusObserver()
                    try await SystemRepository.shared.registerConnectionsPresenceObserver()
                } catch {
                    print("Warning: Failed to restart observers: \(error)")
                    // Non-fatal - sync is running even if observers failed
                }

                // STEP 4: SUCCESS
                currentStep = .complete

                // Update original values after successful save (reset change detection)
                originalBluetoothLeEnabled = isBluetoothLeEnabled
                originalLanEnabled = isLanEnabled
                originalAwdlEnabled = isAwdlEnabled
                originalCloudSyncEnabled = isCloudSyncEnabled

            } catch {
                currentStep = .error(error.localizedDescription)
                appState.setError(error)
            }
        }
    }
}
