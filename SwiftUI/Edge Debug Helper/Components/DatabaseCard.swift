import Combine
import SwiftUI

struct DatabaseCard: View {
    let dittoApp: DittoConfigForDatabase
    var onEdit: () -> Void

    @State private var showAppId = false
    @State private var showAuthToken = false
    @State private var showAuthUrl = false
    @State private var showWebsocketUrl = false

    var body: some View {
        HStack(alignment: .top, spacing: 32) {
            // Left VStack: Icon and Name
            VStack(spacing: 12) {
                FontAwesomeText(icon: DataIcon.databaseThin, size: 56, color: .accentColor)
                    .frame(width: 56, height: 56)
                Text(dittoApp.name)
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(minWidth: 80, maxWidth: 120)

            // Right VStack: Secure fields
            VStack(alignment: .leading, spacing: 12) {
                SecureField(
                    label: "Database ID",
                    value: dittoApp.databaseId,
                    isRevealed: $showAppId
                )
                SecureField(
                    label: "Token",
                    value: dittoApp.token,
                    isRevealed: $showAuthToken
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(20)
        #if os(iOS)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(20)
        #else
            .background(RoundedRectangle(cornerRadius: 20)
                .fill(.regularMaterial)
                .overlay(RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)))
            .cornerRadius(20)
            .elevatedShadow()
        #endif
    }
}
