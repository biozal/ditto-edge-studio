//
//  DittoAppCard.swift
//  Ditto Edge Studio
//
//  Created by Aaron LaBeau on 5/18/25.
//

import SwiftUI
import Combine

struct DittoAppCard: View {
    let dittoApp: DittoAppConfig
    var onEdit: () -> Void
    
    @State private var showAppId = false
    @State private var showAuthToken = false
    @State private var showAuthUrl = false
    @State private var showWebsocketUrl = false
    
    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            // Left VStack: Icon and Name
            VStack(spacing: 12) {
                Image(systemName: "app.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 64, height: 64)
                    .foregroundColor(.accentColor)
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
                    label: "App ID",
                    value: dittoApp.appId,
                    isRevealed: $showAppId
                )
                SecureField(
                    label: "Auth Token",
                    value: dittoApp.authToken,
                    isRevealed: $showAuthToken
                )
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
