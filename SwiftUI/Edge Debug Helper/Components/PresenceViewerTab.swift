import SwiftUI
import DittoSwift

struct PresenceViewerTab: View {
    @State private var ditto: Ditto?

    var body: some View {
        Group {
            if let ditto = ditto {
                PresenceViewer(ditto: ditto)
            } else {
                ContentUnavailableView(
                    "No Ditto Connection",
                    systemImage: "network.slash",
                    description: Text("Connect to a Ditto app to view presence information")
                )
            }
        }
        .task {
            ditto = await DittoManager.shared.dittoSelectedApp
        }
    }
}
