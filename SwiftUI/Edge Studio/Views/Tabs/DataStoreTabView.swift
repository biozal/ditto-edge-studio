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
            List {
                subscriptionSection()
                Spacer()
                observableSection()
                Spacer()
                Section {
                    Button {
                        Task {
                            // Your import task logic here
                        }
                    } label: {
                        HStack {
                            Image(systemName: "square.and.arrow.up.fill")
                            Text("Import")
                            Spacer()
                        }
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                }
                .listRowInsets(EdgeInsets())
            }
            .navigationTitle("Data Store")
            .frame(minWidth: 200, idealWidth: 320, maxWidth: 400)
        } content: {
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
                    .frame(minWidth: 200, idealWidth: 320, maxWidth: 400)

                } else {
                    ContentUnavailableView(
                        "No Observer Events",
                        systemImage: "exclamationmark.triangle.fill",
                        description: Text(
                            "No Observer events.  Update some data in the collection your observer."
                        )
                    )
                    .navigationTitle("Observer Events")
                    .frame(minWidth: 200, idealWidth: 320, maxWidth: 400)
                }
            }
        } detail: {
            ContentUnavailableView(
                "No Observer Selected",
                systemImage: "exclamationmark.triangle.fill",
                description: Text(
                    "No Observer event to view.  Select an existing observer and then an event or click the plus button in the upper right corner to add your first observer and then select it."
                )
            )
            .navigationTitle("Observer Events")
        }
#if os(iOS)
        .navigationSplitViewColumnWidth(400)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(viewModel.selectedApp.name).font(.headline).bold()
            }
        }
#else
        .navigationSplitViewColumnWidth(min: 500, ideal: 800, max: 2000)
#endif
        .sheet(
            isPresented: $viewModel.isEditorPresented,
        ) {
            Group {
                if let subscription = viewModel.selectedSubscription {
                    QueryArgumentEditor(
                        title: subscription.name.isEmpty ? "New Subscription" : "Edit Subscription",
                        name: subscription.name,
                        query: subscription.query,
                        arguments: subscription.args ?? "",
                        onSave: viewModel.formSaveSubscription,
                        onCancel: viewModel.formCancel
                    )
                    .environmentObject(appState)
                } else if let observable = viewModel.selectedObservable {
                    QueryArgumentEditor(
                        title: observable.name.isEmpty ? "New Observer" : "Edit Observer",
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
        }//end of sheet
     
    }
    
    fileprivate func subscriptionSection() -> some View {
        return Section {
            if viewModel.subscriptions.isEmpty {
                VStack {
                    Text("No subscriptions have been added yet. Click the plus button to add your first subscription.")
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
                        .contextMenu{
                            Button {
                                Task {
                                    try await viewModel.deleteSubscription(subscription)
                                }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
        }
        header: {
            HStack {
                Button {
                    viewModel.showSubscriptionEditor(DittoSubscription.new())
                } label: {
                    Image(systemName: "plus.square.fill")
                        .imageScale(.large)
                }
                .buttonStyle(.borderless)
                
                Text("Subscriptions")
                    .font(.title2)
                    .foregroundColor(.primary)
                
                Spacer()
            }
            .padding(.top, 4)
        }
    }
    
    fileprivate func observableSection() -> some View {
        return Section {
            if viewModel.observerables.isEmpty {
                VStack {
                    Text("No observers have been added yet. Click the plus button to add your first observers.")
                        .font(.caption)
                        .lineLimit(nil)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            } else {
                ForEach(viewModel.observerables, id: \.id) { observer in
                    HStack {
                        Text(observer.name)
                            .onTapGesture {
                                viewModel.selectedObservable = observer
                            }
#if os(macOS)
                            .contextMenu {
                                Button("Activate") {
                                    
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
                        Spacer()
                        if observer.isActive {
                            Pill(text: "Active", color: .green)
                        } else {
                            Pill(text: "Inactive", color: .gray)
                        }
                    }
                }
            }
        } header: {
            HStack {
                Button {
                    viewModel.showObserverEditor(DittoObservable.new())
                } label: {
                    Image(systemName: "plus.square.fill")
                        .imageScale(.large)
                }
                .buttonStyle(.borderless)
                
                Text("Observers")
                    .font(.title2)
                    .foregroundColor(.primary)
                
                Spacer()
            }
            .padding(.top, 4)
        }
    }//end of ObservableSection
}

extension DataStoreTabView {
    @Observable
    @MainActor
    class ViewModel {
        let selectedApp: DittoAppConfig
        var isLoading = false

        //used for editor
        var isEditorPresented = false

        // Subscriptions State
        var subscriptions: [DittoSubscription] = []
        var selectedSubscription: DittoSubscription?

        // Observables State
        var observerables: [DittoObservable] = []
        var selectedObservable: DittoObservable?

        init(_ dittoAppConfig: DittoAppConfig) {
            self.selectedApp = dittoAppConfig

            Task {
                subscriptions = await DittoManager.shared.dittoSubscriptions
                observerables = await DittoManager.shared.dittoObservables
            }
        }

        func activateObservable(_ observable: DittoObservable) async throws {

        }

        func closeSelectedApp() async {
            //close observations
            selectedObservable = nil
            await DittoManager.shared.closeDittoSelectedApp()
        }
        
        func deleteSubscription(_ subscription: DittoSubscription) async throws {
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

        func loadObservations(_ observable: DittoObservable) async {
            //set the selected observable
            self.selectedObservable = observable
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
