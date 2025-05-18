//
//  Ditto_Edge_StudioApp.swift
//  Ditto Edge Studio
//
//  Created by Aaron LaBeau on 5/18/25.
//

import SwiftUI

@main
struct Ditto_Edge_StudioApp: App {
    @StateObject private var appState = DittoApp()
    var body: some Scene {
        WindowGroup {
            ContentView()
                .alert(
                    "Error",
                    isPresented: Binding(
                        get: { appState.error != nil },
                        set: { if !$0 { appState.error = nil } }
                    )
                ) {
                    Button("OK", role: .cancel) {
                        appState.error = nil
                    }
                } message: {
                    Text(
                        appState.error?.localizedDescription ?? "Unknown Error"
                    )
                }
                .environmentObject(appState)
        }
    }
}
