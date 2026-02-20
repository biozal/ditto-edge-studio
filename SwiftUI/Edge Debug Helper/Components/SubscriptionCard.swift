import SwiftUI

struct SubscriptionCard: View {
    let subscription: DittoSubscription
    @Environment(\.colorScheme) var colorScheme

    private var gradientColors: [Color] {
        colorScheme == .dark
            ? [Color.Ditto.trafficBlack, Color.Ditto.jetBlack]
            : [Color.Ditto.trafficWhite, Color.Ditto.papyrusWhite]
    }

    private var shadowOpacity: Double {
        colorScheme == .dark ? 0.40 : 0.15
    }

    var body: some View {
        HStack(alignment: .top, spacing: 32) {
            // Left VStack: Icon and Name
            VStack(alignment: .leading, spacing: 12) {
                Text(subscription.name)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subscription.query)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                if let args = subscription.args, !args.isEmpty {
                    Text(args)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(LinearGradient(
                    colors: gradientColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .shadow(color: Color.black.opacity(shadowOpacity), radius: 6, x: 0, y: 3)
        )
    }
}

#Preview {
    SubscriptionCard(subscription: DittoSubscription([
        "_id": "1",
        "name": "Example Subscription",
        "query": "SELECT * FROM example",
        "args": "{\"arg1\": \"value1\", \"arg2\": \"value2\"}"
    ]))
}
