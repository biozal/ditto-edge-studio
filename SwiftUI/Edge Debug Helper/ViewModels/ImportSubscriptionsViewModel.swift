import Foundation

@Observable
@MainActor
class ImportSubscriptionsViewModel {
    var importableSubscriptions: [ImportableSubscription] = []
    var isLoading = false
    var errorMessage: String?
    var importStatus: String = ""
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
                  let queries = localSubs.queries else {
                continue
            }

            for queryInfo in queries {
                // Skip system collections
                guard !queryInfo.isSystemCollection,
                      let collectionName = queryInfo.collectionName else {
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
        let selected = importableSubscriptions.filter { $0.isSelected }

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
        importableSubscriptions.filter { $0.isSelected }.count
    }
}
