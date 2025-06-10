//
//  ObservablesTab.swift
//  Edge Studio
//
//  Created by Aaron LaBeau on 6/2/25.
//

import SwiftUI

struct DataStoreTabView: View {
    @EnvironmentObject private var appState: DittoApp
    @Binding var isMainStudioViewPresented: Bool
    @State private var viewModel: DataStoreTabView.ViewModel

    init(
        isMainStudioViewPresented: Binding<Bool>,
        dittoAppConfig: DittoAppConfig
    ) {
        self._isMainStudioViewPresented = isMainStudioViewPresented
        self._viewModel = State(initialValue: ViewModel(dittoAppConfig))
    }

    var body: some View {
        NavigationSplitView {
            VStack {
                Picker("", selection: $viewModel.mode) {
                    Label(
                        "Subscriptions",
                        systemImage: "arrow.trianglehead.2.clockwise"
                    )
                    .labelStyle(.iconOnly)
                    .tag("subscriptions")
                    Label(
                        "Observers",
                        systemImage: "eye"
                    )
                    .labelStyle(.iconOnly)
                    .tag("observers")
                }
                .padding(.top, 8)
                .padding(.bottom, 8)
                .pickerStyle(.segmented)
                .frame(width: 200)

                if viewModel.mode == "observers" {
                    Button {
                        viewModel.showObserverEditor(
                            DittoObservable.new()
                        )
                    } label: {
                        Label("Observers", systemImage: "plus.square.fill")
                    }
                    List {
                        observableSection()
                    }

                } else {
                    Button {
                        viewModel.showSubscriptionEditor(
                            DittoSubscription.new()
                        )
                    } label: {
                        Label("Subscriptions", systemImage: "plus.square.fill")
                    }
                    .padding(.bottom, 4)
                    List {
                        subscriptionSection()
                    }
                }
                Spacer()
                Button {
                    Task {
                        // Your import task logic here
                    }
                } label: {
                    Label("Import", systemImage: "square.and.arrow.up.fill")
                }
                .padding(.bottom, 8)
            }
            .navigationTitle("Data Store")
            #if os(macOS)
                .frame(minWidth: 200, idealWidth: 250, maxWidth: 250)
            #endif
        } content: {
            if viewModel.mode == "subscriptions" {
                VStack {
                    ContentUnavailableView(
                        "Information List",
                        systemImage: "exclamationmark.triangle.fill",
                        description: Text(
                            "This is supposed to display a list of topics for you to learn about within the app, but the developer hasn't gotten around to implementing it yet"
                        )
                    )
                }
                .frame(minWidth: 200, idealWidth: 250, maxWidth: 250)
            } else {
                //draw observable UI
                VStack {
                    if viewModel.selectedObservable == nil {
                        ContentUnavailableView(
                            "No Observer Selected",
                            systemImage: "exclamationmark.triangle.fill",
                            description: Text(
                                "No Observer selected.  Select an existing observer or click the plus button in the upper right corner to add your first observer and then select it."
                            )
                        )
                        .navigationTitle("Observer Events")
                        .frame(minWidth: 200, idealWidth: 250, maxWidth: 250)

                    } else {
                        if viewModel.observableEvents.isEmpty {
                            ContentUnavailableView(
                                "No Observer Events",
                                systemImage: "exclamationmark.triangle.fill",
                                description: Text(
                                    "No Observer events.  Update some data in the collection your observer."
                                )
                            )
                            .navigationTitle("Observer Events")
                            .frame(minWidth: 200, idealWidth: 250, maxWidth: 250)
                        } else {
                            observableEventsList()
                                .frame(minWidth: 200, idealWidth: 250, maxWidth: 250)
                        }
                    }
                }
            }
        } detail: {
            if viewModel.mode == "subscriptions" {
                ContentUnavailableView(
                    "Developer Lazy",
                    systemImage: "exclamationmark.triangle.fill",
                    description: Text(
                        "I'm a lazy developer this should show you information about the app and how to get started."
                    )
                )
            } else {
                if viewModel.selectedEvent == nil {
                    ContentUnavailableView(
                        "No Observer Selected",
                        systemImage: "exclamationmark.triangle.fill",
                        description: Text(
                            "No Observer event to view.  Select an existing observer and then an event or click the plus button in the upper right corner to add your first observer and then select it."
                        )
                    )
                    .navigationTitle("Observer Events")
                } else {
                    if viewModel.shouldShowEventDetails(),
                        let event = viewModel.selectedEvent
                    {
                        VStack(alignment: .leading, spacing: 0) {
                            Picker("", selection: $viewModel.eventMode) {
                                Text("Items")
                                    .tag("items")
                                Text("Inserted")
                                    .tag("inserted")
                                Text("Updated")
                                    .tag("updated")
                            }
                            #if os(macOS)
                                .padding(.top, 24)
                            #else
                                .padding(.top, 8)
                            #endif
                            .padding(.bottom, 8)
                            .pickerStyle(.segmented)
                            .frame(width: 200)
                            switch viewModel.eventMode {
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
                        }.padding(.leading, 12)
                    } else {
                        ContentUnavailableView(
                            "No Event Data",
                            systemImage: "exclamationmark.triangle.fill",
                            description: Text(
                                "Event had no counters for inserts, updates, deletes, or items. This should never technically speaking happen."
                            )
                        )

                    }

                }
            }
        }
        #if os(iOS)
            .navigationSplitViewColumnWidth(400)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(viewModel.selectedApp.name).font(.headline).bold()
                }
            }
        #endif
        .sheet(
            isPresented: $viewModel.isEditorPresented,
        ) {
            Group {
                if let subscription = viewModel.selectedSubscription {
                    QueryArgumentEditor(
                        title: subscription.name.isEmpty
                            ? "New Subscription" : "Edit Subscription",
                        name: subscription.name,
                        query: subscription.query,
                        arguments: subscription.args ?? "",
                        onSave: viewModel.formSaveSubscription,
                        onCancel: viewModel.formCancel
                    )
                    .environmentObject(appState)
                } else if let observable = viewModel.selectedObservable {
                    QueryArgumentEditor(
                        title: observable.name.isEmpty
                            ? "New Observer" : "Edit Observer",
                        name: observable.name,
                        query: observable.query,
                        arguments: observable.args ?? "",
                        onSave: viewModel.formSaveObservable,
                        onCancel: viewModel.formCancel
                    )
                    .environmentObject(appState)
                }
            }
            #if os(macOS)
                .frame(
                    minWidth: 860,
                    idealWidth: 1000,
                    maxWidth: 1080,
                    minHeight: 400,
                    idealHeight: 600
                )
            #elseif os(iOS)
                .frame(
                    minWidth: UIDevice.current.userInterfaceIdiom == .pad
                        ? 600 : nil,
                    idealWidth: UIDevice.current.userInterfaceIdiom == .pad
                        ? 1000 : nil,
                    maxWidth: UIDevice.current.userInterfaceIdiom == .pad
                        ? 1080 : nil,
                    minHeight: UIDevice.current.userInterfaceIdiom == .pad
                        ? 400 : nil,
                    idealHeight: UIDevice.current.userInterfaceIdiom == .pad
                        ? 500 : nil,
                    maxHeight: UIDevice.current.userInterfaceIdiom == .pad
                        ? 600 : nil
                )
            #endif
            .presentationDetents([.medium, .large])
        }  //end of sheet

    }

    fileprivate func observableEventsList() -> some View {
        return List(viewModel.observableEvents, id: \.id) { event in
            VStack(alignment: .leading) {
                Text("\(event.eventTime)")
                    .font(.headline)
                Text("Items Count: \(event.data.count)")
                    .padding(.bottom, 6)

                Text("Insert Count: \(event.insertIndexes.count)")
                Text("Update Count: \(event.updatedIndexes.count)")
                Text("Delete Count: \(event.deletedIndexes.count)")
                Text("Moves Count: \(event.movedIndexes.count)")
                    .padding(.bottom, 6)
                Divider()
            }.onTapGesture {
                viewModel.selectedEvent = event
            }

        }
        .navigationTitle("Observer Events")
    }

    fileprivate func subscriptionSection() -> some View {
        return Section {
            if viewModel.subscriptions.isEmpty {
                VStack {
                    Text(
                        "No subscriptions have been added yet. Click the plus button to add your first subscription."
                    )
                    .font(.caption)
                    .lineLimit(nil)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            } else {
                ForEach(viewModel.subscriptions, id: \.id) {
                    subscription in
                    Text(subscription.name)
                        .onTapGesture {
                            viewModel.showSubscriptionEditor(subscription)
                        }
                        .contextMenu {
                            Button {
                                Task {
                                    try await viewModel.deleteSubscription(
                                        subscription
                                    )
                                }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }

                    Divider()
                }
            }
        }
    }

    fileprivate func observableSection() -> some View {
        return Section {
            if viewModel.observerables.isEmpty {
                VStack {
                    Text(
                        "No observers have been added yet. Click the plus button to add your first observers."
                    )
                    .font(.caption)
                    .lineLimit(nil)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            } else {
                ForEach(viewModel.observerables, id: \.id) { observer in
                    Text(observer.name)
                        .onTapGesture {
                            viewModel.selectedObservable = observer
                            Task {
                                await viewModel.loadObservedEvents()
                            }
                        }
                        #if os(macOS)
                            .contextMenu {
                                Button("Delete") {
                                    Task {
                                        do {
                                            try await viewModel
                                            .deleteObservable(
                                                observer
                                            )
                                        } catch {
                                            appState.setError(error)
                                        }
                                    }
                                }
                            }
                        #endif
                    Divider()
                }
            }
        }
    }  //end of ObservableSection
}

extension DataStoreTabView {
    @Observable
    @MainActor
    class ViewModel {
        let selectedApp: DittoAppConfig
        var isLoading = false

        //used for navigation
        var mode = "subscriptions"

        //used for editor
        var isEditorPresented = false

        // Subscriptions State
        var subscriptions: [DittoSubscription] = []
        var selectedSubscription: DittoSubscription?

        // Observables State
        var observerables: [DittoObservable] = []
        var selectedObservable: DittoObservable?

        var observableEvents: [DittoObserveEvent] = []
        var selectedEvent: DittoObserveEvent?
        var eventMode = "items"

        init(_ dittoAppConfig: DittoAppConfig) {
            self.selectedApp = dittoAppConfig

            Task {
                subscriptions = await DittoManager.shared.dittoSubscriptions
                observerables = await DittoManager.shared.dittoObservables
            }
            selectedEvent = nil
        }

        func activateObservable(_ observable: DittoObservable) async throws {

        }

        func closeSelectedApp() async {
            //close observations
            selectedObservable = nil
            await DittoManager.shared.closeDittoSelectedApp()
        }

        func deleteSubscription(_ subscription: DittoSubscription) async throws
        {
            try await DittoManager.shared.removeDittoSubscription(subscription)
            subscriptions = await DittoManager.shared.dittoSubscriptions
        }

        func deleteObservable(_ observable: DittoObservable) async throws {
            try await DittoManager.shared.removeDittoObservable(observable)
            observerables = await DittoManager.shared.dittoObservables
        }

        func formCancel() {
            selectedObservable = nil
            selectedSubscription = nil
            isEditorPresented = false
        }

        func formSaveObservable(
            name: String,
            query: String,
            args: String?,
            appState: DittoApp
        ) {
            if var observerable = selectedObservable {
                observerable.name = name
                observerable.query = query
                observerable.args = args ?? ""
                Task {
                    do {
                        try await DittoManager.shared.saveDittoObservable(
                            observerable
                        )
                        observerables = await DittoManager.shared
                            .dittoObservables
                    } catch {
                        appState.setError(error)
                    }
                }
            }
            selectedObservable = nil
            isEditorPresented = false
        }

        func formSaveSubscription(
            name: String,
            query: String,
            args: String?,
            appState: DittoApp
        ) {
            if var subscription = selectedSubscription {
                subscription.name = name
                subscription.query = query
                if let argsString = args {
                    subscription.args = argsString
                } else {
                    subscription.args = nil
                }
                Task {
                    do {
                        try await DittoManager.shared.saveDittoSubscription(
                            subscription
                        )
                        subscriptions = await DittoManager.shared
                            .dittoSubscriptions
                    } catch {
                        appState.setError(error)
                    }
                    selectedSubscription = nil
                }
            }
            isEditorPresented = false
        }

        func loadObservedEvents() async {
            observableEvents = await DittoManager.shared.dittoObservableEvents
        }

        func loadObservations(_ observable: DittoObservable) async {
            //set the selected observable
            self.selectedObservable = observable
        }

        func shouldShowEventDetails() -> Bool {
            if let event = selectedEvent {
                return event.data.count > 0
                || event.insertIndexes.count > 0
                || event.updatedIndexes.count > 0
                || event.deletedIndexes.count > 0
            }
            return false
        }

        func showObserverEditor(_ observable: DittoObservable) {
            selectedObservable = observable
            isEditorPresented = true
        }

        func showSubscriptionEditor(_ subscription: DittoSubscription) {
            selectedSubscription = subscription
            isEditorPresented = true
        }
    }
}

#Preview {
    DataStoreTabView(
        isMainStudioViewPresented: .constant(true),
        dittoAppConfig: DittoAppConfig.new()
    )
    .environmentObject(DittoApp())
}
