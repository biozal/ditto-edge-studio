//
//  DiskUsageViewer.swift
//  Ditto Edge Studio
//
//  Created by Aaron LaBeau on 5/23/25.
//

import SwiftUI
import DittoSwift
import DittoDiskUsage

struct DiskUsageViewer: View {
    let ditto: Ditto
    var body: some View {
        DittoDiskUsageView(ditto: ditto)
    }
}
