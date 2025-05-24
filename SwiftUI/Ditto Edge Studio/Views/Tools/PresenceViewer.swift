//
//  PresenceViewer.swift
//  Ditto Edge Studio
//
//  Created by Aaron LaBeau on 5/23/25.
//

import DittoPresenceViewer
import DittoSwift
import SwiftUI

struct PresenceViewer: View{
    let ditto: Ditto

    var body: some View {
        PresenceView(ditto: ditto)
    }
}
