//
//  DittoPeersListView.swift
//  Edge Studio
//
//  Created by Aaron LaBeau on 6/10/25.
//

import SwiftUI
import DittoSwift
import DittoPeersList

struct DittoPeersListView: View {
    let ditto: Ditto
    
    var body: some View {
        PeersListView(ditto: ditto)
    }
}

