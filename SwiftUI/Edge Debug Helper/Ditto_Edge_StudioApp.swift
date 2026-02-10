//
//  Ditto_Edge_StudioApp.swift
//  Ditto Edge Studio
//
//  Created by Aaron LaBeau on 5/18/25.
//

import SwiftUI

// MARK: - Window Controller Helper

class WindowController {
    static func openFontDebugWindow() {
        // Send notification to open window
        NotificationCenter.default.post(name: NSNotification.Name("OpenFontDebugWindow"), object: nil)
    }

    static func openHelpWindow() {
        NotificationCenter.default.post(name: NSNotification.Name("OpenHelpWindow"), object: nil)
    }
}

@main
struct Ditto_Edge_StudioApp: App {
    @StateObject private var appState = AppState()
    @Environment(\.scenePhase) private var scenePhase
    @State private var windowSize: CGSize = CGSize(width: 1200, height: 700) // Default size
    @State private var showFontDebugWindow = false
    @State private var showHelpWindow = false

    init() {
        // Register Font Awesome fonts programmatically
        FontAwesomeRegistration.registerFonts()

        // Set up notification observer for opening Font Debug window
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("OpenFontDebugWindow"),
            object: nil,
            queue: .main
        ) { _ in
            // This will be handled by updating state
        }

        // Set up notification observer for opening Help window
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("OpenHelpWindow"),
            object: nil,
            queue: .main
        ) { _ in
            // This will be handled by updating state
        }
    }

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
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenFontDebugWindow"))) { _ in
                    showFontDebugWindow = true
                }
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenHelpWindow"))) { _ in
                    showHelpWindow = true
                }
                .sheet(isPresented: $showFontDebugWindow) {
                    FontDebugWindow()
                        .frame(width: 600, height: 700)
                }
                .sheet(isPresented: $showHelpWindow) {
                    HelpDocumentationWindow()
                        .frame(width: 800, height: 700)
                }
        }
        .windowResizability(.contentMinSize)
                .handlesExternalEvents(matching: Set(arrayLiteral: "*"))
                .commands {
                    CommandGroup(replacing: .newItem) {
                        // Leave empty to remove New Window command
                    }

                    // MARK: - Help Menu with Font Debug
                    CommandGroup(replacing: .help) {
                        Button("User Guide") {
                            WindowController.openHelpWindow()
                        }
                        .keyboardShortcut("h", modifiers: .command)

                        Divider()

                        Button("Ditto Docs") {
                            // Open help documentation
                            if let url = URL(string: "https://docs.ditto.live") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .keyboardShortcut("?", modifiers: .command)

                        Button("Ditto Portal"){
                            // Open help documentation
                            if let url = URL(string: "https://portal.ditto.live") {
                                NSWorkspace.shared.open(url)
                            }
                        }

                        Divider()
                        
                        Button("Report Issue"){
                            // Open help documentation
                            if let url = URL(string: "https://github.com/biozal/ditto-edge-studio/issues") {
                                NSWorkspace.shared.open(url)
                            }
                        }

                        Divider()

                        Button("Font Debug...") {
                            WindowController.openFontDebugWindow()
                        }
                        .keyboardShortcut("d", modifiers: [.command, .shift])
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
