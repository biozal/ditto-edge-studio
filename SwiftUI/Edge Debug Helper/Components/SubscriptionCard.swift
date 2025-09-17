//
//  DittoSubscriptionCard.swift
//  Edge Studio
//
//  Created by Aaron LaBeau on 6/11/25.
//

import SwiftUI

struct SubscriptionCard: View {
    let subscription: DittoSubscription
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            // Subscription icon - indented to align slightly left of header text
            Image(systemName: "arrow.trianglehead.2.clockwise")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 14)
                .padding(.leading, 14)

            // Content
            VStack(alignment: .leading, spacing: 2) {
                Text(subscription.name.isEmpty ? "Unnamed Subscription" : subscription.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .foregroundColor(.primary)

                if !subscription.query.isEmpty {
                    Text(subscription.query)
                        .font(.system(size: 11, design: .monospaced))
                        .lineLimit(1)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Args indicator
            if let args = subscription.args, !args.isEmpty {
                Circle()
                    .fill(.secondary)
                    .frame(width: 4, height: 4)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        .cornerRadius(4)
        .contentShape(Rectangle())
    }
}

#Preview {
    SubscriptionCard(
        subscription: DittoSubscription(
            ["_id": "1",
            "name": "Example Subscription",
            "query": "SELECT * FROM example",
             "args": "{\"arg1\": \"value1\", \"arg2\": \"value2\"}"
            ]),
        isSelected: false
    )
}
