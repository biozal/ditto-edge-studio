//
//  ViewContainer.swift
//  Edge Studio
//
//  Created on today's date.
//

import SwiftUI

// MARK: - View Context Definition
enum ViewContext: Identifiable {
    case home
    case query(subscription: DittoSubscription?)
    case observer(observable: DittoObservable)
    case observersView
    case collection(name: String)
    case empty

    var id: String {
        switch self {
        case .home:
            return "home"
        case .query(let subscription):
            return "query_\(subscription?.id ?? "new")"
        case .observer(let observable):
            return "observer_\(observable.id)"
        case .observersView:
            return "observers"
        case .collection(let name):
            return "collection_\(name)"
        case .empty:
            return "empty"
        }
    }

    var title: String {
        switch self {
        case .home:
            return "Home"
        case .query(let subscription):
            return subscription?.name.isEmpty == false ? subscription!.name : "Query"
        case .observer(let observable):
            return observable.name.isEmpty ? "Observer" : observable.name
        case .observersView:
            return "Observers"
        case .collection(let name):
            return name
        case .empty:
            return "Store Explorer"
        }
    }

    var systemImage: String {
        switch self {
        case .home:
            return "house"
        case .query:
            return "arrow.trianglehead.2.clockwise"
        case .observer:
            return "eye"
        case .observersView:
            return "eye"
        case .collection:
            return "square.stack.fill"
        case .empty:
            return "cylinder.split.1x2"
        }
    }
}

// MARK: - Unified View Container
struct ViewContainer: View {
    let context: ViewContext
    @Bindable var viewModel: MainStudioView.ViewModel
    let appState: AppState

    var body: some View {
        switch context {
        case .home:
            HomeDetailView(
                syncStatusItems: $viewModel.syncStatusItems,
                isSyncEnabled: $viewModel.isSyncEnabled
            )

        case .query(let subscription):
            VSplitView {
                // Query editor at the top
                QueryEditorView(
                    queryText: $viewModel.selectedQuery,
                    executeModes: $viewModel.executeModes,
                    selectedExecuteMode: $viewModel.selectedExecuteMode,
                    isLoading: $viewModel.isQueryExecuting,
                    onExecuteQuery: {
                        await viewModel.executeQuery(appState: appState)
                    },
                    onAddToFavorites: {
                        await viewModel.addCurrentQueryToFavorites(appState: appState)
                    }
                )

                // Results at the bottom
                QueryResultsView(
                    jsonResults: $viewModel.jsonResults,
                    queryText: viewModel.selectedQuery,
                    hasExecutedQuery: viewModel.hasExecutedQuery,
                    appId: viewModel.selectedApp.appId
                )
            }
            .onAppear {
                if let subscription = subscription {
                    viewModel.selectedQuery = subscription.query
                }
            }
            .onChange(of: viewModel.selectedQuery) { oldValue, newValue in
                // Save query changes to the dictionary for query tabs
                if case .query(let queryId) = viewModel.selectedItem {
                    viewModel.tabQueries[queryId] = newValue

                    // Update the tab title in the dictionary
                    let newTitle = viewModel.generateTabTitle(from: newValue)
                    viewModel.tabTitles[queryId] = newTitle
                }
            }

        case .observer(let observable):
            VSplitView {
                // Top: Events table
                ObserverEventsTableView(
                    observable: observable,
                    events: $viewModel.observableEvents,
                    selectedEventId: $viewModel.selectedEventId
                )
                .frame(minHeight: 200)

                // Bottom: Selected event details
                ObserverEventDetailView(
                    selectedEvent: viewModel.selectedEventObject,
                    eventMode: $viewModel.eventMode
                )
            }
            .onAppear {
                viewModel.selectedObservable = observable
                Task {
                    await viewModel.loadObservedEvents()
                }
            }

        case .observersView:
            // Single observers tab showing all events from all observers
            AllObserversEventsView(
                observers: $viewModel.observerables,
                events: $viewModel.observableEvents,
                selectedEventId: $viewModel.selectedEventId,
                selectedObservable: $viewModel.selectedObservable,
                viewModel: viewModel,
                appState: appState
            )

        case .collection(let name):
            VSplitView {
                // Query editor at the top
                QueryEditorView(
                    queryText: $viewModel.selectedQuery,
                    executeModes: $viewModel.executeModes,
                    selectedExecuteMode: $viewModel.selectedExecuteMode,
                    isLoading: $viewModel.isQueryExecuting,
                    onExecuteQuery: {
                        await viewModel.executeQuery(appState: appState)
                    },
                    onAddToFavorites: {
                        await viewModel.addCurrentQueryToFavorites(appState: appState)
                    }
                )

                // Results at the bottom
                QueryResultsView(
                    jsonResults: $viewModel.jsonResults,
                    queryText: viewModel.selectedQuery,
                    hasExecutedQuery: viewModel.hasExecutedQuery,
                    appId: viewModel.selectedApp.appId
                )
            }
            .onAppear {
                viewModel.selectedQuery = "SELECT * FROM \(name)"
            }

        case .empty:
            DefaultStoreExplorerView()
        }
    }
}

