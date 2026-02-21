import Combine
import SwiftUI

struct DatabaseCard: View {
    let dittoApp: DittoConfigForDatabase
    var onEdit: () -> Void

    @State private var showAppId = false
    @State private var showAuthToken = false
    @State private var showAuthUrl = false
    @State private var showWebsocketUrl = false

    #if os(iOS)
    @Environment(\.colorScheme) var colorScheme

    private var nameColor: Color {
        colorScheme == .dark ? Color.dittoYellow : Color.black
    }

    private var iconColor: Color {
        colorScheme == .dark ? Color.dittoYellow : Color.primary
    }

    private var shadowOpacity: Double {
        colorScheme == .dark ? 0.40 : 0.10
    }
    #endif

    var body: some View {
        #if os(iOS)
        VStack(alignment: .leading, spacing: 12) {
            // Header: icon + name — always gets full card width
            HStack(alignment: .center, spacing: 12) {
                FontAwesomeText(icon: DataIcon.databaseThin, size: 40, color: iconColor)
                    .frame(width: 40, height: 40)
                Text(dittoApp.name)
                    .font(.title3)
                    .foregroundColor(nameColor)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            // Fields below
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
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(colorScheme == .dark
                    ? AnyShapeStyle(LinearGradient(
                        colors: [Color.Ditto.trafficBlack, Color.Ditto.jetBlack],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    : AnyShapeStyle(Color(uiColor: .systemBackground)))
                .shadow(color: Color.black.opacity(shadowOpacity), radius: 6, x: 0, y: 3)
        )
        #else
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
        .background(RoundedRectangle(cornerRadius: 20)
            .fill(.regularMaterial)
            .overlay(RoundedRectangle(cornerRadius: 20)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)))
        .cornerRadius(20)
        .elevatedShadow()
        #endif
    }
}
