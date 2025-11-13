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
        VStack(alignment: .center, spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            VStack(alignment: .center, spacing: 8) {
                Text(title)
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(24)
    }
}
