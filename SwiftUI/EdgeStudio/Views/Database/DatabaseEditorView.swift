import SwiftUI

@MainActor
struct DatabaseEditorView: View {
    @Environment(AppState.self) private var appState
    @Binding var isPresented: Bool
    /// Optional binding so the host (`ContentView`) can disable interactive
    /// dismiss while the form has uncommitted changes. When `nil`, the editor
    /// still surfaces its own confirmation dialog on Cancel.
    @Binding var hasUnsavedChanges: Bool
    @State private var viewModel: ViewModel
    /// Drives the "Discard changes?" confirmation when the user taps Cancel
    /// with an unsaved form. Cleared on every dismissal path.
    @State private var showDiscardConfirmation = false

    init(
        isPresented: Binding<Bool>,
        hasUnsavedChanges: Binding<Bool> = .constant(false),
        dittoAppConfig: DittoConfigForDatabase
    ) {
        _isPresented = isPresented
        _hasUnsavedChanges = hasUnsavedChanges
        _viewModel = State(initialValue: ViewModel(dittoAppConfig))
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                #if os(macOS)
                HStack {
                    Text(viewModel.databaseId == "" ? "Register Database" : "Edit Database")
                        .font(.title2.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                }
                .padding(.top, 4)
                .padding(.bottom, 12)
                #endif

                Form {
                    HStack {
                        Spacer()
                        Picker("", selection: $viewModel.mode) {
                            ForEach(AuthMode.allCases, id: \.self) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(maxWidth: 300)
                        .accessibilityIdentifier("AuthModePicker")
                        Spacer()
                    }

                    #if os(macOS)
                    Spacer()
                        .frame(height: 20)
                    #endif

                    Section("Basic Information") {
                        TextField("Name", text: $viewModel.name)
                            .lineLimit(1)
                            .padding(.bottom, 10)
                            .accessibilityIdentifier("NameTextField")
                    }

                    Section("Authorization Information") {
                        TextField("Database ID", text: $viewModel.databaseId)
                        #if os(macOS)
                            .textFieldStyle(.roundedBorder)
                        #endif
                            .font(.system(.body, design: .monospaced))
                            .lineLimit(1)
                            .trimOnPaste($viewModel.databaseId)
                            .padding(.bottom, 5)
                            .accessibilityIdentifier("DatabaseIdTextField")

                        authTokenField(for: viewModel.mode)
                    }

                    modeSpecificSections(for: viewModel.mode)
                }

                // Info panel for new database registration
                if viewModel.databaseId == "" {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "info.circle.fill")
                                .foregroundStyle(.blue)
                                .font(.system(size: 16))

                            Text(
                                "This information comes from the [Ditto Portal](https://portal.ditto.live) and is required in order to register a Ditto Database."
                            )
                            .font(.callout)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                            .tint(.blue)
                        }
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                    }
                    .padding(.horizontal)
                    .padding(.top, 10)
                }

