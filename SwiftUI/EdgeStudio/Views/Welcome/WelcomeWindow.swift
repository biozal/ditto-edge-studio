import SwiftUI

/// macOS window wrapper for `WelcomeView`. Hosts the SwiftUI window
/// scene declared in `Ditto_Edge_StudioApp.swift`'s
/// `WindowGroup(id: "welcome-window")`.
///
/// On iPadOS the welcome screen is presented as a `.sheet` instead,
/// so this wrapper is macOS-only — multi-window on iPadOS would force
/// the user into split-screen to see both welcome and studio.
struct WelcomeWindow: View {
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        WelcomeView {
            dismissWindow(id: "welcome-window")
        }
        .frame(minWidth: 720, idealWidth: 880, minHeight: 600, idealHeight: 720)
    }
}
