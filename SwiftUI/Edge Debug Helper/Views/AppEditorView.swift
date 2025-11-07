//
//  AddAppView.swift
//  Edge Studio
//
//  Created by Aaron LaBeau on 5/18/25.
//

import SwiftUI

// View modifier to handle paste trimming
struct PasteTrimModifier: ViewModifier {
    @Binding var text: String

    func body(content: Content) -> some View {
        content
            .onPasteCommand(of: [.plainText]) { providers in
                for provider in providers {
                    _ = provider.loadObject(ofClass: NSString.self) { string, error in
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

struct AppEditorView: View {
    @EnvironmentObject private var appState: AppState
    @Binding var isPresented: Bool
    @State private var viewModel: ViewModel
    @State private var showWipeConfirmation = false
    @State private var wipeStatus: String?
    @State private var showWipeStatus = false

    init(isPresented: Binding<Bool>, dittoAppConfig: DittoAppConfig) {
        self._isPresented = isPresented
        self._viewModel = State(initialValue: ViewModel(dittoAppConfig))
    }
    var body: some View {
        NavigationStack {
            Form {
                Picker("Mode", selection: $viewModel.mode) {
                                        ForEach(AuthMode.allCases, id: \.self) { mode in
                                            Text(mode.displayName).tag(mode)
                                        }
                                    }
                                    .pickerStyle(.segmented)
                Section("Basic Information") {
                    TextField("Name", text: $viewModel.name)
                        .lineLimit(1)
                        .padding(.bottom, 10)
                }

                Section("Authorization Information") {
                    TextField("App ID", text: $viewModel.appId)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(1)
                        .trimOnPaste($viewModel.appId)
                        .padding(.bottom, 5)

                    authTokenField(for: viewModel.mode)
                }

                modeSpecificSections(for: viewModel.mode)
            }
#if os(macOS)
            .padding()
#endif
            .navigationTitle(viewModel.appId == "" ? "Add Ditto App Config" : "Edit Ditto App Config")
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
                }
                ToolbarItem(placement: .confirmationAction){
                    Button ("Save"){
                        Task {
                            await viewModel.save(appState: appState)
                            isPresented = false
                        }
                    }
                    .disabled(
                        viewModel.appId.isEmpty ||
                        viewModel.name.isEmpty ||
                        viewModel.authToken.isEmpty
                    )
                }
            }
            .alert("Wipe Database", isPresented: $showWipeConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Wipe Database", role: .destructive) {
                    Task {
                        await wipeDatabase()
                    }
                }
            } message: {
                Text("Are you sure you want to wipe the database for '\(viewModel.name)'? This will delete all local data and cannot be undone. Data will be resynced from other peers if available.")
            }
            .alert("Database Wipe Status", isPresented: $showWipeStatus) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(wipeStatus ?? "")
            }
        }
    }

    private func wipeDatabase() async {
        do {
            let appConfig = viewModel.toDittoAppConfig()
            try await DittoManager.shared.wipeDatabaseForApp(appConfig)
            wipeStatus = "Database wiped successfully for '\(viewModel.name)'"
            showWipeStatus = true
        } catch {
            wipeStatus = "Failed to wipe database: \(error.localizedDescription)"
            showWipeStatus = true
        }
    }

    // MARK: - View Builders

    @ViewBuilder
    private func authTokenField(for mode: AuthMode) -> some View {
        switch mode {
        case .onlinePlayground, .offlinePlayground:
            TextField("Playground Token", text: $viewModel.authToken)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1)
                .trimOnPaste($viewModel.authToken)
                .padding(.bottom, 10)
        case .sharedKey:
            TextField("Offline License Token", text: $viewModel.authToken)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1)
                .trimOnPaste($viewModel.authToken)
                .padding(.bottom, 5)

            Text("Required for sync activation in shared key mode. Obtain from https://portal.ditto.live")
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.bottom, 10)
        }
    }

    @ViewBuilder
    private func modeSpecificSections(for mode: AuthMode) -> some View {
        switch mode {
        case .sharedKey:
            secretKeySection()
        case .onlinePlayground:
            serverInformationSection()
            httpApiSection()
        case .offlinePlayground:
            EmptyView()
        }
    }

    @ViewBuilder
    private func secretKeySection() -> some View {
        Section("Optional Secret Key") {
            TextField("Secret Key (Optional)", text: $viewModel.secretKey)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1)
                .padding(.bottom, 5)

            Text("Optional secret key for shared key identity encryption. Leave empty if not required.")
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.bottom, 10)
        }
    }

    @ViewBuilder
    private func serverInformationSection() -> some View {
        Section("Ditto Server (BigPeer) Information") {
            TextField("Auth URL", text: $viewModel.authUrl)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1)

            TextField("Websocket URL", text: $viewModel.websocketUrl)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1)
                .padding(.bottom, 10)
        }
    }

    @ViewBuilder
    private func httpApiSection() -> some View {
        Section("Ditto Server - HTTP API - Optional") {
            VStack(alignment: .leading) {
                TextField("HTTP API URL", text: $viewModel.httpApiUrl)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1)
                    .padding(.bottom, 8)

                TextField("HTTP API Key", text: $viewModel.httpApiKey)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1)
                    .padding(.bottom, 10)

                Toggle("Allow untrusted certificates", isOn: $viewModel.allowUntrustedCerts)
                    .padding(.bottom, 5)

                Text("By allowing untrusted certificates, you are bypassing SSL certificate validation entirely, which poses significant security risks. This setting should only be used in development environments and never in production.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 10)
            }
        }
    }

    // MARK: - View Builders

    @ViewBuilder
    private func authTokenField(for mode: AuthMode) -> some View {
        switch mode {
        case .onlinePlayground, .offlinePlayground:
            TextField("Playground Token", text: $viewModel.authToken)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1)
                .trimOnPaste($viewModel.authToken)
                .padding(.bottom, 10)
        case .sharedKey:
            TextField("Offline License Token", text: $viewModel.authToken)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1)
                .trimOnPaste($viewModel.authToken)
                .padding(.bottom, 5)

            Text("Required for sync activation in shared key mode. Obtain from https://portal.ditto.live")
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.bottom, 10)
        }
    }

    @ViewBuilder
    private func modeSpecificSections(for mode: AuthMode) -> some View {
        switch mode {
        case .sharedKey:
            secretKeySection()
        case .onlinePlayground:
            serverInformationSection()
            httpApiSection()
        case .offlinePlayground:
            EmptyView()
        }
    }

    @ViewBuilder
    private func secretKeySection() -> some View {
        Section("Optional Secret Key") {
            TextField("Secret Key (Optional)", text: $viewModel.secretKey)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1)
                .padding(.bottom, 5)

            Text("Optional secret key for shared key identity encryption. Leave empty if not required.")
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.bottom, 10)
        }
    }

    @ViewBuilder
    private func serverInformationSection() -> some View {
        Section("Ditto Server (BigPeer) Information") {
            TextField("Auth URL", text: $viewModel.authUrl)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1)

            TextField("Websocket URL", text: $viewModel.websocketUrl)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1)
                .padding(.bottom, 10)
        }
    }

    @ViewBuilder
    private func httpApiSection() -> some View {
        Section("Ditto Server - HTTP API - Optional") {
            VStack(alignment: .leading) {
                TextField("HTTP API URL", text: $viewModel.httpApiUrl)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1)
                    .padding(.bottom, 8)

                TextField("HTTP API Key", text: $viewModel.httpApiKey)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1)
                    .padding(.bottom, 10)

                Toggle("Allow untrusted certificates", isOn: $viewModel.allowUntrustedCerts)
                    .padding(.bottom, 5)

                Text("By allowing untrusted certificates, you are bypassing SSL certificate validation entirely, which poses significant security risks. This setting should only be used in development environments and never in production.")
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
    AppEditorView(isPresented: .constant(true), dittoAppConfig: DittoAppConfig.new())
}

