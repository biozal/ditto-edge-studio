import SwiftUI

/// Transport Settings action used by the Presence header on macOS and the native
/// detail toolbar on iOS. The iOS `Label` supplies both the vertical-bar symbol
/// and the title used by the system overflow menu on iPhone Duo.
struct TransportSettingsButton: View {
    @State private var showPopover = false
    @State private var selectedDetent: PresentationDetent = .large
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        Button {
            showPopover.toggle()
        } label: {
            #if os(macOS)
            Image(systemName: "gearshape")
            #else
            Label("Transport Settings", systemImage: "gearshape")
            #endif
        }
        .accessibilityLabel("Transport Settings")
        .accessibilityIdentifier("TransportSettingsButton")
        #if os(macOS)
            .foregroundStyle(colorScheme == .dark ? Color.Ditto.trafficWhite : .black)
            .font(.system(size: 18))
            .padding(5)
            .tint(colorScheme == .dark ? Color.Ditto.jetBlack : .white)
            .buttonStyle(.glass)
            .clipShape(Circle())
        #endif
        #if os(iOS)
        .sheet(isPresented: $showPopover) {
            TransportConfigView()
                .presentationDetents([.medium, .large], selection: $selectedDetent)
                .presentationDragIndicator(.visible)
        }
        #else
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
                TransportConfigView()
                    .frame(width: 340)
                    .padding(.vertical, 8)
            }
        #endif
    }
}