                Spacer()
            }
            #if os(macOS)
            .padding(.leading, 16)
            .padding(.trailing, 24)
            .padding(.vertical, 16)
            #endif
            #if os(iOS)
            .navigationTitle(viewModel.databaseId == "" ? "Register Database" : "Edit Database")
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        attemptCancel()
                    } label: {
                        Label("Cancel", systemImage: "xmark")
                    }
                    .accessibilityIdentifier("CancelButton")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await viewModel.save(appState: appState)
                            isPresented = false
                        }
                    }
                    .disabled(viewModel.databaseId.isEmpty ||
                        viewModel.name.isEmpty ||
                        viewModel.developmentToken.isEmpty)
                    .accessibilityIdentifier("SaveButton")
                }
            }
        }
        .onAppear {
            // Sync the host's binding with whatever the view model currently
            // reports — covers the rare case where `@State` survives across a
            // sheet re-presentation with an updated config.
            hasUnsavedChanges = viewModel.hasUnsavedChanges
        }
        .onChange(of: viewModel.hasUnsavedChanges) { _, newValue in
            hasUnsavedChanges = newValue
        }
        .confirmationDialog(
            "Discard changes?",
            isPresented: $showDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button("Discard Changes", role: .destructive) {
                hasUnsavedChanges = false
                isPresented = false
            }
            Button("Keep Editing", role: .cancel) {}
        } message: {
            Text("Your edits to this database configuration will be lost.")
        }
    }

    /// Routes the Cancel button: confirms the discard intent when the form has
    /// unsaved edits, otherwise dismisses immediately. Used for the explicit
    /// Cancel toolbar action on both platforms; iOS swipe-to-dismiss is gated
    /// separately by `.interactiveDismissDisabled` on the hosting sheet.
    private func attemptCancel() {
        if viewModel.hasUnsavedChanges {
            showDiscardConfirmation = true
        } else {
            hasUnsavedChanges = false
            isPresented = false
        }
    }

    // MARK: - View Builders

    @ViewBuilder
    private func authTokenField(for mode: AuthMode) -> some View {
        switch mode {
        case .development:
            TextField("Development token", text: $viewModel.developmentToken)
            #if os(macOS)
                .textFieldStyle(.roundedBorder)
            #endif
                .lineLimit(1)
                .trimOnPaste($viewModel.developmentToken)
                .padding(.bottom, 10)
                .accessibilityIdentifier("TokenTextField")
        case .smallPeerOnly:
            TextField("Offline Token", text: $viewModel.developmentToken)
            #if os(macOS)
                .textFieldStyle(.roundedBorder)
            #endif
                .lineLimit(1)
                .trimOnPaste($viewModel.developmentToken)
                .padding(.bottom, 5)
                .accessibilityIdentifier("TokenTextField")

            Text("Required for sync activation in Small Peer Only mode.\nObtain from https://portal.ditto.live")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.bottom, 10)
        }
    }

    @ViewBuilder
    private func modeSpecificSections(for mode: AuthMode) -> some View {
        switch mode {
        case .smallPeerOnly:
            secretKeySection()
        case .development:
            serverInformationSection()
            httpApiSection()
        }
        developerOptionsSection()
    }

    private func developerOptionsSection() -> some View {
        Section("Developer Options") {
            Picker("SDK Log Level", selection: $viewModel.logLevel) {
                Text("Error").tag("error")
                Text("Warning").tag("warning")
                Text("Info (Default)").tag("info")
                Text("Debug").tag("debug")
                Text("Verbose").tag("verbose")
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("LogLevelPicker")

            Text("Controls DittoLogger.minimumLogLevel when this database is activated. Applied globally across all Ditto instances.")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading) {
                Toggle("Enable DQL Strict Mode", isOn: $viewModel.isStrictModeEnabled)
                    .padding(.bottom, 5)
                    .accessibilityIdentifier("StrictModeToggle")

                Text(
                    "⚠️ For most users of Ditto SDK 5.0 and later, strict mode should remain disabled. " +
                        "When disabled, nested objects are treated as MAPs by default, enabling field-level merging. " +
                        "Enable only if you require SDK 4.x compatibility or explicitly need REGISTER-typed objects. " +
                        "Mismatched settings across peers may cause nested fields to appear missing."
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 10)
            }
        }
    }

    private func secretKeySection() -> some View {
        Section("Optional Secret Key") {
            TextField("Shared Key", text: $viewModel.secretKey)
            #if os(macOS)
                .textFieldStyle(.roundedBorder)
            #endif
                .lineLimit(1)
                .padding(.bottom, 5)
                .accessibilityIdentifier("SecretKeyTextField")

            Text("Optional secret key for shared key identity encryption. Leave empty if not using Shared Key.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.bottom, 10)
        }
    }

    private func serverInformationSection() -> some View {
        // Ditto SDK 5.0 dropped the websocket URL requirement — only the
        // auth URL (now just "URL") is needed.
        Section("Ditto Server (BigPeer) Information") {
            TextField("URL", text: $viewModel.url)
            #if os(macOS)
                .textFieldStyle(.roundedBorder)
            #endif
                .lineLimit(1)
                .padding(.bottom, 10)
                .accessibilityIdentifier("UrlTextField")
        }
    }

    private func httpApiSection() -> some View {
        Section("Ditto Server - HTTP API - Optional") {
            TextField("HTTP API URL", text: $viewModel.httpApiUrl)
            #if os(macOS)
                .textFieldStyle(.roundedBorder)
            #endif
                .lineLimit(1)
                .padding(.bottom, 8)
                .accessibilityIdentifier("HttpApiUrlTextField")

            TextField("HTTP API Key", text: $viewModel.httpApiKey)
            #if os(macOS)
                .textFieldStyle(.roundedBorder)
            #endif
                .lineLimit(1)
                .padding(.bottom, 10)
                .accessibilityIdentifier("HttpApiKeyTextField")

            VStack(alignment: .leading) {
                Toggle("Allow untrusted certificates", isOn: $viewModel.allowUntrustedCerts)
                    .padding(.bottom, 5)
                    .accessibilityIdentifier("AllowUntrustedCertsToggle")

                Text(
                    "By allowing untrusted certificates, you are bypassing SSL certificate validation entirely, which poses significant security risks. This setting should only be used in development environments and never in production."
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 10)
            }
        }
    }
}

#Preview {
    DatabaseEditorView(isPresented: .constant(true), dittoAppConfig: DittoConfigForDatabase.new())
}

extension DatabaseEditorView {
    /// Immutable snapshot of every editable field at the time the editor
    /// opened. Used by `hasUnsavedChanges` to detect dirty state without
    /// observing every field individually.
    fileprivate struct OriginalSnapshot: Equatable {
        let name: String
        let databaseId: String
        let developmentToken: String
        let url: String
        let httpApiUrl: String
        let httpApiKey: String
        let mode: AuthMode
        let allowUntrustedCerts: Bool
        let secretKey: String
        let logLevel: String
        let isStrictModeEnabled: Bool
    }

    @MainActor
    @Observable
    class ViewModel {
        let _id: String
        var name: String
        var databaseId: String
        var developmentToken: String
        var url: String
        var httpApiUrl: String
        var httpApiKey: String
        var mode: AuthMode
        var allowUntrustedCerts: Bool
        var secretKey: String
        var logLevel: String
        var isStrictModeEnabled: Bool

