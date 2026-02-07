import SwiftUI

struct SubscriptionCard: View {
    let subscription: DittoSubscription
    
    var body: some View {
        HStack(alignment: .top, spacing: 32) {
            // Left VStack: Icon and Name
            VStack(alignment: .leading, spacing: 12) {
                Text(subscription.name)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subscription.query)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                if let args = subscription.args, !args.isEmpty {
                    Text(args)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(20)
#if os(iOS)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(20)
#else
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)
                )
        )
        .cornerRadius(20)
        .elevatedShadow()
#endif
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
    )
}