// MARK: - Default Empty View
struct DefaultStoreExplorerView: View {
    var body: some View {
        VStack {
            Spacer()
            VStack(spacing: 16) {
                Image(systemName: "cylinder.split.1x2")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary)

                VStack(spacing: 8) {
                    Text("Store Explorer")
                        .font(.title2)
                        .bold()

                    Text("Select an item from the sidebar to begin exploring your Ditto store")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - Observer Views
struct ObserverEventsTableView: View {
    let observable: DittoObservable
    @Binding var events: [DittoObserveEvent]
    @Binding var selectedEventId: String?

    var body: some View {
        VStack {
            if events.filter({ $0.observeId == observable.id }).isEmpty {
                ContentUnavailableView(
                    "No Observer Events",
                    systemImage: "exclamationmark.triangle.fill",
                    description: Text(
                        observable.storeObserver == nil
                        ? "Activate this observer to see events."
                        : "Waiting for events from this observer..."
                    )
                )
            } else {
                let observerEvents = events.filter { $0.observeId == observable.id }
                Table(observerEvents, selection: Binding<Set<String>>(
                    get: {
                        if let selectedId = selectedEventId {
                            return Set([selectedId])
                        } else {
                            return Set<String>()
                        }
                    },
                    set: { newValue in
                        if let first = newValue.first {
                            selectedEventId = first
                        } else {
                            selectedEventId = nil
                        }
                    }
                )) {
                    TableColumn("Time") { event in
                        Text(event.eventTime)
                    }
                    TableColumn("Count") { event in
                        Text("\(event.data.count)")
                    }
                    TableColumn("Inserted") { event in
                        Text("\(event.insertIndexes.count)")
                    }
                    TableColumn("Updated") { event in
                        Text("\(event.updatedIndexes.count)")
                    }
                    TableColumn("Deleted") { event in
                        Text("\(event.deletedIndexes.count)")
                    }
                    TableColumn("Moves") { event in
                        Text("\(event.movedIndexes.count)")
                    }
                }
                .navigationTitle("Observer Events: \(observable.name)")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ObserverEventDetailView: View {
    let selectedEvent: DittoObserveEvent?
    @Binding var eventMode: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let event = selectedEvent {
                Picker("", selection: $eventMode) {
                    Text("Items")
                        .tag("items")
                    Text("Inserted")
                        .tag("inserted")
                    Text("Updated")
                        .tag("updated")
                }
                .padding(.top, 24)
                .padding(.bottom, 8)
                .pickerStyle(.segmented)
                .frame(width: 200)

                switch eventMode {
                case "inserted":
                    VStack(alignment: .leading, spacing: 0) {
                        ResultJsonViewer(resultText: event.getInsertedData())
                    }
                case "updated":
                    VStack(alignment: .leading, spacing: 0) {
                        ResultJsonViewer(resultText: event.getUpdatedData())
                    }
                default:
                    VStack(alignment: .leading, spacing: 0) {
                        ResultJsonViewer(resultText: event.data)
                    }
                }
                Spacer()
            } else {
                ResultJsonViewer(resultText: [])
            }
        }
        .padding(.leading, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - All Observers View
struct AllObserversEventsView: View {
    @Binding var observers: [DittoObservable]
    @Binding var events: [DittoObserveEvent]
    @Binding var selectedEventId: String?
    @Binding var selectedObservable: DittoObservable?
    var viewModel: MainStudioView.ViewModel
    var appState: AppState

    // Get the latest event for each observer
    private var latestEventsByObserver: [DittoObserveEvent] {
        var latestEvents: [String: DittoObserveEvent] = [:]

        for event in events {
            if let existingEvent = latestEvents[event.observeId] {
                // Keep the most recent event (compare by eventTime)
                if event.eventTime > existingEvent.eventTime {
                    latestEvents[event.observeId] = event
                }
            } else {
                latestEvents[event.observeId] = event
            }
        }

        return Array(latestEvents.values).sorted { event1, event2 in
            // Sort by observer name
            let observer1 = observers.first(where: { $0.id == event1.observeId })
            let observer2 = observers.first(where: { $0.id == event2.observeId })
            let name1 = observer1?.name ?? ""
            let name2 = observer2?.name ?? ""
            return name1 < name2
        }
    }

    var body: some View {
        VStack {
            Table(latestEventsByObserver, selection: Binding<Set<String>>(
                get: {
                    if let selectedId = selectedEventId {
                        return Set([selectedId])
                    } else {
                        return Set<String>()
                    }
                },
                set: { newValue in
                    if let first = newValue.first {
                        selectedEventId = first
                    } else {
                        selectedEventId = nil
                    }
                }
            )) {
                TableColumn("Observer") { event in
                    if let observer = observers.first(where: { $0.id == event.observeId }) {
                        Text(observer.name.isEmpty ? "Unnamed" : observer.name)
                    } else {
                        Text("Unknown")
                    }
                }
                TableColumn("Time") { event in
                    Text(event.eventTime)
                }
                TableColumn("Count") { event in
                    Text("\(event.data.count)")
                }
                TableColumn("Inserted") { event in
                    Text("\(event.insertIndexes.count)")
                }
                TableColumn("Updated") { event in
                    Text("\(event.updatedIndexes.count)")
                }
                TableColumn("Deleted") { event in
                    Text("\(event.deletedIndexes.count)")
                }
                TableColumn("Moves") { event in
                    Text("\(event.movedIndexes.count)")
                }
            }
            #if os(macOS)
            .contextMenu(forSelectionType: String.self) { selectedIds in
                if let selectedId = selectedIds.first,
                   let event = latestEventsByObserver.first(where: { $0.id == selectedId }),
                   let observer = observers.first(where: { $0.id == event.observeId }) {
                    // Context menu for a specific observer row
                    Button("Stop Observer") {
                        Task {
                            do {
                                try await viewModel.removeStoreObserver(observer)
                            } catch {
                                appState.setError(error)
                            }
                        }
                    }
                } else {
                    // Context menu for empty space - show start options
                    Menu("Start Observer") {
                        ForEach(observers.filter { $0.storeObserver == nil }) { observer in
                            Button(observer.name.isEmpty ? "Unnamed Observer" : observer.name) {
                                Task {
                                    do {
                                        try await viewModel.registerStoreObserver(observer)
                                    } catch {
                                        appState.setError(error)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            #endif
            .navigationTitle("Observer Events")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

