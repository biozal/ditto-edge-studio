//
//  ObservableEventsListView.swift
//  Edge Studio
//
//  Component for displaying the list of observable events in a table format
//

import SwiftUI

struct ObservableEventsListView: View {
    @Binding var events: [DittoObserveEvent]
    @Binding var selectedEventId: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if events.isEmpty {
                ContentUnavailableView(
                    "No Observer Events",
                    systemImage: "exclamationmark.triangle.fill",
                    description: Text(
                        "Activate an observer to see observable events."
                    )
                )
            } else {
                // Custom list with hoverable rows
                ScrollView {
                    VStack(spacing: 0) {
                        // Header row
                        EventsTableHeader()

                        // Data rows
                        ForEach(events) { event in
                            EventsTableRow(
                                event: event,
                                isSelected: selectedEventId == event.id
                            )
                            .onTapGesture {
                                selectedEventId = event.id
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Events Table Header

struct EventsTableHeader: View {
    var body: some View {
        HStack(spacing: 12) {
            Text("Time")
                .font(.caption)
                .fontWeight(.semibold)
                .frame(width: 120, alignment: .leading)
            Text("Count")
                .font(.caption)
                .fontWeight(.semibold)
                .frame(width: 60, alignment: .leading)
            Text("Inserted")
                .font(.caption)
                .fontWeight(.semibold)
                .frame(width: 60, alignment: .leading)
            Text("Updated")
                .font(.caption)
                .fontWeight(.semibold)
                .frame(width: 60, alignment: .leading)
            Text("Deleted")
                .font(.caption)
                .fontWeight(.semibold)
                .frame(width: 60, alignment: .leading)
            Text("Moves")
                .font(.caption)
                .fontWeight(.semibold)
                .frame(width: 60, alignment: .leading)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.1))
    }
}

// MARK: - Events Table Row

struct EventsTableRow: View {
    let event: DittoObserveEvent
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(event.eventTime)
                .font(.system(size: 12))
                .frame(width: 120, alignment: .leading)
            Text("\(event.data.count)")
                .font(.system(size: 12))
                .frame(width: 60, alignment: .leading)
            Text("\(event.insertIndexes.count)")
                .font(.system(size: 12))
                .frame(width: 60, alignment: .leading)
            Text("\(event.updatedIndexes.count)")
                .font(.system(size: 12))
                .frame(width: 60, alignment: .leading)
            Text("\(event.deletedIndexes.count)")
                .font(.system(size: 12))
                .frame(width: 60, alignment: .leading)
            Text("\(event.movedIndexes.count)")
                .font(.system(size: 12))
                .frame(width: 60, alignment: .leading)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .hoverableCard(isSelected: isSelected, spacing: 0)
    }
}
