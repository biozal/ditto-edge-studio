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
            maxWidth: viewModel.isMainStudioViewPresented ? .infinity : 800,
            minHeight: viewModel.isMainStudioViewPresented ? 700 : 540,
            maxHeight: viewModel.isMainStudioViewPresented ? .infinity : 540
        )
        .onChange(of: viewModel.isMainStudioViewPresented) { _, isPresented in
            guard let window = NSApplication.shared.windows.first(where: { $0.isMainWindow }) else { return }
            if isPresented {
                window.styleMask.insert(.resizable)
                window.minSize = NSSize(width: 1200, height: 700)
                window.maxSize = NSSize(width: 10000, height: 10000)
                window.standardWindowButton(.zoomButton)?.isHidden = false
            } else {
                window.setContentSize(NSSize(width: 800, height: 540))
                window.minSize = NSSize(width: 800, height: 540)
                window.maxSize = NSSize(width: 800, height: 540)
                window.styleMask.remove(.resizable)
                window.standardWindowButton(.zoomButton)?.isHidden = true
                window.center()
            }
        }
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
                Image("ditto-edge-studio-splash")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 300, maxHeight: 120)

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

                    Button {
                        viewModel.showQRScanner()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "qrcode.viewfinder")
                                .foregroundColor(.white)
                            Text("Import from QR Code")
                                .foregroundColor(.white)
                                .fontWeight(.medium)
                            Spacer()
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
            .padding(.bottom, 100)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            WindowAccessor { window in
                window.setContentSize(NSSize(width: 800, height: 540))
                window.minSize = NSSize(width: 800, height: 540)
                window.maxSize = NSSize(width: 800, height: 540)
                window.styleMask.remove(.resizable)
                window.standardWindowButton(.zoomButton)?.isHidden = true
                window.center()
            }
        )
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
        .sheet(isPresented: Binding(
            get: { viewModel.isShowingQRCode },
            set: { viewModel.isShowingQRCode = $0 }
        )) {
            if let config = viewModel.qrCodeConfig {
                QRCodeDisplayView(config: config)
                    .frame(minWidth: 360, minHeight: 420)
            }
        }
        .sheet(isPresented: Binding(
            get: { viewModel.isShowingQRScanner },
            set: { viewModel.isShowingQRScanner = $0 }
        )) {
            QRCodeScannerView { config in
                Task { await viewModel.importFromQRCode(config, appState: appState) }
            }
            .frame(minWidth: 480, minHeight: 360)
        }
    }
}
#endif

// MARK: - iPad Picker View

#if os(iOS)
extension ContentView {
    var iPadPickerView: some View {
        compactPickerContent
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
                    .environmentObject(appState)
                    .presentationDetents([.large])
                }
            }
            .sheet(isPresented: Binding(
                get: { viewModel.isShowingQRCode },
                set: { viewModel.isShowingQRCode = $0 }
            )) {
                if let config = viewModel.qrCodeConfig {
                    QRCodeDisplayView(config: config)
                }
            }
            .sheet(isPresented: Binding(
                get: { viewModel.isShowingQRScanner },
                set: { viewModel.isShowingQRScanner = $0 }
            )) {
                QRCodeScannerView { config in
                    Task { await viewModel.importFromQRCode(config, appState: appState) }
                }
            }
    }

    /// Compact mode: < 650pt wide — HIG-compliant NavigationStack with yellow FAB
    var compactPickerContent: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                Color(uiColor: .systemBackground).ignoresSafeArea()

                if viewModel.isLoading {
                    ProgressView("Loading...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.dittoApps.isEmpty {
                    VStack(spacing: 20) {
                        FontAwesomeText(icon: DataIcon.databaseThin, size: 48, color: .secondary)
                        Text("No Databases")
                            .font(.title2)
                            .foregroundColor(.primary)
                        Text("Tap + to add a database configuration.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 32)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 300))],
                            spacing: 16
                        ) {
                            ForEach(viewModel.dittoApps, id: \._id) { app in
                                DatabaseCard(dittoApp: app, onEdit: { viewModel.showAppEditor(app) })
                                    .onTapGesture {
                                        Task { await viewModel.showMainStudio(app, appState: appState) }
                                    }
                                    .contextMenu {
                                        Button { viewModel.showAppEditor(app) } label: { Label("Edit", systemImage: "pencil") }
                                        Button { viewModel.showQRCode(app) } label: { Label("QR Code", systemImage: "qrcode") }
                                        Divider()
                                        Button(role: .destructive) {
                                            Task { await viewModel.deleteApp(app, appState: appState) }
                                        } label: { Label("Delete", systemImage: "trash") }
                                    }
                                    .accessibilityIdentifier("AppCard_\(app.name)")
                            }
                        }
                        .padding(.horizontal)
                        .accessibilityIdentifier("DatabaseList")
                    }
                    .safeAreaInset(edge: .bottom) {
                        Color.clear.frame(height: 88)
                    }
                }

                // Floating Action Button — HIG: primary creation action, bottom-right, thumb-accessible
                Button {
                    viewModel.showAppEditor(DittoConfigForDatabase.new())
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.black)
                        .frame(width: 56, height: 56)
                        .background(Color.dittoYellow)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 4)
                }
                .padding(.bottom, 24)
                .padding(.trailing, 24)
                .accessibilityIdentifier("AddDatabaseButton")
            }
            .navigationTitle("Edge Studio")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                // HIG: secondary/utility actions in navigation bar trailing
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        viewModel.showQRScanner()
                    } label: {
                        Image(systemName: "qrcode.viewfinder")
                            .foregroundColor(.primary)
                    }
                    .accessibilityIdentifier("ImportQRCodeButton")
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        if let url = URL(string: "https://portal.ditto.live") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Image(systemName: "cloud")
                            .foregroundColor(.primary)
                    }
                }
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

        // used for QR code display
        var isShowingQRCode = false
        var qrCodeConfig: DittoConfigForDatabase?

        /// used for QR scanner
        var isShowingQRScanner = false

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

        func showQRCode(_ config: DittoConfigForDatabase) {
            qrCodeConfig = config
            isShowingQRCode = true
        }

        func showQRScanner() {
            isShowingQRScanner = true
        }

        func importFromQRCode(_ config: DittoConfigForDatabase, appState: AppState) async {
            do {
                try await databaseRepository.addDittoAppConfig(config)
            } catch {
                appState.setError(error)
            }
            isShowingQRScanner = false
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