extension AppEditorView {
    @Observable
    class ViewModel {
        let _id: String
        var name: String
        var appId: String
        var authToken: String
        var authUrl: String
        var websocketUrl: String
        var httpApiUrl: String
        var httpApiKey: String
        var mode: AuthMode
        var allowUntrustedCerts: Bool
        var secretKey: String
        
        let isNewItem: Bool
        private let databaseRepository = DatabaseRepository.shared
        
        init(_ appConfig: DittoAppConfig) {
            _id =  appConfig._id
            name = appConfig.name
            appId = appConfig.appId
            authToken = appConfig.authToken
            authUrl = appConfig.authUrl
            websocketUrl = appConfig.websocketUrl
            httpApiUrl = appConfig.httpApiUrl
            httpApiKey = appConfig.httpApiKey
            mode = appConfig.mode
            allowUntrustedCerts = appConfig.allowUntrustedCerts
            secretKey = appConfig.secretKey
            
            if (appConfig.appId == "") {
                isNewItem = true
            } else {
                isNewItem = false
            }
        }
        
        func save(appState: AppState) async {
            do {
                // Trim whitespace from appId
                let trimmedAppId = appId.trimmingCharacters(in: .whitespacesAndNewlines)

                let appConfig = DittoAppConfig(_id,
                                               name: name,
                                               appId: trimmedAppId,
                                               authToken: authToken.trimmingCharacters(in: .whitespacesAndNewlines),
                                               authUrl: authUrl,
                                               websocketUrl: websocketUrl,
                                               httpApiUrl: httpApiUrl,
                                               httpApiKey: httpApiKey,
                                               mode: mode,
                                               allowUntrustedCerts: allowUntrustedCerts,
                                               secretKey: secretKey.trimmingCharacters(in: .whitespacesAndNewlines))
                if isNewItem {
                    try await databaseRepository.addDittoAppConfig(appConfig)
                } else {
                    try await databaseRepository.updateDittoAppConfig(appConfig)
                }
            } catch {
                appState.setError(error)
            }
        }

        func toDittoAppConfig() -> DittoAppConfig {
            let trimmedAppId = appId.trimmingCharacters(in: .whitespacesAndNewlines)
            return DittoAppConfig(_id,
                                  name: name,
                                  appId: trimmedAppId,
                                  authToken: authToken.trimmingCharacters(in: .whitespacesAndNewlines),
                                  authUrl: authUrl,
                                  websocketUrl: websocketUrl,
                                  httpApiUrl: httpApiUrl,
                                  httpApiKey: httpApiKey,
                                  mode: mode,
                                  allowUntrustedCerts: allowUntrustedCerts,
                                  secretKey: secretKey.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}

