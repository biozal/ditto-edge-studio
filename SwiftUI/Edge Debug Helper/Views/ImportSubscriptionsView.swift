import Foundation
import SwiftUI

struct ImportSubscriptionsView: View {
    @EnvironmentObject private var appState: AppState
    @Binding var isPresented: Bool
    @State private var viewModel: ViewModel

    init(isPresented: Binding<Bool>, existingSubscriptions: [DittoSubscription], selectedAppId: String) {
        _isPresented = isPresented
        _viewModel = State(initialValue: ViewModel(
            existingSubscriptions: existingSubscriptions,
            selectedAppId: selectedAppId
        ))
    }

    var body: some View {
        VStack(spacing: 20) {
            // Header
            Text("Import Subscriptions from Devices")
                .font(.title2)
                .bold()
                .padding(.top)

            if viewModel.isLoading {
                Spacer()
                ProgressView("Loading device subscriptions...")
                Spacer()
            } else if let error = viewModel.errorMessage {
                Spacer()
                ContentUnavailableView(
                    "Error Loading Subscriptions",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
                Spacer()
            } else if viewModel.importableSubscriptions.isEmpty {
                Spacer()
                ContentUnavailableView(
                    "No New Subscriptions Found",
                    systemImage: "checkmark.circle",
                    description: Text("All device subscriptions are already imported")
                )
                Spacer()
            } else {
                subscriptionsList
            }

            // Import status
            if viewModel.isImporting {
                ProgressView(viewModel.importStatus)
                    .padding()
            }

            // Actions
            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .disabled(viewModel.isImporting)

                Spacer()

                Text("\(viewModel.selectedCount) selected")
                    .foregroundColor(.secondary)

                Button("Import Selected") {
                    Task {
                        do {
                            try await viewModel.importSelectedSubscriptions()
                            try await Task.sleep(nanoseconds: 500_000_000) // 0.5s delay
                            isPresented = false
                        } catch {
                            appState.setError(error)
                        }
                    }
                }
                .disabled(viewModel.selectedCount == 0 || viewModel.isImporting)
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 700, height: 500)
        .task {
            await viewModel.loadDevicesAndSubscriptions()
        }
    }

    private var subscriptionsList: some View {
        List {
            ForEach(viewModel.importableSubscriptions) { subscription in
                HStack(alignment: .top, spacing: 12) {
                    Toggle("", isOn: Binding(
                        get: { subscription.isSelected },
                        set: { _ in viewModel.toggleSelection(for: subscription.id) }
                    ))
                    .labelsHidden()
                    #if os(macOS)
                        .toggleStyle(.checkbox)
                    #endif

                    VStack(alignment: .leading, spacing: 6) {
                        Text(subscription.collectionName)
                            .font(.headline)

                        Text(subscription.query)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)

                        HStack {
                            Label(subscription.deviceName, systemImage: "desktopcomputer")
                            Text("•")
                            Text(subscription.deviceInfo)
                        }
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}

// MARK: - ViewModel

extension ImportSubscriptionsView {
    @Observable
    @MainActor
    class ViewModel {
        var importableSubscriptions: [ImportableSubscription] = []
        var isLoading = false
        var errorMessage: String?
        var importStatus = ""
        var isImporting = false

        private let queryService = QueryService.shared
        private let existingSubscriptions: [DittoSubscription]
        private let selectedAppId: String

        init(existingSubscriptions: [DittoSubscription], selectedAppId: String) {
            self.existingSubscriptions = existingSubscriptions
            self.selectedAppId = selectedAppId
        }

        func loadDevicesAndSubscriptions() async {
            isLoading = true
            errorMessage = nil

            do {
                let peerInfos = try await queryService.fetchSmallPeerInfo()
                processSmallPeerInfo(peerInfos)
            } catch {
                errorMessage = "Failed to fetch device info: \(error.localizedDescription)"
            }

            isLoading = false
        }

        private func processSmallPeerInfo(_ peerInfos: [SmallPeerInfo]) {
            var result: [ImportableSubscription] = []
            var seenQueries: Set<String> = []

            for peer in peerInfos {
                guard let localSubs = peer.local_subscriptions,
                      let queries = localSubs.queries else
                {
                    continue
                }

                for queryInfo in queries {
                    // Skip system collections
                    guard !queryInfo.isSystemCollection,
                          let collectionName = queryInfo.collectionName else
                    {
                        continue
                    }

                    let queryText = queryInfo.query

                    // Check if query already exists in current subscriptions
                    let alreadyExists = existingSubscriptions.contains {
                        $0.query == queryText
                    }

                    // Check if we've already added this query in this import session
                    let alreadyInList = seenQueries.contains(queryText)

                    if !alreadyExists && !alreadyInList {
                        let importable = ImportableSubscription(
                            deviceName: peer.displayName,
                            deviceInfo: peer.deviceInfo,
                            collectionName: collectionName,
                            query: queryText,
                            isSelected: false
                        )
                        result.append(importable)
                        seenQueries.insert(queryText)
                    }
                }
            }

            importableSubscriptions = result
        }

        func toggleSelection(for id: UUID) {
            if let index = importableSubscriptions.firstIndex(where: { $0.id == id }) {
                importableSubscriptions[index].isSelected.toggle()
            }
        }

        func importSelectedSubscriptions() async throws {
            isImporting = true
            let selected = importableSubscriptions.filter(\.isSelected)

            for (index, sub) in selected.enumerated() {
                importStatus = "Importing \(index + 1) of \(selected.count): \(sub.collectionName)..."

                var newSubscription = DittoSubscription(id: UUID().uuidString)
                newSubscription.name = "Imported: \(sub.collectionName)"
                newSubscription.query = sub.query
                newSubscription.args = nil

                try await SubscriptionsRepository.shared.saveDittoSubscription(newSubscription)
            }

            importStatus = "Import complete!"
            isImporting = false
        }

        var selectedCount: Int {
            importableSubscriptions.count(where: { $0.isSelected })
        }
    }
}
