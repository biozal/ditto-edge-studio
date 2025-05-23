//
//  AddAppView.swift
//  Ditto Edge Studio
//
//  Created by Aaron LaBeau on 5/18/25.
//

import SwiftUI

struct AppEditorView: View {
    @EnvironmentObject private var appState: DittoApp
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
                }

                Section("Authorization Information") {
                    TextField("AppID", text: $viewModel.appId)
                    TextField("Playground Token", text: $viewModel.authToken)
                }

                if (viewModel.mode == "online") {
                    Section("BigPeer Information") {
                        TextField("Auth URL", text: $viewModel.authUrl)
                        TextField("Websocket URL", text: $viewModel.websocketUrl)
                    }
                    Section("Connect via HTTP API") {
                        TextField("HTTP API URL", text: $viewModel.httpApiUrl)
                        TextField("HTTP API Key", text: $viewModel.httpApiKey)
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
        
        let isNewItem: Bool
        
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
            
            if (appConfig.appId == "") {
                isNewItem = true
            } else {
                isNewItem = false
            }
        }
        
        func save(appState: DittoApp) async throws {
            do {
                let appConfig = DittoAppConfig(_id,
                                               name: name,
                                               appId: appId,
                                               authToken: authToken,
                                               authUrl: authUrl,
                                               websocketUrl: websocketUrl,
                                               httpApiUrl: httpApiUrl,
                                               httpApiKey: httpApiKey,
                                               mode: mode)
                if isNewItem {
                    try await DittoManager.shared.addDittoAppConfig(appConfig)
                } else {
                    try await DittoManager.shared.updateDittoAppConfig(appConfig)
                }
            } catch {
                appState.setError(error)
            }
        }
    }
}
