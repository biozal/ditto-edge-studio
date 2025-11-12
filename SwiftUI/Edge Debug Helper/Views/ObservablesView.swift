//
//  ObservablesView.swift
//  Edge Studio
//
//  Main view for managing and displaying observables
//

import SwiftUI

struct ObservablesView: View {
    @Binding var observables: [DittoObservable]
    @Binding var selectedObservable: DittoObservable?
    @Binding var observableEvents: [DittoObserveEvent]
    @Binding var selectedEventId: String?
    @Binding var eventMode: String
    @EnvironmentObject var appState: AppState

    var onLoadEvents: () async -> Void
    var onRegisterObserver: (DittoObservable) async throws -> Void
    var onRemoveObserver: (DittoObservable) async throws -> Void
    var onDeleteObservable: (DittoObservable) async throws -> Void

    var body: some View {
        VStack(alignment: .trailing) {
#if os(macOS)
            VSplitView {
                // Top pane: Events list
                topPane
                    .frame(minHeight: 200)

                // Bottom pane: Event details
                bottomPane
                    .frame(minHeight: 200)
            }
#else
            VStack {
                topPane
                bottomPane
            }
#endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
#if os(iOS)
        .toolbar {
            // iOS toolbar items can be added here if needed
        }
#endif
    }

    // MARK: - Top Pane

    private var topPane: some View {
        Group {
            if selectedObservable == nil {
                ObservableEmptyStateView(
                    title: "No Observer Selected",
                    systemImage: "exclamationmark.triangle.fill",
                    description: "Please select an observer from the sidebar to view events."
                )
            } else {
                ObservableEventsListView(
                    events: $observableEvents,
                    selectedEventId: $selectedEventId
                )
            }
        }
    }

    // MARK: - Bottom Pane

    private var bottomPane: some View {
        ObservableEventDetailPane(
            events: $observableEvents,
            eventMode: $eventMode,
            hasSelectedObservable: selectedObservable != nil
        )
    }
}

// MARK: - Observables Sidebar View

struct ObservablesSidebarView: View {
    @Binding var observables: [DittoObservable]
    @Binding var selectedObservable: DittoObservable?
    @EnvironmentObject var appState: AppState

    var onSelectObservable: (DittoObservable) async -> Void
    var onRegisterObserver: (DittoObservable) async throws -> Void
    var onRemoveObserver: (DittoObservable) async throws -> Void
    var onDeleteObservable: (DittoObservable) async throws -> Void

    var body: some View {
        VStack(alignment: .leading) {
            if observables.isEmpty {
                Spacer()
                ContentUnavailableView(
                    "No Observers",
                    systemImage: "exclamationmark.triangle.fill",
                    description: Text(
                        "No observers have been added yet. Click the plus button to add your first observers."
                    )
                )
            } else {
                List(observables) { observer in
                    ObservableCard(observer: observer)
                        .onTapGesture {
                            selectedObservable = observer
                            Task {
                                await onSelectObservable(observer)
                            }
                        }
#if os(macOS)
                        .contextMenu {
                            observerContextMenuButtons(for: observer)
                        }
#else
                        .swipeActions(edge: .trailing) {
                            observerSwipeActions(for: observer)
                        }
#endif
                }
            }
            Spacer()
        }
    }

    // MARK: - Context Menu Buttons

    @ViewBuilder
    private func observerContextMenuButtons(for observer: DittoObservable) -> some View {
        if observer.storeObserver == nil {
            Button {
                Task {
                    do {
                        try await onRegisterObserver(observer)
                    } catch {
                        appState.setError(error)
                    }
                }
            } label: {
                Label("Activate", systemImage: "play.circle")
                    .labelStyle(.titleAndIcon)
            }
        } else {
            Button {
                Task {
                    do {
                        try await onRemoveObserver(observer)
                    } catch {
                        appState.setError(error)
                    }
                }
            } label: {
                Label("Stop", systemImage: "stop.circle")
                    .labelStyle(.titleAndIcon)
            }
        }

        Button {
            Task {
                do {
                    try await onDeleteObservable(observer)
                } catch {
                    appState.setError(error)
                }
            }
        } label: {
            Label("Delete", systemImage: "trash")
                .labelStyle(.titleAndIcon)
        }
    }

    // MARK: - Swipe Actions

    @ViewBuilder
    private func observerSwipeActions(for observer: DittoObservable) -> some View {
        if observer.storeObserver == nil {
            Button {
                Task {
                    do {
                        try await onRegisterObserver(observer)
                    } catch {
                        appState.setError(error)
                    }
                }
            } label: {
                Label("Activate", systemImage: "play.circle")
            }
        } else {
            Button {
                Task {
                    do {
                        try await onRemoveObserver(observer)
                    } catch {
                        appState.setError(error)
                    }
                }
            } label: {
                Label("Stop", systemImage: "stop.circle")
            }
        }

        Button(role: .destructive) {
            Task {
                do {
                    try await onDeleteObservable(observer)
                } catch {
                    appState.setError(error)
                }
            }
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }
}
