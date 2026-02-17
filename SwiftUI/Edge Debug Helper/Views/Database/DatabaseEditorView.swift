import SwiftUI

struct DatabaseEditorView: View {
    @EnvironmentObject private var appState: AppState
    @Binding var isPresented: Bool
    @State private var viewModel: ViewModel

    init(isPresented: Binding<Bool>, dittoAppConfig: DittoConfigForDatabase) {
        _isPresented = isPresented
        _viewModel = State(initialValue: ViewModel(dittoAppConfig))
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
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

                    Spacer()
                        .frame(height: 20)

                    Section("Basic Information") {
                        TextField("Name", text: $viewModel.name)
                            .lineLimit(1)
                            .padding(.bottom, 10)
                            .accessibilityIdentifier("NameTextField")
                    }

                    Section("Authorization Information") {
                        TextField("Database ID", text: $viewModel.databaseId)
                            .textFieldStyle(.roundedBorder)
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
                                .foregroundColor(.blue)
                                .font(.system(size: 16))

                            Text(
                                "This information comes from the [Ditto Portal](https://portal.ditto.live) and is required in order to register a Ditto Database."
                            )
                            .font(.callout)
                            .foregroundColor(.primary)
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
            .padding()
            #endif
            .navigationTitle(viewModel.databaseId == "" ? "Register Database" : "Edit Database")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            isPresented = false
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
                            viewModel.token.isEmpty)
                        .accessibilityIdentifier("SaveButton")
                    }
                }
        }
    }

    // MARK: - View Builders

    @ViewBuilder
    private func authTokenField(for mode: AuthMode) -> some View {
        switch mode {
        case .server:
            TextField("Token", text: $viewModel.token)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1)
                .trimOnPaste($viewModel.token)
                .padding(.bottom, 10)
                .accessibilityIdentifier("TokenTextField")
        case .smallPeersOnly:
            TextField("Offline Token", text: $viewModel.token)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1)
                .trimOnPaste($viewModel.token)
                .padding(.bottom, 5)
                .accessibilityIdentifier("TokenTextField")

            Text("Required for sync activation in Small Peers Only mode.\nObtain from https://portal.ditto.live")
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.bottom, 10)
        }
    }

    @ViewBuilder
    private func modeSpecificSections(for mode: AuthMode) -> some View {
        switch mode {
        case .smallPeersOnly:
            secretKeySection()
        case .server:
            serverInformationSection()
            httpApiSection()
        }
    }

    private func secretKeySection() -> some View {
        Section("Optional Secret Key") {
            TextField("Shared Key", text: $viewModel.secretKey)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1)
                .padding(.bottom, 5)
                .accessibilityIdentifier("SecretKeyTextField")

            Text("Optional secret key for shared key identity encryption. Leave empty if not using Shared Key.")
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.bottom, 10)
        }
    }

    private func serverInformationSection() -> some View {
        Section("Ditto Server (BigPeer) Information") {
            TextField("Auth URL", text: $viewModel.authUrl)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1)
                .accessibilityIdentifier("AuthUrlTextField")

            TextField("Websocket URL", text: $viewModel.websocketUrl)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1)
                .padding(.bottom, 10)
                .accessibilityIdentifier("WebsocketUrlTextField")
        }
    }

    private func httpApiSection() -> some View {
        Section("Ditto Server - HTTP API - Optional") {
            VStack(alignment: .leading) {
                TextField("HTTP API URL", text: $viewModel.httpApiUrl)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1)
                    .padding(.bottom, 8)
                    .accessibilityIdentifier("HttpApiUrlTextField")

                TextField("HTTP API Key", text: $viewModel.httpApiKey)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1)
                    .padding(.bottom, 10)
                    .accessibilityIdentifier("HttpApiKeyTextField")

                Toggle("Allow untrusted certificates", isOn: $viewModel.allowUntrustedCerts)
                    .padding(.bottom, 5)
                    .accessibilityIdentifier("AllowUntrustedCertsToggle")

                Text(
                    "By allowing untrusted certificates, you are bypassing SSL certificate validation entirely, which poses significant security risks. This setting should only be used in development environments and never in production."
                )
                .font(.caption2)
                .foregroundColor(.secondary)
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
    @Observable
    class ViewModel {
        let _id: String
        var name: String
        var databaseId: String
        var token: String
        var authUrl: String
        var websocketUrl: String
        var httpApiUrl: String
        var httpApiKey: String
        var mode: AuthMode
        var allowUntrustedCerts: Bool
        var secretKey: String

        let isNewItem: Bool
        private let databaseRepository = DatabaseRepository.shared

        init(_ appConfig: DittoConfigForDatabase) {
            _id = appConfig._id
            name = appConfig.name
            databaseId = appConfig.databaseId
            token = appConfig.token
            authUrl = appConfig.authUrl
            websocketUrl = appConfig.websocketUrl
            httpApiUrl = appConfig.httpApiUrl
            httpApiKey = appConfig.httpApiKey
            mode = appConfig.mode
            allowUntrustedCerts = appConfig.allowUntrustedCerts
            secretKey = appConfig.secretKey

            if appConfig.databaseId == "" {
                isNewItem = true
            } else {
                isNewItem = false
            }
        }

        func save(appState: AppState) async {
            do {
                // Trim whitespace from databaseId
                let trimmedDatabaseId = databaseId.trimmingCharacters(in: .whitespacesAndNewlines)

                let appConfig = DittoConfigForDatabase(
                    _id,
                    name: name,
                    databaseId: trimmedDatabaseId,
                    token: token.trimmingCharacters(in: .whitespacesAndNewlines),
                    authUrl: authUrl,
                    websocketUrl: websocketUrl,
                    httpApiUrl: httpApiUrl,
                    httpApiKey: httpApiKey,
                    mode: mode,
                    allowUntrustedCerts: allowUntrustedCerts,
                    secretKey: secretKey.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                if isNewItem {
                    try await databaseRepository.addDittoAppConfig(appConfig)
                } else {
                    try await databaseRepository.updateDittoAppConfig(appConfig)
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
        content
            .onPasteCommand(of: [.plainText]) { providers in
                for provider in providers {
                    _ = provider.loadObject(ofClass: NSString.self) { string, _ in
                        if let string = string as? String {
                            DispatchQueue.main.async {
                                text = string.trimmingCharacters(in: .whitespacesAndNewlines)
                            }
                        }
                    }
                }
            }
    }
}

extension View {
    func trimOnPaste(_ text: Binding<String>) -> some View {
        modifier(PasteTrimModifier(text: text))
    }
}
