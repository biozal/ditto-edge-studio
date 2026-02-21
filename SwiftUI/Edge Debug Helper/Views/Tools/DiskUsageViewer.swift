import DittoDiskUsage
import DittoSwift
import SwiftUI

struct DiskUsageViewer: View {
    let ditto: Ditto
    var body: some View {
        DittoDiskUsageView(ditto: ditto)
    }
}
