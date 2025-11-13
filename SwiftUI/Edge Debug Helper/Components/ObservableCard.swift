//
//  ObservableCard.swift
//  Edge Studio
//
//  Card component for displaying an individual observable
//

import SwiftUI

struct ObservableCard: View {
    let observer: DittoObservable

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill((observer.storeObserver == nil ? Color.gray.opacity(0.15) : Color.green.opacity(0.15)))
                .shadow(radius: 1)
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(observer.name)
                        .font(.headline)
                        .bold()

                    Text(observer.query)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                Spacer()
            }
            .padding(12)
        }
        .frame(height: 80)
    }
}
