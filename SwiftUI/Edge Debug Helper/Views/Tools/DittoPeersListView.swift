import SwiftUI
import DittoSwift
import DittoPeersList

struct DittoPeersListView: View {
    let ditto: Ditto
    
    var body: some View {
        PeersListView(ditto: ditto)
    }
}

