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
    @Environment(\.scenePhase) private var scenePhase
    @State private var windowSize: CGSize = CGSize(width: 1200, height: 700) // Default size

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: windowSize.width, minHeight: windowSize.height)
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
                    if let appError = appState.error as? AppError {
                        switch appError {
                        case .error(let message):
                            Text(message)
                        }
                    } else {
                        Text( appState.error?.localizedDescription ?? "Unknown Error")
                    }
                }
                .environmentObject(appState)
        }
        .windowResizability(.contentSize)
                .handlesExternalEvents(matching: Set(arrayLiteral: "*"))
                .commands {
                    CommandGroup(replacing: .newItem) {
                        // Leave empty to remove New Window command
                    }
                }
        .onChange(of: scenePhase) { newPhase, oldPhase in
            switch newPhase {
            case .background, .inactive:
                Task {
                }
            case .active:
                break
            @unknown default:
                break
            }
        }
    }
}
