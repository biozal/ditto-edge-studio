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
        // Register UserDefaults defaults so preference values are correct before the user
        // has ever opened the macOS Settings window or the iOS Settings app.
        // Without this, UserDefaults.bool(forKey:) returns false (not true) for absent keys.
        UserDefaults.standard.register(defaults: [
            "metricsEnabled": true,
            "mcpServerEnabled": false,
            "mcpServerPort": 65269
        ])

        #if os(macOS)
        // On macOS, programmatic registration ensures fonts are available before first render.
        // On iOS, UIAppFonts in Info.plist handles registration — manual call causes duplicates.
        FontAwesomeRegistration.registerFonts()
        #endif
    }

    @AppStorage("mcpServerEnabled") private var mcpServerEnabled = false

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
            #if os(macOS)
                .onAppear {
                    if mcpServerEnabled {
                        Task { await MCPServerService.shared.start() }
                    }
                }
                .onChange(of: mcpServerEnabled) { _, enabled in
                    Task {
                        if enabled {
                            await MCPServerService.shared.start()
                        } else {
                            await MCPServerService.shared.stop()
                        }
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    Task { await MCPServerService.shared.stop() }
                }
            #endif
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 800, height: 540)
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

        #if os(macOS)

        // MARK: - Native Settings Window (macOS only)

        // Automatically adds "Settings…" (⌘,) to the app menu.

        Settings {
            AppPreferencesView()
        }

        // MARK: - Utility Windows (macOS only)

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
                    if let url = URL(string: "https://docs.ditto.live") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .keyboardShortcut("?", modifiers: .command)

                Button("Ditto Portal") {
                    if let url = URL(string: "https://portal.ditto.live") {
                        NSWorkspace.shared.open(url)
                    }
                }

                Divider()

                Button("Report Issue") {
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
        #endif
    }
}
