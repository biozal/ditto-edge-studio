import SwiftUI

private let dittoBlack = Color(red: 42 / 255, green: 41 / 255, blue: 42 / 255)
private let dittoBlackLight = Color(red: 65 / 255, green: 64 / 255, blue: 65 / 255)

struct SubscriptionCard: View {
    let subscription: DittoSubscription

    var body: some View {
        HStack(alignment: .top, spacing: 32) {
            // Left VStack: Icon and Name
            VStack(alignment: .leading, spacing: 12) {
                Text(subscription.name)
                    .font(.headline)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subscription.query)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                if let args = subscription.args, !args.isEmpty {
                    Text(args)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.60))
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
                    colors: [dittoBlackLight, dittoBlack],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .shadow(color: Color.black.opacity(0.40), radius: 6, x: 0, y: 3)
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
