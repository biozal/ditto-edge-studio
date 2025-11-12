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

                    Text("Manage your Ditto database connections and monitor peer synchronization")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)

                Divider()

                // Connected Peers Section
                VStack(alignment: .leading, spacing: 16) {
                    // Header with last update time
                    HStack {
                        Text("Connected Peers")
                            .font(.title2)
                            .bold()

                        Spacer()

                        if isSyncEnabled {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.caption)
                                Text("Sync Active")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        } else {
                            HStack(spacing: 4) {
                                Image(systemName: "pause.circle.fill")
                                    .foregroundColor(.orange)
                                    .font(.caption)
                                Text("Sync Paused")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    if syncStatusItems.isEmpty {
                        HStack {
                            Spacer()
                            if isSyncEnabled {
                                EmptyStateView(
                                    "No Peers Connected",
                                    systemImage: "arrow.trianglehead.2.clockwise.rotate.90",
                                    description: Text("Sync is active but no peers are currently connected")
                                )
                            } else {
                                EmptyStateView(
                                    "Sync Paused",
                                    systemImage: "pause.circle",
                                    description: Text("Enable sync to see connected peers and their status")
                                )
                            }
                            Spacer()
                        }
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(syncStatusItems, id: \.peerType) { status in
                                syncStatusCard(for: status)
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
    }

    private func syncStatusCard(for status: SyncStatusInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with peer type and connection status
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(status.peerType)
                        .font(.headline)
                        .bold()

                    Text(status.syncSessionStatus)
                        .font(.subheadline)
                        .foregroundColor(status.syncSessionStatus == "Connected" ? .green : .orange)
                }

                Spacer()

                // Status icon
                Image(systemName: status.syncSessionStatus == "Connected" ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundColor(status.syncSessionStatus == "Connected" ? .green : .orange)
                    .font(.title2)
            }

            // Sync information
            VStack(alignment: .leading, spacing: 8) {
                if let commitId = status.syncedUpToLocalCommitId {
                    HStack {
                        Image(systemName: "checkmark.circle")
                            .foregroundColor(.green)
                            .font(.caption)
                        Text("Synced to local database commit: \(commitId)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                HStack {
                    Image(systemName: "person.circle")
                        .foregroundColor(.blue)
                        .font(.caption)
                    Text("Peer ID: \(status.id)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if status.lastUpdateReceivedTime != nil {
                    HStack {
                        Image(systemName: "clock")
                            .foregroundColor(.gray)
                            .font(.caption)
                        Text("Last update: \(status.formattedLastUpdate)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
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