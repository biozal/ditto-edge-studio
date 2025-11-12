//
//  ObservableEmptyStateView.swift
//  Edge Studio
//
//  Reusable empty state view for observables
//

import SwiftUI

struct ObservableEmptyStateView: View {
    let title: String
    let systemImage: String
    let description: String

    var body: some View {
        VStack {
            Spacer()
            ContentUnavailableView(
                title,
                systemImage: systemImage,
                description: Text(description)
            )
            Spacer()
        }
    }
}
