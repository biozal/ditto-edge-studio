import DittoPresenceViewer
import DittoSwift
import SwiftUI

struct PresenceViewer: View{
    let ditto: Ditto

    var body: some View {
        PresenceView(ditto: ditto)
    }
}
