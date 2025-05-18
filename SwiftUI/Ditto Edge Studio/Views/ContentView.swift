//
//  ContentView.swift
//  Ditto Edge Studio
//
//  Created by Aaron LaBeau on 5/18/25.
//
import SwiftUI
import Combine

struct ContentView: View {
    @EnvironmentObject private var appState: DittoApp
    @State private var viewModel: ContentView.ViewModel = ViewModel()
    
    // Define columns: 2 for iPad, 1 for iPhone
    var columns: [GridItem] {
#if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .pad {
            return Array(
                repeating: .init(.flexible(), spacing: 16),
                count: 2
            )
        }
#endif
        return [GridItem(.flexible())]
    }
    
    var body: some View {
        Group {
            if viewModel.isMainStudioViewPresented, let selectedApp = viewModel.selectedDittoAppConfig {
                MainStudioView(
                    isMainStudioViewPresented: Binding(
                        get: { viewModel.isMainStudioViewPresented },
                        set: { viewModel.isMainStudioViewPresented = $0 }
                    ),
                    dittoAppConfig: selectedApp
                )
                .environmentObject(appState)
            } else {
                NavigationStack {
                    Group {
                        if viewModel.isLoading {
                            AnyView(ProgressView("Loading Apps...")
                                .progressViewStyle(.circular))
                        } else if viewModel.dittoApps.isEmpty {
                            AnyView(
                                ContentUnavailableView(
                                    "No Apps",
                                    systemImage: "exclamationmark.triangle.fill",
                                    description: Text(
                                        "No apps have been added yet. Click the plus button above to add your first app.")
                                )
                            )
                        } else {
#if os(iOS)
                            AnyView(List {
                                Section(header: Spacer().frame(height: 24).listRowInsets(EdgeInsets())) {
                                    ForEach(viewModel.dittoApps, id: \._id) { dittoApp in
                                        DittoAppCard(dittoApp: dittoApp) {}
                                            .contentShape(Rectangle())
                                            .onTapGesture {
                                                viewModel.showMainStudio(dittoApp)
                                            }
                                            .swipeActions(edge: .trailing) {
                                                Button(role: .cancel) {
                                                    viewModel.showAppEditor(dittoApp)
                                                } label: {
                                                    Label("Edit", systemImage: "pencil")
                                                }
                                            }
                                    }
                                }
                            }
                                .padding(.top, 16))
#else
                            AnyView(List {
                                ForEach(viewModel.dittoApps, id: \._id) { dittoApp in
                                    DittoAppCard(dittoApp: dittoApp) {}
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            viewModel.showMainStudio(dittoApp)
                                        }
                                        .contextMenu {
                                            Button("Edit") {
                                                viewModel.showAppEditor(dittoApp)
                                            }
                                        }
                                }
                            })
#endif
                        }
                    }
                    .navigationTitle(Text("Ditto Apps"))
                    .toolbar {
#if os(iOS)
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                viewModel.showAppEditor(DittoAppConfig.new())
                            } label: {
                                Image(systemName: "plus")
                            }
                        }
#else
                        ToolbarItem(placement: .automatic) {
                            Button {
                                viewModel.showAppEditor(DittoAppConfig.new())
                            } label: {
                                Image(systemName: "plus")
                            }
                        }
#endif
                    }
                    .sheet(isPresented: Binding(
                        get: { viewModel.isPresented },
                        set: { viewModel.isPresented = $0 }
                    )) {
                        AppEditorView(
                            isPresented: Binding(
                                get: { viewModel.isPresented },
                                set: { viewModel.isPresented = $0 }
                            ),
                            dittoAppConfig: viewModel.dittoAppToEdit!
                        )
                        .environmentObject(appState)
                    }
                }
            }
        }
        .task(id: ObjectIdentifier(appState)) {
            //load the apps from the database
            await viewModel.loadApps(appState: appState)
        }
    }
}

extension ContentView {
    @Observable
    @MainActor
    class ViewModel {
        @ObservationIgnored private var cancellables = Set<AnyCancellable>()
        
        var dittoApps: [DittoAppConfig] = []
        var isLoading = false
        
        //used for editor
        var isPresented = false
        var dittoAppToEdit: DittoAppConfig?
        
        //used for MainStudioView
        var isMainStudioViewPresented = false
        var selectedDittoAppConfig: DittoAppConfig?
        
        init() {
            // Observe changes to DittoService's planets
            Task { @MainActor in
                DittoManager.shared.$dittoAppConfigs
                    .receive(on: RunLoop.main)
                    .sink { [weak self] updatedApps in
                        self?.dittoApps = updatedApps
                    }
                    .store(in: &cancellables)
            }
        }
        
        func loadApps(appState: DittoApp) async {
            isLoading = true
            do {
                try await DittoManager.shared.initializeStore(
                    dittoApp: appState
                )
                dittoApps = DittoManager.shared.dittoAppConfigs
            } catch {
                appState.setError(error)
            }
            isLoading = false
        }
        
        func showAppEditor(_ dittoApp: DittoAppConfig) {
            dittoAppToEdit = dittoApp
            isPresented = true
        }
        
        func showMainStudio(_ dittoApp: DittoAppConfig) {
            selectedDittoAppConfig = dittoApp
            isMainStudioViewPresented = true
        }
    }
}

#Preview {
    ContentView()
        .environment(DittoAppConfig.new())
}
