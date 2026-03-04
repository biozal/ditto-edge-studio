import SwiftUI

struct ObserverEventsTableView: View {
    let events: [DittoObserveEvent]
    @Binding var selectedEventId: String?

    #if os(macOS)
    private let columnDefs: [(header: String, width: CGFloat)] = [
        ("Time", 180), ("Count", 70), ("Inserted", 80),
        ("Updated", 80), ("Deleted", 70), ("Moves", 70)
    ]
    #else
    private let columnDefs: [(header: String, width: CGFloat)] = [
        ("Time", 200), ("Count", 80), ("Inserted", 100),
        ("Updated", 100), ("Deleted", 90), ("Moves", 80)
    ]
    #endif

    var body: some View {
        #if os(macOS)
        macOSTable
        #else
        iOSTable
        #endif
    }

    // MARK: - macOS

    #if os(macOS)
    private var macOSTable: some View {
        GeometryReader { geometry in
            ScrollView([.horizontal, .vertical]) {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    Section {
                        ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                            let isSelected = selectedEventId == event.id
                            let values = rowValues(for: event)
                            HStack(spacing: 0) {
                                ForEach(columnDefs.indices, id: \.self) { colIdx in
                                    if colIdx > 0 { Divider() }
                                    Text(values[colIdx])
                                        .font(.system(.body, design: .monospaced))
                                        .lineLimit(1)
                                        .frame(width: columnDefs[colIdx].width, alignment: .leading)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 8)
                                }
                                Divider()
                            }
                            .frame(minWidth: geometry.size.width)
                            .background(
                                isSelected
                                    ? Color.accentColor.opacity(0.2)
                                    : (index % 2 == 0
                                        ? Color(NSColor.textBackgroundColor)
                                        : Color(NSColor.controlBackgroundColor).opacity(0.3))
                            )
                            .onTapGesture {
                                selectedEventId = isSelected ? nil : event.id
                            }
                        }
                    } header: {
                        HStack(spacing: 0) {
                            ForEach(columnDefs.indices, id: \.self) { colIdx in
                                if colIdx > 0 { Divider() }
                                Text(columnDefs[colIdx].header)
                                    .font(.system(.headline, design: .monospaced))
                                    .frame(width: columnDefs[colIdx].width, alignment: .leading)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 8)
                                    .background(Color(NSColor.windowBackgroundColor))
                            }
                            Divider()
                        }
                        .frame(minWidth: geometry.size.width)
                        .background(Color(NSColor.windowBackgroundColor))
                    }
                }
                .frame(minHeight: geometry.size.height, alignment: .top)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    #endif

    // MARK: - iOS

    #if os(iOS)
    private var iOSTable: some View {
        GeometryReader { geometry in
            ScrollView([.horizontal, .vertical]) {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    Section {
                        ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                            let isSelected = selectedEventId == event.id
                            let values = rowValues(for: event)
                            HStack(spacing: 0) {
                                ForEach(columnDefs.indices, id: \.self) { colIdx in
                                    if colIdx > 0 { Divider() }
                                    Text(values[colIdx])
                                        .font(.system(.body, design: .monospaced))
                                        .lineLimit(1)
                                        .frame(width: columnDefs[colIdx].width, alignment: .leading)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 8)
                                }
                                Divider()
                            }
                            .background(
                                isSelected
                                    ? Color.accentColor.opacity(0.2)
                                    : (index % 2 == 0
                                        ? Color(UIColor.systemBackground)
                                        : Color(UIColor.secondarySystemBackground).opacity(0.3))
                            )
                            .onTapGesture {
                                selectedEventId = isSelected ? nil : event.id
                            }
                        }
                    } header: {
                        HStack(spacing: 0) {
                            ForEach(columnDefs.indices, id: \.self) { colIdx in
                                if colIdx > 0 { Divider() }
                                Text(columnDefs[colIdx].header)
                                    .font(.system(.headline, design: .monospaced))
                                    .lineLimit(1)
                                    .frame(width: columnDefs[colIdx].width, alignment: .leading)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 8)
                                    .background(Color(UIColor.systemBackground))
                            }
                            Divider()
                        }
                        .background(Color(UIColor.systemBackground))
                    }
                }
                .frame(minHeight: geometry.size.height, alignment: .top)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    #endif

    // MARK: - Helpers

    private func rowValues(for event: DittoObserveEvent) -> [String] {
        [
            event.eventTime,
            "\(event.data.count)",
            "\(event.insertIndexes.count)",
            "\(event.updatedIndexes.count)",
            "\(event.deletedIndexes.count)",
            "\(event.movedIndexes.count)"
        ]
    }
}
