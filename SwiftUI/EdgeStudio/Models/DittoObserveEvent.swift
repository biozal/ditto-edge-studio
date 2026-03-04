import Foundation

public struct DittoObserveEvent: Identifiable {
    /// used for tracking unique observe events
    public var id: String

    /// used to link to the Selected Observer
    public var observeId: String

    public var data: [String] = []
    public var insertIndexes: [Int] = []
    public var updatedIndexes: [Int] = []
    public var movedIndexes: [(from: Int, to: Int)] = []
    public var deletedIndexes: [Int] = []

    public var eventTime = ""
}

extension DittoObserveEvent {
    static func new(observeId: String) -> DittoObserveEvent {
        DittoObserveEvent(
            id: UUID().uuidString,
            observeId: observeId
        )
    }
}

// MARK: Calculate Data

extension DittoObserveEvent {
    func getInsertedData() -> [String] {
        getData(indexes: insertIndexes)
    }

    func getUpdatedData() -> [String] {
        getData(indexes: updatedIndexes)
    }

    private func getData(indexes: [Int]) -> [String] {
        var items: [String] = []
        if !data.isEmpty && !indexes.isEmpty {
            for index in indexes {
                if index >= 0 && index < data.count {
                    items.append(data[index])
                }
            }
        }
        return items
    }
}
