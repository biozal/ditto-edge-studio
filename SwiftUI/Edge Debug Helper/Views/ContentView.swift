import Combine
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
                let selectedApp = viewModel.selectedDittoConfigForDatabase
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
                            AnyView(NoDatabaseConfigurationView())
                        } else {
                            DatabaseList(
                                viewModel: viewModel,
                                appState: appState
                            )
                        }
                    }
                    .navigationTitle(Text("Registered Ditto Databases"))
                    .toolbar {
                        #if os(iOS)
                            ToolbarItem(placement: .topBarTrailing) {
                                Button {
                                    viewModel.showAppEditor(
                                        DittoConfigForDatabase.new()
                                    )
                                } label: {
                                    FontAwesomeText(icon: ActionIcon.plus, size: 14)
                                }
                                .accessibilityIdentifier("AddDatabaseButton")
                            }
                        #else
                            ToolbarItem(placement: .automatic) {
                                Button {
                                    viewModel.showAppEditor(
                                        DittoConfigForDatabase.new()
                                    )
                                } label: {
                                    FontAwesomeText(icon: ActionIcon.plus, size: 14)
                                }
                                .accessibilityIdentifier("AddDatabaseButton")
                            }
                        #endif
                    }
                    .sheet(
                        isPresented: Binding(
                            get: { viewModel.isPresented },
                            set: { viewModel.isPresented = $0 }
                        )
                    ) {
                        DatabaseEditorView(
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
                                maxWidth: 1920,
                                minHeight: 600,
                                idealHeight: 600,
                                maxHeight: 650
                            )
                        #elseif os(iOS)
                            .frame(
                                minWidth: UIDevice.current.userInterfaceIdiom
                                    == .pad ? 800 : nil,
                                idealWidth: UIDevice.current.userInterfaceIdiom
                                    == .pad ? 1000 : nil,
                                maxWidth: UIDevice.current.userInterfaceIdiom
                                    == .pad ? 1080 : nil,
                                minHeight: UIDevice.current.userInterfaceIdiom
                                    == .pad ? 600 : nil,
                                idealHeight: UIDevice.current.userInterfaceIdiom
                                    == .pad ? 680 : nil,
                                maxHeight: UIDevice.current.userInterfaceIdiom
                                    == .pad ? 850 : nil
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

        var dittoApps: [DittoConfigForDatabase] = []
        var isLoading = false
        var isMainStudioLoaded = false

        //used for editor
        var isPresented = false
        var dittoAppToEdit: DittoConfigForDatabase?

        //used for MainStudioView
        var isMainStudioViewPresented = false
        var selectedDittoConfigForDatabase: DittoConfigForDatabase?

        init() {
            // Repository callback will be set up when loadApps is called
        }

        func deleteApp(_ dittoApp: DittoConfigForDatabase, appState: AppState) async {
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
                // 1. Check for legacy data and show warning if needed
                let cleanupService = LegacyDataCleanupService.shared
                if await cleanupService.hasLegacyData() {
                    let userApprovedCleanup = await cleanupService.showBreakingChangeWarning()

                    if !userApprovedCleanup {
                        // User chose to cancel - exit app
                        #if os(macOS)
                        NSApplication.shared.terminate(nil)
                        #else
                        exit(0)
                        #endif
                        return
                    }

                    // User approved - delete old data
                    try await cleanupService.cleanupLegacyData()
                }

                // 2. Set appState in DittoManager
                await DittoManager.shared.setAppState(appState)

                // 3. Load database configs from secure storage
                await databaseRepository.setAppState(appState)
                let configs = try await databaseRepository.loadDatabaseConfigs()
                self.dittoApps = configs

                // 4. Set up callback for future updates
                await databaseRepository.setOnDittoDatabaseConfigUpdate { [weak self] configs in
                    Task { @MainActor [weak self] in
                        self?.dittoApps = configs
                    }
                }

                // 5. Set appState in other repositories
                await SystemRepository.shared.setAppState(appState)
                await ObservableRepository.shared.setAppState(appState)
                await FavoritesRepository.shared.setAppState(appState)
                await HistoryRepository.shared.setAppState(appState)
                await CollectionsRepository.shared.setAppState(appState)
                await SubscriptionsRepository.shared.setAppState(appState)

            } catch {
                appState.setError(error)
            }
            isLoading = false
        }

        func showAppEditor(_ dittoApp: DittoConfigForDatabase) {
            dittoAppToEdit = dittoApp
            isPresented = true
        }

        func showMainStudio(_ dittoApp: DittoConfigForDatabase, appState: AppState)
            async
        {
            do {
                selectedDittoConfigForDatabase = dittoApp
                let didSetupDitto = try await DittoManager.shared
                    .hydrateDittoSelectedDatabase(
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
        .environment(DittoConfigForDatabase.new())
}
