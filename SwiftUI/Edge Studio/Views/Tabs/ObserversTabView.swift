//
//  ObservablesTab.swift
//  Edge Studio
//
//  Created by Aaron LaBeau on 6/2/25.
//

import SwiftUI

struct ObserversTabView: View {
    @EnvironmentObject private var appState: DittoApp
    @Binding var isMainStudioViewPresented: Bool
    @State private var viewModel: ObserversTabView.ViewModel
    @State private var splitPosition: CGFloat = 300  // initial height

    init(
        isMainStudioViewPresented: Binding<Bool>,
        dittoAppConfig: DittoAppConfig
    ) {
        self._isMainStudioViewPresented = isMainStudioViewPresented
        self._viewModel = State(initialValue: ViewModel(dittoAppConfig))
    }

    var body: some View {
        NavigationSplitView {
            sidebar()
        } detail: {
            #if os(macOS)
                VSplitView {
                    if viewModel.selectedObservable == nil {
                        observableDetailNoContent()
                            .frame(minHeight: 200)

                    } else {
                        observableEventsList()
                            .frame(minHeight: 200)
                    }
                    observableDetailSelectedEvent(observeEvent: viewModel.selectedEvent)
                }
            #else
                VStack {
                    if viewModel.selectedObservable == nil {
                        observableDetailNoContent()
                    } else {
                        observableEventsList()
                    }
                    observableDetailSelectedEvent(observeEvent: viewModel.selectedEvent)
                }
            #endif

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
                if let observable = viewModel.newObserverable {
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

    fileprivate func sidebar() -> some View {
        return VStack {
            List {
                observerableList()
            }
            Spacer()
            Button {
                viewModel.editObservable(DittoObservable.new())
            } label: {
                Label("Observers", systemImage: "plus.square.fill")
            }.padding(.bottom, 20)

        }
        .navigationTitle("Observers")
        #if os(macOS)
            .frame(minWidth: 200, idealWidth: 250, maxWidth: 250)
        #endif
    }

    fileprivate func observableDetailNoSelection() -> some View {
        return VStack {
            ContentUnavailableView(
                "No Observer Selected",
                systemImage: "exclamationmark.triangle.fill",
                description: Text(
                    "No Observer event to view.  Select an existing observer and then an event or click the plus button in the upper right corner to add your first observer and then select it."
                )
            )
            .navigationTitle("Observer Events")
        }
    }

    fileprivate func observableDetailSelectedEvent(observeEvent: DittoObserveEvent?)
        -> some View
    {
        return VStack(alignment: .leading, spacing: 0) {
            if let event = observeEvent {
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
            
            } else {
                ResultJsonViewer(resultText: [])
            }
        }
        .padding(.leading, 12)
    }

    fileprivate func observableDetailNoContent() -> some View {
        return VStack {
            ContentUnavailableView(
                "No Obvserver Selected",
                systemImage: "exclamationmark.triangle.fill",
                description: Text(
                    "Please select an observer from the siderbar to view events."
                )
            )
        }
    }

    fileprivate func observableEventsList() -> some View {
        return List(viewModel.observableEvents, id: \.id) { event in
            if !(event.eventTime.isEmpty || event.eventTime == "") {
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
                }.onTapGesture {
                    viewModel.selectedEvent = event
                }
            }
        }
        .navigationTitle("Observer Events")
    }

    fileprivate func observerableList() -> some View {
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
                                Button("Edit") {
                                    Task {
                                        viewModel.editObservable(observer)
                                    }
                                }
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

extension ObserversTabView {
    @Observable
    @MainActor
    class ViewModel {
        let selectedApp: DittoAppConfig
        var isLoading = false

        //used for editor
        var isEditorPresented = false

        // Observables State
        var observerables: [DittoObservable] = []
        var selectedObservable: DittoObservable?
        var newObserverable: DittoObservable?

        var observableEvents: [DittoObserveEvent] = []
        var selectedEvent: DittoObserveEvent?
        var eventMode = "items"

        init(_ dittoAppConfig: DittoAppConfig) {
            self.selectedApp = dittoAppConfig

            Task {
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

        func editObservable(_ observable: DittoObservable) {
            newObserverable = observable
            isEditorPresented = true
        }

        func deleteObservable(_ observable: DittoObservable) async throws {
            try await DittoManager.shared.removeDittoObservable(observable)
            observerables = await DittoManager.shared.dittoObservables
        }

        func formCancel() {
            newObserverable = nil
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
            newObserverable = nil
            isEditorPresented = false
        }

        func loadObservedEvents() async {
            observableEvents = []
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

    }
}

#Preview {
    ObserversTabView(
        isMainStudioViewPresented: .constant(true),
        dittoAppConfig: DittoAppConfig.new()
    )
    .environmentObject(DittoApp())
}
