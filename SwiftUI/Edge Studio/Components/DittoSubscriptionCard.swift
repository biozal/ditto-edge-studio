//
//  DittoSubscriptionCard.swift
//  Edge Studio
//
//  Created by Aaron LaBeau on 6/11/25.
//

import SwiftUI

struct DittoSubscriptionCard: View {
    let subscription: DittoSubscription
    
    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            // Left VStack: Icon and Name
            VStack(alignment: .leading, spacing: 12) {
                Text(subscription.name)
                    .font(.title)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subscription.query)
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                if let args = subscription.args, !args.isEmpty {
                    Text(args)
                        .font(.title3)
                        .multilineTextAlignment(.center)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
#if os(iOS)
        .background(Color(.secondarySystemBackground))
#else
        .background(
            RoundedRectangle(cornerRadius: 16).fill(
                Color(NSColor.windowBackgroundColor)
            ).shadow(radius: 4)
        )
#endif
        .cornerRadius(16)
    }
}

#Preview {
    DittoSubscriptionCard(
        subscription: DittoSubscription(
            ["_id": "1",
            "name": "Example Subscription",
            "query": "SELECT * FROM example",
             "args": "{\"arg1\": \"value1\", \"arg2\": \"value2\"}"
            ]),
    )
}
