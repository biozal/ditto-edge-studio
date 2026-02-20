import SwiftUI

/// A borderless gear button that presents TransportConfigView in a popover.
/// Styled to match native macOS toolbar icon buttons (sidebar/inspector toggles).
/// Used in ConnectedPeersView and PresenceViewerSK.
struct TransportSettingsButton: View {
    @State private var showPopover = false
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        Button {
            showPopover.toggle()
        } label: {
            Image(systemName: "gearshape")
                .foregroundStyle(colorScheme == .dark ? Color.Ditto.trafficWhite : .black)
                .font(.system(size: 18))
                .padding(5)
        }
        .tint(colorScheme == .dark ? Color.Ditto.jetBlack : .white)
        .buttonStyle(.glass)
        .clipShape(Circle())
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            TransportConfigView()
                .frame(width: 340)
                .padding(.vertical, 8)
        }
    }
}
