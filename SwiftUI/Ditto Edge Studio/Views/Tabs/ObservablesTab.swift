//
//  ObservablesTab.swift
//  Ditto Edge Studio
//
//  Created by Aaron LaBeau on 6/2/25.
//

import SwiftUI

struct ObservablesTab: View {
    @EnvironmentObject private var appState: DittoApp
    @Binding var isMainStudioViewPresented: Bool
    @State private var viewModel: ObservablesTab.ViewModel

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
                                .font(.headline)
                                .foregroundColor(.primary)
                                .padding(.bottom, 5)
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
            ContentUnavailableView(
                "No Observer Selected",
                systemImage: "exclamationmark.triangle.fill",
                description: Text(
                    "No Observer selected.  Select an existing observer or click the plus button in the upper right corner to add your first observer and then select it."
                )
            )
            .navigationTitle("Observer Events")
            
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
        .toolbar {
            #if os(iPadOS)
                ToolbarItem(placement: .principal) {
                    Text(viewModel.selectedApp.name).font(.headline).bold()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        //viewModel.selectedSubscription = DittoSubscription.new()
                    } label: {
                        Image(systemName: "plus")
                    }
            }
            #endif
            #if os(macOS)
                ToolbarItem(placement: .automatic) {
                    Button {
                        Task {
                            await viewModel.closeSelectedApp()
                            isMainStudioViewPresented = false
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        //viewModel.selectedSubscription = DittoSubscription.new()
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            #endif
        }
    }
}

extension ObservablesTab {
    @Observable
    @MainActor
    class ViewModel {
        let selectedApp: DittoAppConfig
        var isLoading = false
        
        // Observables State
        var observerables: [DittoObservable] = []
        var selectedObservable: DittoObservable?
        
        init(_ dittoAppConfig: DittoAppConfig) {
            self.selectedApp = dittoAppConfig
        }
        
        func closeSelectedApp() async {
            //close observations
            selectedObservable = nil
            await DittoManager.shared.closeDittoSelectedApp()
        }
    }
}


#Preview {
    ObservablesTab(
        isMainStudioViewPresented: .constant(true),
        dittoAppConfig: DittoAppConfig.new()
    )
    .environmentObject(DittoApp())
}
