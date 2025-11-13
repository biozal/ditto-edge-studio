import Combine
//
//  ContentView.swift
//  Ditto Edge Studio
//
//  Created by Aaron LaBeau on 5/18/25.
//
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
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
            if viewModel.isMainStudioViewPresented,
                let selectedApp = viewModel.selectedDittoAppConfig
            {
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
                            AnyView(
                                ProgressView("Loading Database Configs...")
                                    .progressViewStyle(.circular)
                            )
                        } else if viewModel.dittoApps.isEmpty {
                            AnyView(
                                ContentUnavailableView(
                                    "No Database Configurations",
                                    systemImage:
                                        "exclamationmark.triangle.fill",
                                    description: Text(
                                        "No databases have been added yet. Click the plus button above to add your first app."
                                    )
                                )
                            )
                        } else {
                            DatabaseList(
                                viewModel: viewModel,
                                appState: appState
                            )
                        }
                    }
                    .navigationTitle(Text("Ditto Apps"))
                    .toolbar {
                        #if os(iOS)
                            ToolbarItem(placement: .topBarTrailing) {
                                Button {
                                    viewModel.showAppEditor(
                                        DittoAppConfig.new()
                                    )
                                } label: {
                                    Image(systemName: "plus")
                                }
                            }
                        #else
                            ToolbarItem(placement: .automatic) {
                                Button {
                                    viewModel.showAppEditor(
                                        DittoAppConfig.new()
                                    )
                                } label: {
                                    Image(systemName: "plus")
                                }
                            }
                        #endif
                    }
                    .sheet(
                        isPresented: Binding(
                            get: { viewModel.isPresented },
                            set: { viewModel.isPresented = $0 }
                        )
                    ) {
                        AppEditorView(
                            isPresented: Binding(
                                get: { viewModel.isPresented },
                                set: { viewModel.isPresented = $0 }
                            ),
                            dittoAppConfig: viewModel.dittoAppToEdit!
                        )
                        #if os(macOS)
                            .frame(
                                minWidth: 600,
                                idealWidth: 1000,
                                maxWidth: 1080
                            )
                        #elseif os(iOS)
                            .frame(
                                minWidth: UIDevice.current.userInterfaceIdiom
                                    == .pad ? 600 : nil,
                                idealWidth: UIDevice.current.userInterfaceIdiom
                                    == .pad ? 1000 : nil,
                                maxWidth: UIDevice.current.userInterfaceIdiom
                                    == .pad ? 1080 : nil,
                                minHeight: UIDevice.current.userInterfaceIdiom
                                    == .pad ? 800 : nil,
                                idealHeight: UIDevice.current.userInterfaceIdiom
                                    == .pad ? 800 : nil,
                                maxHeight: UIDevice.current.userInterfaceIdiom
                                    == .pad ? 1000 : nil
                            )
                        #endif
                        .environmentObject(appState)
                        .presentationDetents([.medium, .large])
                    }
                }
            }
        }
        .onAppear {
            Task {
                await viewModel.loadApps(appState: appState)
            }
        }
    }
}

extension ContentView {
    @Observable
    @MainActor
    class ViewModel {
        @ObservationIgnored private var cancellables = Set<AnyCancellable>()
        private let databaseRepository = DatabaseRepository.shared

        var dittoApps: [DittoAppConfig] = []
        var isLoading = false
        var isMainStudioLoaded = false

        //used for editor
        var isPresented = false
        var dittoAppToEdit: DittoAppConfig?

        //used for MainStudioView
        var isMainStudioViewPresented = false
        var selectedDittoAppConfig: DittoAppConfig?

        init() {
            // Repository callback will be set up when loadApps is called
        }

        func deleteApp(_ dittoApp: DittoAppConfig, appState: AppState) async {
            do {
                // Now requires await since DatabaseRepository is an actor
                try await databaseRepository.deleteDittoAppConfig(dittoApp)
            } catch {
                appState.setError(error)
            }
        }

        func loadApps(appState: AppState) async {
            isLoading = true
            do {
                // Initialize DittoManager first
                try await DittoManager.shared.initializeStore(
                    appState: appState
                )
                
                //setup the local database subscription for registered apps
                await databaseRepository.setAppState(appState)
                try await databaseRepository.setupDatabaseConfigSubscriptions()
                
                // Set appState in SystemRepository as well
                await SystemRepository.shared.setAppState(appState)
                
                // Set appState in ObservableRepository as well
                await ObservableRepository.shared.setAppState(appState)
                
                // Set appState in FavoritesRepository as well
                await FavoritesRepository.shared.setAppState(appState)
                
                // Set appState in HistoryRepository as well
                await HistoryRepository.shared.setAppState(appState)

                // Set appState in EdgeStudioCollectionService as well
                await EdgeStudioCollectionService.shared.setAppState(appState)

                // Set appState in SubscriptionsRepository as well
                await SubscriptionsRepository.shared.setAppState(appState)
                
                // Set up callback using the new setter method (now requires await)
                await databaseRepository.setOnDittoDatabaseConfigUpdate { [weak self] configs in
                    Task { @MainActor [weak self] in
                        self?.dittoApps = configs
                    }
                }
                
                // Register observers after setting up callback (requires await)
                try await databaseRepository.registerLocalObservers()
            } catch {
                appState.setError(error)
            }
            isLoading = false
        }

        func showAppEditor(_ dittoApp: DittoAppConfig) {
            dittoAppToEdit = dittoApp
            isPresented = true
        }

        func showMainStudio(_ dittoApp: DittoAppConfig, appState: AppState)
            async
        {
            do {
                selectedDittoAppConfig = dittoApp
                let didSetupDitto = try await DittoManager.shared
                    .hydrateDittoSelectedApp(
                        dittoApp
                    )
                if didSetupDitto {
                    isMainStudioViewPresented = true
                }
            } catch {
                appState.setError(error)
            }
        }
    }
}

#Preview {
    ContentView()
        .environment(DittoAppConfig.new())
}
