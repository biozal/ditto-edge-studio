//
//  HomeDetailView.swift
//  Edge Studio
//

import SwiftUI

struct HomeDetailView: View {
    @Binding var syncStatusItems: [SyncStatusInfo]
    @Binding var isSyncEnabled: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("Welcome to Edge Studio")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text("Manage your Ditto database connections")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)

                Divider()

                // Quick Actions or Info Section
                VStack(alignment: .leading, spacing: 16) {
                    Text("Quick Start")
                        .font(.title2)
                        .bold()

                    VStack(alignment: .leading, spacing: 12) {
                        QuickActionCard(
                            icon: "arrow.triangle.2.circlepath",
                            title: "Sync",
                            description: "Monitor real-time peer synchronization",
                            iconColor: .blue
                        )

                        QuickActionCard(
                            icon: "cylinder.split.1x2",
                            title: "Store Explorer",
                            description: "Browse collections, subscriptions, and observers",
                            iconColor: .green
                        )

                        QuickActionCard(
                            icon: "doc.text",
                            title: "Query",
                            description: "Execute DQL queries and view results",
                            iconColor: .orange
                        )

                        QuickActionCard(
                            icon: "gearshape",
                            title: "Ditto Tools",
                            description: "Access advanced database tools and utilities",
                            iconColor: .purple
                        )
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
    }
}

// MARK: - Quick Action Card
struct QuickActionCard: View {
    let icon: String
    let title: String
    let description: String
    let iconColor: Color

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(iconColor)
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .bold()

                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
    }
}

struct EmptyStateView: View {
    let title: String
    let systemImage: String
    let description: Text?

    init(_ title: String, systemImage: String, description: Text? = nil) {
        self.title = title
        self.systemImage = systemImage
        self.description = description
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            VStack(spacing: 8) {
                Text(title)
                    .font(.headline)
                    .multilineTextAlignment(.center)

                if let description = description {
                    description
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .padding(.vertical, 40)
    }
}

#Preview {
    HomeDetailView(
        syncStatusItems: .constant([]),
        isSyncEnabled: .constant(true)
    )
}