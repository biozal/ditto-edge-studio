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
// swiftlint:disable:next type_name
struct Ditto_Edge_StudioApp: App {
    @StateObject private var appState = AppState()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openWindow) private var openWindow

    init() {
        // Register Font Awesome fonts programmatically
        FontAwesomeRegistration.registerFonts()
    }

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
                    if let appError = appState.error as? AppError {
                        switch appError {
                        case let .error(message):
                            Text(message)
                        }
                    } else {
                        Text(appState.error?.localizedDescription ?? "Unknown Error")
                    }
                }
                .environmentObject(appState)
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenFontDebugWindow"))) { _ in
                    openWindow(id: "font-debug-window")
                }
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenHelpWindow"))) { _ in
                    openWindow(id: "help-window")
                }
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 800, height: 540)
        .handlesExternalEvents(matching: ["*"])

        // MARK: - Utility Windows

        // Help Documentation Window
        WindowGroup(id: "help-window") {
            HelpDocumentationWindow()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 800, height: 700)

        // Font Debug Window
        WindowGroup(id: "font-debug-window") {
            FontDebugWindow()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 600, height: 700)
        .commands {
            CommandGroup(replacing: .newItem) {
                // Leave empty to remove New Window command
            }

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

                Button("Ditto Portal") {
                    // Open help documentation
                    if let url = URL(string: "https://portal.ditto.live") {
                        NSWorkspace.shared.open(url)
                    }
                }

                Divider()

                Button("Report Issue") {
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
        .onChange(of: scenePhase) { newPhase, _ in
            switch newPhase {
            case .background, .inactive:
                Task {}
            case .active:
                break
            @unknown default:
                break
            }
        }
    }
}
