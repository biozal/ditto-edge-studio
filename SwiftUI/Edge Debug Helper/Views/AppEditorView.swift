//
//  AddAppView.swift
//  Edge Studio
//
//  Created by Aaron LaBeau on 5/18/25.
//

import SwiftUI

struct AppEditorView: View {
    @EnvironmentObject private var appState: AppState
    @Binding var isPresented: Bool
    @State private var viewModel: ViewModel
    
    init(isPresented: Binding<Bool>, dittoAppConfig: DittoAppConfig) {
        self._isPresented = isPresented
        self._viewModel = State(initialValue: ViewModel(dittoAppConfig))
    }
    var body: some View {
        NavigationStack {
            Form {
                Picker("Mode", selection: $viewModel.mode) {
                                        Text("Online Playground").tag("online")
                                        Text("Offline").tag("offline")
                                    }
                                    .pickerStyle(.segmented)
                Section("Basic Information") {
                    TextField("Name", text: $viewModel.name)
                        .padding(.bottom, 10)
                }

                Section("Authorization Information") {
                    TextField("AppID", text: $viewModel.appId)
                    TextField("Playground Token", text: $viewModel.authToken)
                        .padding(.bottom, 10)
                }

                if (viewModel.mode == "online") {
                    Section("Ditto Server (BigPeer) Information") {
                        TextField("Auth URL", text: $viewModel.authUrl)
                        TextField("Websocket URL", text: $viewModel.websocketUrl)
                            .padding(.bottom, 10)
                    }
                    Section("Ditto Server - HTTP API - Optional") {
                        VStack(alignment: .leading) {
                            TextEditor(text: $viewModel.httpApiUrl)
                                .frame(minHeight: 40)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.secondary.opacity(0.5))
                                )
                            Text("HTTP API URL")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.bottom, 8)
                            
                            TextEditor(text: $viewModel.httpApiKey)
                                .frame(minHeight: 40)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.secondary.opacity(0.5))
                                )
                            Text("HTTP API Key")
                                .font(.caption)
                                .foregroundColor(.secondary)
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
                            do {
                                try await viewModel.save(appState: appState)
                            } catch {
                                //the view model handles this
                            }
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
        var mode: String
        var allowUntrustedCerts: Bool
        
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
            
            if (appConfig.appId == "") {
                isNewItem = true
            } else {
                isNewItem = false
            }
        }
        
        func save(appState: AppState) async throws {
            do {
                let appConfig = DittoAppConfig(_id,
                                               name: name,
                                               appId: appId,
                                               authToken: authToken,
                                               authUrl: authUrl,
                                               websocketUrl: websocketUrl,
                                               httpApiUrl: httpApiUrl,
                                               httpApiKey: httpApiKey,
                                               mode: mode,
                                               allowUntrustedCerts: allowUntrustedCerts)
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

