//
//  ObservableEventDetailPane.swift
//  Edge Studio
//
//  Bottom pane component for displaying historical event details
//

import SwiftUI

struct ObservableEventDetailPane: View {
    @Binding var events: [DittoObserveEvent]
    @Binding var eventMode: String
    let hasSelectedObservable: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if hasSelectedObservable && !events.isEmpty {
                // Header with picker
                EventDetailHeader(eventMode: $eventMode)

                // Historical list of events
                EventHistoryList(events: events, eventMode: eventMode)

            } else if hasSelectedObservable && events.isEmpty {
                // Observable selected but no events yet
                ObservableEmptyStateView(
                    title: "No Events Yet",
                    systemImage: "clock",
                    description: "Events will appear here as they are observed"
                )
            } else {
                // No observable selected
                ObservableEmptyStateView(
                    title: "No Observer Selected",
                    systemImage: "eye.slash",
                    description: "Select an observer to view events"
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.controlBackgroundColor).opacity(0.3))
    }
}

// MARK: - Event Detail Header

struct EventDetailHeader: View {
    @Binding var eventMode: String

    var body: some View {
        HStack {
            Text("Event History")
                .font(.headline)
                .padding(.leading, 12)

            Spacer()

            Picker("", selection: $eventMode) {
                Text("Inserted")
                    .tag("inserted")
                Text("Updated")
                    .tag("updated")
                Text("Deleted")
                    .tag("deleted")
            }
            .pickerStyle(.segmented)
            .frame(width: 250)
            .padding(.trailing, 12)
        }
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(Color.secondary.opacity(0.05))
    }
}

// MARK: - Event History List

struct EventHistoryList: View {
    let events: [DittoObserveEvent]
    let eventMode: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(events) { event in
                    EventHistoryCard(event: event, eventMode: eventMode)
                }
            }
            .padding(.vertical, 12)
        }
    }
}

// MARK: - Event History Card

struct EventHistoryCard: View {
    let event: DittoObserveEvent
    let eventMode: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Event header with timestamp and counts
            EventHistoryCardHeader(event: event)

            // Data based on selected mode
            EventHistoryCardContent(event: event, eventMode: eventMode)

            Divider()
                .padding(.top, 8)
        }
        .padding(.horizontal, 8)
    }
}

// MARK: - Event History Card Header

struct EventHistoryCardHeader: View {
    let event: DittoObserveEvent

    var body: some View {
        HStack {
            Text(event.eventTime)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            Spacer()
            Text("Inserted: \(event.insertIndexes.count) | Updated: \(event.updatedIndexes.count) | Deleted: \(event.deletedIndexes.count)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.accentColor.opacity(0.1))
        .cornerRadius(6)
    }
}

// MARK: - Event History Card Content

struct EventHistoryCardContent: View {
    let event: DittoObserveEvent
    let eventMode: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            switch eventMode {
            case "inserted":
                EventDataList(
                    data: event.getInsertedData(),
                    isEmpty: event.insertIndexes.isEmpty,
                    emptyMessage: "No inserted items in this event"
                )
            case "updated":
                EventDataList(
                    data: event.getUpdatedData(),
                    isEmpty: event.updatedIndexes.isEmpty,
                    emptyMessage: "No updated items in this event"
                )
            case "deleted":
                DeletedDataView(
                    deletedIndexes: event.deletedIndexes
                )
            default:
                EmptyView()
            }
        }
    }
}

// MARK: - Event Data List

struct EventDataList: View {
    let data: [String]
    let isEmpty: Bool
    let emptyMessage: String

    var body: some View {
        if !isEmpty {
            ForEach(data, id: \.self) { item in
                Text(item)
                    .font(.system(size: 11, design: .monospaced))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 2)
            }
        } else {
            Text(emptyMessage)
                .font(.caption)
                .foregroundColor(.secondary)
                .italic()
                .padding(.horizontal, 12)
        }
    }
}

// MARK: - Deleted Data View

struct DeletedDataView: View {
    let deletedIndexes: [Int]

    var body: some View {
        if !deletedIndexes.isEmpty {
            Text("Deleted indexes: \(deletedIndexes.map(String.init).joined(separator: ", "))")
                .font(.system(size: 11, design: .monospaced))
                .padding(.horizontal, 12)
                .padding(.vertical, 2)
        } else {
            Text("No deleted items in this event")
                .font(.caption)
                .foregroundColor(.secondary)
                .italic()
                .padding(.horizontal, 12)
        }
    }
}
