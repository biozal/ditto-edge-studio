import SwiftUI

/// True when running under XCUITest.
///
/// Detected via the `UI_TESTING` launch *environment variable* (NOT a launch
/// argument). On macOS, launching a SwiftUI app with any command-line argument is
/// treated as a non-default launch and the `WindowGroup` does not auto-open its
/// window — which makes the app window-less under XCUITest. An environment
/// variable avoids that, so the window opens normally. The legacy `UI-TESTING`
/// argument is still honored for back-compat.
func isRunningUITests() -> Bool {
    ProcessInfo.processInfo.environment["UI_TESTING"] == "1"
        || ProcessInfo.processInfo.arguments.contains("UI-TESTING")
}

// MARK: - Window Controller Helper

class WindowController {
    static func openFontDebugWindow() {
        // Send notification to open window
        NotificationCenter.default.post(name: NSNotification.Name("OpenFontDebugWindow"), object: nil)
    }

    static func openHelpWindow() {
        NotificationCenter.default.post(name: NSNotification.Name("OpenHelpWindow"), object: nil)
    }

    static func openWelcomeWindow() {
        NotificationCenter.default.post(name: NSNotification.Name("OpenWelcomeWindow"), object: nil)
    }

    static func openQuickstartBrowserWindow() {
        NotificationCenter.default.post(name: NSNotification.Name("OpenQuickstartBrowserWindow"), object: nil)
    }

    /// Posts a notification to show the quickstart browser with data in userInfo.
    static func showQuickstartBrowser(projects: [QuickstartProject], isConfigured: Bool, directory: URL) {
        NotificationCenter.default.post(
            name: NSNotification.Name("ShowQuickstartBrowser"),
            object: nil,
            userInfo: [
                "projects": projects,
                "isConfigured": isConfigured,
                "directory": directory
            ]
        )
    }
}

#if os(macOS)
/// App delegate used ONLY to make UI testing work on macOS.
///
/// The window-opening fix is the `UI_TESTING` launch *environment variable*
/// (see `isRunningUITests()`): launching with an env var rather than a
/// command-line argument keeps it a default launch, so the `WindowGroup` opens
/// its window normally. This delegate is the belt-and-suspenders for that —
/// `applicationShouldHandleReopen` returning `true` lets AppKit (re)open a
/// window if the app is activated without one. A no-op in production.
@MainActor
final class UITestSupportAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        true
    }
}
#endif

@main
// swiftlint:disable:next type_name
struct Ditto_Edge_StudioApp: App {
    @State private var appState = AppState()
    @Environment(\.openWindow) private var openWindow

    #if os(macOS)
    /// Foregrounds the app + forces its window on-screen when launched under
    /// UI tests (no effect otherwise). See `UITestSupportAppDelegate`.
    @NSApplicationDelegateAdaptor(UITestSupportAppDelegate.self) private var uiTestAppDelegate
    #endif

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

    #if os(macOS)
    @State private var quickstartBrowserProjects: [QuickstartProject] = []
    @State private var quickstartBrowserIsConfigured = false
    @State private var quickstartBrowserDir: URL?
    #endif

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
                .environment(appState)
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenFontDebugWindow"))) { _ in
                    openWindow(id: "font-debug-window")
                }
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenHelpWindow"))) { _ in
                    openWindow(id: "help-window")
                }
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenWelcomeWindow"))) { _ in
                    openWindow(id: "welcome-window")
                }
            #if os(macOS)
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowQuickstartBrowser"))) { notification in
                    if let userInfo = notification.userInfo,
                       let projects = userInfo["projects"] as? [QuickstartProject],
                       let isConfigured = userInfo["isConfigured"] as? Bool,
                       let directory = userInfo["directory"] as? URL
                    {
                        quickstartBrowserProjects = projects
                        quickstartBrowserIsConfigured = isConfigured
                        quickstartBrowserDir = directory
                        openWindow(id: "quickstart-browser-window")
                    }
                }
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
        // .contentSize lets the window snap to whatever frame the
        // current view declares. ContentView's picker uses a *fixed*
        // frame (Xcode-launch-style — non-resizable, all buttons always
        // visible); MainStudioView uses a min frame so once a database
        // is open the window can be grown freely. .contentMinSize used
        // to be the default but it always made the picker resizable
        // and let users drag it below the height needed to fit all 3
        // CTA buttons.
        .windowResizability(.contentSize)
        .defaultSize(width: 900, height: 640)

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

        // Welcome Window — first-run onboarding for fresh databases.
        // Opens automatically from MainStudioViewModel when a database
        // is selected with no subscriptions and no query history (gated
        // on @AppStorage("showWelcomeOnNewDatabase") = true), or on
        // demand from the Help menu.
        WindowGroup(id: "welcome-window") {
            WelcomeWindow()
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 880, height: 720)

        // Font Debug Window
        WindowGroup(id: "font-debug-window") {
            FontDebugWindow()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 600, height: 700)

        // Quickstart Browser Window
        WindowGroup(id: "quickstart-browser-window") {
            if let dir = quickstartBrowserDir {
                QuickstartBrowserWindow(
                    projects: quickstartBrowserProjects,
                    isConfigured: quickstartBrowserIsConfigured,
                    quickstartDir: dir
                )
            } else {
                Text("No quickstart data available.")
                    .frame(width: 600, height: 400)
            }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 700, height: 500)
        .commands {
            CommandGroup(replacing: .newItem) {
                // Leave empty to remove New Window command
            }

            CommandGroup(replacing: .help) {
                Button("Welcome") {
                    WindowController.openWelcomeWindow()
                }

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

                Button("Download Quickstarts...") {
                    WindowController.openQuickstartBrowserWindow()
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
