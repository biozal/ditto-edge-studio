import Combine
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @State private var viewModel: ContentView.ViewModel = ViewModel()

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
                #if os(iOS)
                iPadPickerView
                #else
                macOSPickerView
                #endif
            }
        }
        #if os(macOS)
        .frame(
            minWidth: viewModel.isMainStudioViewPresented ? 1200 : 800,
            minHeight: viewModel.isMainStudioViewPresented ? 700 : 540
        )
        #endif
        .onAppear {
            Task {
                await viewModel.loadApps(appState: appState)
            }
        }
    }
}

// MARK: - macOS Picker View

#if os(macOS)
extension ContentView {
    var macOSPickerView: some View {
        ZStack(alignment: .bottomLeading) {
            Image("ditto-splash")
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .ignoresSafeArea()

            Color.black.opacity(0.20)
                .ignoresSafeArea()

            HStack {
                Spacer()
                DatabaseListPanel(viewModel: viewModel, appState: appState)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 4)
                    .frame(width: 340, height: 450)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(LinearGradient(
                                colors: [
                                    Color.black.opacity(0.18),
                                    Color.black.opacity(0.52)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                            )
                    )
                    .shadow(color: .black.opacity(0.45), radius: 18, x: 0, y: 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding(.trailing, 24)

            VStack(alignment: .center, spacing: 20) {
                Text("Edge Studio")
                    .font(.custom("ChakraPetch-Bold", size: 42))
                    .foregroundColor(.dittoYellow)
                    .shadow(color: .black.opacity(0.7), radius: 4, x: 0, y: 2)

                VStack(spacing: 14) {
                    Button {
                        viewModel.showAppEditor(DittoConfigForDatabase.new())
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "plus")
                                .foregroundColor(.black)
                            Text("Database Config")
                                .foregroundColor(.black)
                                .fontWeight(.medium)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.dittoYellow)
                    .focusEffectDisabled()
                    .accessibilityIdentifier("AddDatabaseButton")

                    Button {
                        if let url = URL(string: "https://portal.ditto.live") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "cloud")
                                .foregroundColor(.white)
                            Text("Ditto Portal")
                                .foregroundColor(.white)
                                .fontWeight(.medium)
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.6))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.glass)
                    .focusEffectDisabled()
                }
                .frame(width: 280)
            }
            .frame(width: 436)
            .padding(.bottom, 60)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            // Resize window to 800×540 whenever the picker appears —
            // handles both first launch and returning from MainStudioView.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                guard let window = NSApplication.shared.keyWindow else { return }
                let fixedSize = NSSize(width: 800, height: 540)
                window.setContentSize(fixedSize)
                window.minSize = fixedSize
                window.maxSize = fixedSize
                window.styleMask.remove(.resizable)
                window.standardWindowButton(.zoomButton)?.isHidden = true
                window.center()
            }
        }
        .onDisappear {
            DispatchQueue.main.async {
                guard let window = NSApplication.shared.keyWindow else { return }
                window.styleMask.insert(.resizable)
                window.minSize = NSSize(width: 1200, height: 700)
                window.maxSize = NSSize(width: 10000, height: 10000)
                window.standardWindowButton(.zoomButton)?.isHidden = false
            }
        }
        .sheet(
            isPresented: Binding(
                get: { viewModel.isPresented },
                set: { viewModel.isPresented = $0 }
            )
        ) {
            if let dittoAppConfig = viewModel.dittoAppToEdit {
                DatabaseEditorView(
                    isPresented: Binding(
                        get: { viewModel.isPresented },
                        set: { viewModel.isPresented = $0 }
                    ),
                    dittoAppConfig: dittoAppConfig
                )
                .frame(
                    minWidth: 600,
                    idealWidth: 1000,
                    maxWidth: 1920,
                    minHeight: 600,
                    idealHeight: 600,
                    maxHeight: 650
                )
                .environmentObject(appState)
                .presentationDetents([.medium, .large])
            }
        }
    }
}
#endif

// MARK: - iPad Picker View

#if os(iOS)
extension ContentView {
    var iPadPickerView: some View {
        ZStack(alignment: .bottomLeading) {
            // Same splash background as macOS
            Image("ditto-splash")
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .ignoresSafeArea()

            Color.black.opacity(0.20)
                .ignoresSafeArea()

            // Floating glass panel — right-center
            HStack {
                Spacer()
                DatabaseListPanel(viewModel: viewModel, appState: appState)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 4)
                    .frame(width: 340, height: 450)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(LinearGradient(
                                colors: [
                                    Color.black.opacity(0.18),
                                    Color.black.opacity(0.52)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                            )
                    )
                    .shadow(color: .black.opacity(0.45), radius: 18, x: 0, y: 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding(.trailing, 24)

            // Branding + action buttons — bottom-left
            VStack(alignment: .center, spacing: 20) {
                Text("Edge Studio")
                    .font(.custom("ChakraPetch-Bold", size: 42))
                    .foregroundColor(.dittoYellow)
                    .shadow(color: .black.opacity(0.7), radius: 4, x: 0, y: 2)

                VStack(spacing: 14) {
                    Button {
                        viewModel.showAppEditor(DittoConfigForDatabase.new())
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "plus")
                                .foregroundColor(.black)
                            Text("Database Config")
                                .foregroundColor(.black)
                                .fontWeight(.medium)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.dittoYellow)
                    .focusEffectDisabled()
                    .accessibilityIdentifier("AddDatabaseButton")

                    Button {
                        if let url = URL(string: "https://portal.ditto.live") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "cloud")
                                .foregroundColor(.white)
                            Text("Ditto Portal")
                                .foregroundColor(.white)
                                .fontWeight(.medium)
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.6))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.glass)
                    .focusEffectDisabled()
                }
                .frame(width: 280)
            }
            .frame(width: 436)
            .padding(.bottom, 60)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(
            isPresented: Binding(
                get: { viewModel.isPresented },
                set: { viewModel.isPresented = $0 }
            )
        ) {
            if let dittoAppConfig = viewModel.dittoAppToEdit {
                DatabaseEditorView(
                    isPresented: Binding(
                        get: { viewModel.isPresented },
                        set: { viewModel.isPresented = $0 }
                    ),
                    dittoAppConfig: dittoAppConfig
                )
                .frame(
                    minWidth: 800,
                    idealWidth: 1000,
                    maxWidth: 1080,
                    minHeight: 600,
                    idealHeight: 680,
                    maxHeight: 850
                )
                .environmentObject(appState)
                .presentationDetents([.medium, .large])
            }
        }
    }
}
#endif

// MARK: - ViewModel

extension ContentView {
    @Observable
    @MainActor
    class ViewModel {
        @ObservationIgnored private var cancellables = Set<AnyCancellable>()
        private let databaseRepository = DatabaseRepository.shared

        var dittoApps: [DittoConfigForDatabase] = []
        var isLoading = false
        var isMainStudioLoaded = false

        // used for editor
        var isPresented = false
        var dittoAppToEdit: DittoConfigForDatabase?

        // used for MainStudioView
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
                // 1. Set appState in DittoManager
                await DittoManager.shared.setAppState(appState)

                // 2. Load database configs from secure storage
                await databaseRepository.setAppState(appState)
                let configs = try await databaseRepository.loadDatabaseConfigs()
                dittoApps = configs

                // 3. Set up callback for future updates
                await databaseRepository.setOnDittoDatabaseConfigUpdate { [weak self] configs in
                    Task { @MainActor [weak self] in
                        self?.dittoApps = configs
                    }
                }

                // 4. Set appState in other repositories
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
