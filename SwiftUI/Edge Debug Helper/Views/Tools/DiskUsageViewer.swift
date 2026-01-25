import SwiftUI
import DittoSwift
import DittoDiskUsage

struct DiskUsageViewer: View {
    let ditto: Ditto
    var body: some View {
        DittoDiskUsageView(ditto: ditto)
    }
}