        // Transport settings — preserved from existing config, not editable in this view
        var isBluetoothLeEnabled = true
        var isLanEnabled = true
        var isAwdlEnabled = true
        var isCloudSyncEnabled = true

        let isNewItem: Bool
        @ObservationIgnored
        private let original: OriginalSnapshot
        private let databaseRepository = DatabaseRepository.shared

        init(_ appConfig: DittoConfigForDatabase) {
            _id = appConfig._id
            name = appConfig.name
            databaseId = appConfig.databaseId
            developmentToken = appConfig.developmentToken
            url = appConfig.url
            httpApiUrl = appConfig.httpApiUrl
            httpApiKey = appConfig.httpApiKey
            mode = appConfig.mode
            allowUntrustedCerts = appConfig.allowUntrustedCerts
            secretKey = appConfig.secretKey
            logLevel = appConfig.logLevel
            isStrictModeEnabled = appConfig.isStrictModeEnabled
            isBluetoothLeEnabled = appConfig.isBluetoothLeEnabled
            isLanEnabled = appConfig.isLanEnabled
            isAwdlEnabled = appConfig.isAwdlEnabled
            isCloudSyncEnabled = appConfig.isCloudSyncEnabled

            original = OriginalSnapshot(
                name: appConfig.name,
                databaseId: appConfig.databaseId,
                developmentToken: appConfig.developmentToken,
                url: appConfig.url,
                httpApiUrl: appConfig.httpApiUrl,
                httpApiKey: appConfig.httpApiKey,
                mode: appConfig.mode,
                allowUntrustedCerts: appConfig.allowUntrustedCerts,
                secretKey: appConfig.secretKey,
                logLevel: appConfig.logLevel,
                isStrictModeEnabled: appConfig.isStrictModeEnabled
            )

            if appConfig.databaseId == "" {
                isNewItem = true
            } else {
                isNewItem = false
            }
        }

        /// True when any editable field has diverged from the value the editor
        /// opened with. Drives the discard-changes confirmation dialog and the
        /// host's interactive-dismiss gate. Resets implicitly after a save
        /// because the parent dismisses the sheet.
        var hasUnsavedChanges: Bool {
            name != original.name
                || databaseId != original.databaseId
                || developmentToken != original.developmentToken
                || url != original.url
                || httpApiUrl != original.httpApiUrl
                || httpApiKey != original.httpApiKey
                || mode != original.mode
                || allowUntrustedCerts != original.allowUntrustedCerts
                || secretKey != original.secretKey
                || logLevel != original.logLevel
                || isStrictModeEnabled != original.isStrictModeEnabled
        }

        func save(appState: AppState) async {
            do {
                // Trim whitespace from databaseId
                let trimmedDatabaseId = databaseId.trimmingCharacters(in: .whitespacesAndNewlines)

                let appConfig = DittoConfigForDatabase(
                    _id,
                    name: name,
                    databaseId: trimmedDatabaseId,
                    developmentToken: developmentToken.trimmingCharacters(in: .whitespacesAndNewlines),
                    url: url,
                    httpApiUrl: httpApiUrl,
                    httpApiKey: httpApiKey,
                    mode: mode,
                    allowUntrustedCerts: allowUntrustedCerts,
                    secretKey: secretKey.trimmingCharacters(in: .whitespacesAndNewlines),
                    isBluetoothLeEnabled: isBluetoothLeEnabled,
                    isLanEnabled: isLanEnabled,
                    isAwdlEnabled: isAwdlEnabled,
                    isCloudSyncEnabled: isCloudSyncEnabled,
                    logLevel: logLevel,
                    isStrictModeEnabled: isStrictModeEnabled
                )
                if isNewItem {
                    try await databaseRepository.addDittoAppConfig(appConfig)
                } else {
                    try await databaseRepository.updateDittoAppConfig(appConfig)
                    // The config (incl. logLevel) is already saved above. Applying
                    // the live SDK log level is best-effort and must NOT fail the
                    // save or trigger the error alert + sheet dismissal — it takes
                    // effect on next open if it throws here.
                    do {
                        try await DittoManager.shared.changeDittoLogLevel(logLevel, for: appConfig)
                    } catch {
                        Log.warning("Could not apply log level immediately: \(error.localizedDescription)")
                    }
                }
            } catch {
                appState.setError(error)
            }
        }
    }
}

/// View modifier to handle paste trimming
struct PasteTrimModifier: ViewModifier {
    @Binding var text: String

    func body(content: Content) -> some View {
        #if os(macOS)
        content
            .onPasteCommand(of: [.plainText]) { providers in
                for provider in providers {
                    _ = provider.loadObject(ofClass: NSString.self) { string, _ in
                        if let string = string as? String {
                            Task { @MainActor in
                                text = string.trimmingCharacters(in: .whitespacesAndNewlines)
                            }
                        }
                    }
                }
            }
        #else
        content
        #endif
    }
}

extension View {
    func trimOnPaste(_ text: Binding<String>) -> some View {
        modifier(PasteTrimModifier(text: text))
    }
}
