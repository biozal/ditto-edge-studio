//
//  ObservablesTab.swift
//  Ditto Edge Studio
//
//  Created by Aaron LaBeau on 6/2/25.
//

import SwiftUI

struct ObservablesTabView: View {
    @EnvironmentObject private var appState: DittoApp
    @Binding var isMainStudioViewPresented: Bool
    @State private var viewModel: ObservablesTabView.ViewModel

    init(
        isMainStudioViewPresented: Binding<Bool>,
        dittoAppConfig: DittoAppConfig
    ) {
        self._isMainStudioViewPresented = isMainStudioViewPresented
        self._viewModel = State(initialValue: ViewModel(dittoAppConfig))
    }
    
    var body: some View {
        NavigationSplitView {
            if viewModel.observerables.isEmpty {
                ContentUnavailableView(
                    "No Observers",
                    systemImage: "exclamationmark.triangle.fill",
                    description: Text(
                        "No observers have been added yet. Click the plus button in the upper right corner to add your first observers."
                    )
                )
                .navigationTitle("Observers")
            } else {
                List {
                    #if os(macOS)
                        Section(
                            header:
                                Text("Observers")
                                .font(.title)
                                .foregroundColor(.primary)
                                .padding(.bottom, 5)
                                .padding(.top, 20)
                        ) {
                            ForEach(viewModel.observerables, id: \.id) {
                                observer in
                                Text(observer.name)
                                    .onTapGesture {
                                        viewModel.selectedObservable =
                                            observer
                                    }
                            }
                        }
                    #else
                        ForEach(viewModel.observerables, id: \.id) {
                            observer in
                            Text(observer.name)
                                .onTapGesture {
                                    viewModel.selectedObservable =
                                        observer
                                }
                        }
                    #endif

                }
                .navigationTitle("Observers")
            }
        } content: {
            VStack {
                ContentUnavailableView(
                    "No Observer Selected",
                    systemImage: "exclamationmark.triangle.fill",
                    description: Text(
                        "No Observer selected.  Select an existing observer or click the plus button in the upper right corner to add your first observer and then select it."
                    )
                )
                .navigationTitle("Observer Events")
            }
        }
        detail: {
            ContentUnavailableView(
                "No Observer Selected",
                systemImage: "exclamationmark.triangle.fill",
                description: Text(
                    "No Observer event to view.  Select an existing observer and then an event or click the plus button in the upper right corner to add your first observer and then select it."
                )
            )
            .navigationTitle("Observer Events")
        }
        .sheet(
           isPresented: $viewModel.isEditorPresented,
        ){
            ObserverEditorView(
                isPresented: $viewModel.isEditorPresented,
                selectedObservable: viewModel.selectedObservable ?? DittoObservable.new()
            )
            #if os(macOS)
            .frame(minWidth: 860,
                   idealWidth: 1000,
                   maxWidth: 1080,
                   minHeight: 500,
                   idealHeight: 800)
            #elseif os(iOS)
            .frame(
                minWidth: UIDevice.current.userInterfaceIdiom == .pad ? 600 : nil,
                idealWidth: UIDevice.current.userInterfaceIdiom == .pad ? 1000 : nil,
                maxWidth: UIDevice.current.userInterfaceIdiom == .pad ? 1080 : nil,
                minHeight: UIDevice.current.userInterfaceIdiom == .pad ? 500 : nil,
                idealHeight: UIDevice.current.userInterfaceIdiom == .pad ? 700 : nil,
                maxHeight: UIDevice.current.userInterfaceIdiom == .pad ? 800 : nil
            )
            #endif
            .environmentObject(appState)
            .presentationDetents([.medium, .large])
        }
        .toolbar {
            #if os(iPadOS)
                ToolbarItem(placement: .principal) {
                    Text(viewModel.selectedApp.name).font(.headline).bold()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.showObserverEditor(DittoObservable.new())
                    } label: {
                        Image(systemName: "plus")
                    }
            }
            #endif
            
            #if os(macOS)
            ToolbarItem(id: "add", placement: .primaryAction) {
                Button {
                    viewModel.showObserverEditor(DittoObservable.new())
                } label: {
                    Image(systemName: "plus")
                }
            }
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    Task {
                        await viewModel.closeSelectedApp()
                        isMainStudioViewPresented = false
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
            }
            #endif
        }
    }
}

extension ObservablesTabView {
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
        
        init(_ dittoAppConfig: DittoAppConfig) {
            self.selectedApp = dittoAppConfig
        }
        
        func showObserverEditor(_ observable: DittoObservable) {
            selectedObservable = observable
            isEditorPresented = true
        }
        
        func closeSelectedApp() async {
            //close observations
            selectedObservable = nil
            await DittoManager.shared.closeDittoSelectedApp()
        }
    }
}


#Preview {
    ObservablesTabView(
        isMainStudioViewPresented: .constant(true),
        dittoAppConfig: DittoAppConfig.new()
    )
    .environmentObject(DittoApp())
}
