import Combine
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @State private var viewModel: ContentView.ViewModel = ViewModel()

    #if os(macOS)
    @State private var quickstartService = QuickstartDownloadService()
    @State private var showNoConnectionAlert = false
    @State private var showExistingFolderAlert = false
    @State private var showDownloadErrorAlert = false
    @State private var downloadErrorMessage = ""
    @State private var quickstartDestination: URL?
    @State private var existingFolderURL: URL?
    @State private var continueWithoutConfig = false
    #endif

    var body: some View {
        Group {
            if viewModel.isClosingDatabase {
                closingDatabaseView
            } else if viewModel.isMainStudioViewPresented,
                      let selectedApp = viewModel.selectedDittoConfigForDatabase
            {
                MainStudioView(
                    isMainStudioViewPresented: Binding(
                        get: { viewModel.isMainStudioViewPresented },
                        set: { viewModel.isMainStudioViewPresented = $0 }
                    ),
                    isClosingDatabase: Binding(
                        get: { viewModel.isClosingDatabase },
                        set: { viewModel.isClosingDatabase = $0 }
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
            minWidth: (viewModel.isMainStudioViewPresented || viewModel.isClosingDatabase) ? 1400 : 800,
            maxWidth: (viewModel.isMainStudioViewPresented || viewModel.isClosingDatabase) ? .infinity : 800,
            minHeight: (viewModel.isMainStudioViewPresented || viewModel.isClosingDatabase) ? 820 : 540,
            maxHeight: (viewModel.isMainStudioViewPresented || viewModel.isClosingDatabase) ? .infinity : 540
        )
        .onChange(of: viewModel.isMainStudioViewPresented) { _, isPresented in
            guard let window = NSApplication.shared.windows.first(where: { $0.isMainWindow }) else { return }
            if isPresented {
                window.styleMask.insert(.resizable)
                window.minSize = NSSize(width: 1400, height: 820)
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
        #if os(macOS)
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenQuickstartBrowserWindow"))) { _ in
            startQuickstartDownload()
        }
        .alert("No Database Connection", isPresented: $showNoConnectionAlert) {
            Button("Continue Anyway") {
                continueWithoutConfig = true
                openFolderPickerAndDownload(configureEnv: false)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You are not connected to a database. Quickstart projects will be downloaded but .env files will not be auto-configured.")
        }
        .alert("Quickstarts Folder Exists", isPresented: $showExistingFolderAlert) {
            Button("Replace", role: .destructive) {
                if let existing = existingFolderURL, let dest = quickstartDestination {
                    try? quickstartService.removeExistingFolder(at: existing)
                    let hasConfig = DittoManager.shared.dittoSelectedApp != nil
                        && DittoManager.shared.dittoSelectedAppConfig != nil
                    Task {
                        await performDownload(to: dest, configureEnv: hasConfig && !continueWithoutConfig)
                    }
                }
            }
            Button("Choose Different Location") {
                let hasConfig = DittoManager.shared.dittoSelectedApp != nil
                    && DittoManager.shared.dittoSelectedAppConfig != nil
                openFolderPickerAndDownload(configureEnv: hasConfig && !continueWithoutConfig)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("A quickstart-main folder already exists at this location. Would you like to replace it or choose a different location?")
        }
        .alert("Download Error", isPresented: $showDownloadErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(downloadErrorMessage)
        }
        #endif
    }

    private var closingDatabaseView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Closing database...")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                    minHeight: 700,
                    idealHeight: 800,
                    maxHeight: 860
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
                QRCodeDisplayView(config: config, favorites: viewModel.qrCodeFavorites)
                    .frame(minWidth: 360, minHeight: 420)
            }
        }
        .sheet(isPresented: Binding(
            get: { viewModel.isShowingQRScanner },
            set: { viewModel.isShowingQRScanner = $0 }
        )) {
            QRCodeScannerView { config, favorites in
                Task { await viewModel.importFromQRCode(config, favorites: favorites, appState: appState) }
            }
            .frame(minWidth: 480, minHeight: 360)
        }
    }
}

// MARK: - Quickstart Download Flow (macOS)

extension ContentView {
    func startQuickstartDownload() {
        let hasConnection = DittoManager.shared.dittoSelectedApp != nil
            && DittoManager.shared.dittoSelectedAppConfig != nil

        continueWithoutConfig = false

        if !hasConnection {
            showNoConnectionAlert = true
        } else {
            openFolderPickerAndDownload(configureEnv: true)
        }
    }

    func openFolderPickerAndDownload(configureEnv: Bool) {
        let panel = NSOpenPanel()
        panel.title = "Choose Download Location for Quickstarts"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"

        guard panel.runModal() == .OK, let selectedURL = panel.url else {
            return
        }

        quickstartDestination = selectedURL

        // Check for existing folder
        if let existing = quickstartService.existingQuickstartFolder(in: selectedURL) {
            existingFolderURL = existing
            showExistingFolderAlert = true
            return
        }

        Task {
            await performDownload(to: selectedURL, configureEnv: configureEnv)
        }
    }

    func performDownload(to destination: URL, configureEnv: Bool) async {
        do {
            let extractedDir = try await quickstartService.downloadAndExtract(to: destination)

            if configureEnv, let config = await DittoManager.shared.dittoSelectedAppConfig {
                quickstartService.configureEnvFiles(
                    in: extractedDir,
                    databaseId: config.databaseId,
                    token: config.token,
                    authUrl: config.authUrl,
                    websocketUrl: config.websocketUrl
                )

                try? quickstartService.configureEdgeServerYaml(
                    in: extractedDir,
                    databaseId: config.databaseId,
                    token: config.token,
                    authUrl: config.authUrl
                )
            }

            quickstartService.discoverProjects(in: extractedDir, isConfigured: configureEnv)

            // Small delay to let discoverProjects populate on MainActor
            try? await Task.sleep(for: .milliseconds(100))

            let projects = quickstartService.projects
            WindowController.showQuickstartBrowser(
                projects: projects,
                isConfigured: configureEnv,
                directory: extractedDir
            )
        } catch {
            await MainActor.run {
                downloadErrorMessage = error.localizedDescription
                showDownloadErrorAlert = true
            }
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
                    QRCodeDisplayView(config: config, favorites: viewModel.qrCodeFavorites)
                }
            }
            .sheet(isPresented: Binding(
                get: { viewModel.isShowingQRScanner },
                set: { viewModel.isShowingQRScanner = $0 }
            )) {
                QRCodeScannerView { config, favorites in
                    Task { await viewModel.importFromQRCode(config, favorites: favorites, appState: appState) }
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
                                        Button { Task { await viewModel.showQRCode(app) } } label: { Label("QR Code", systemImage: "qrcode") }
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
        var qrCodeFavorites: [FavoriteQueryItem] = []

        /// used for QR scanner
        var isShowingQRScanner = false

        // used for MainStudioView
        var isMainStudioViewPresented = false
        var isClosingDatabase = false
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

        func showQRCode(_ config: DittoConfigForDatabase) async {
            let favorites = await (try? FavoritesRepository.shared.loadFavorites(for: config.databaseId)) ?? []
            qrCodeFavorites = favorites.map { FavoriteQueryItem(q: $0.query) }
            qrCodeConfig = config
            isShowingQRCode = true
        }

        func showQRScanner() {
            isShowingQRScanner = true
        }

        func importFromQRCode(_ config: DittoConfigForDatabase, favorites: [FavoriteQueryItem], appState: AppState) async {
            do {
                try await databaseRepository.addDittoAppConfig(config)
                if !favorites.isEmpty {
                    _ = try? await FavoritesRepository.shared.loadFavorites(for: config.databaseId)
                    for item in favorites {
                        let fav = DittoQueryHistory(
                            id: UUID().uuidString,
                            query: item.q,
                            createdDate: Date().ISO8601Format()
                        )
                        try? await FavoritesRepository.shared.saveFavorite(fav)
                    }
                }
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
