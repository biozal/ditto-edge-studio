import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel: ContentView.ViewModel = ViewModel()

    /// Persists the `_id` of the currently open database across app launches via
    /// SceneStorage (per-window state, restored on cold launch). When `loadApps`
    /// completes we re-open whichever database matches this id, so users land
    /// back where they were after a restart. Cleared when the user closes the
    /// database or hydration fails.
    @SceneStorage("selectedDatabaseId") private var storedDatabaseId: String?

    #if os(macOS)
    @State private var quickstartService = QuickstartDownloadService()
    @State private var showNoConnectionAlert = false
    @State private var showExistingFolderAlert = false
    @State private var showProgressSheet = false
    @State private var quickstartDestination: URL?
    @State private var existingFolderURL: URL?
    @State private var continueWithoutConfig = false
    #endif

    var body: some View {
        Group {
            if viewModel.isClosingDatabase {
                closingDatabaseView
                #if os(macOS)
                .frame(minWidth: 1400, minHeight: 820)
                #endif
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
                .environment(appState)
                #if os(macOS)
                    .frame(minWidth: 1400, minHeight: 820)
                #endif
            } else {
                #if os(iOS)
                iPadPickerView
                #else
                macOSPickerView
                    .frame(minWidth: 800, minHeight: 540)
                #endif
            }
        }
        .onAppear {
            Task {
                await viewModel.loadApps(appState: appState)
                // Restore the previously open database if one was persisted in
                // SceneStorage. Skip if a database is already presented (e.g. the
                // user tapped a card before the load finished) or if the stored
                // id no longer matches any saved config (e.g. the user deleted
                // the config between launches).
                if let storedId = storedDatabaseId,
                   !viewModel.isMainStudioViewPresented,
                   let config = viewModel.dittoApps.first(where: { $0._id == storedId })
                {
                    await viewModel.showMainStudio(config, appState: appState)
                }
            }
        }
        // Keep SceneStorage in sync with the currently presented database so a
        // cold launch restores the right one. Setting `nil` on close clears it
        // and prevents auto-reopening a database the user explicitly closed.
        .onChange(of: viewModel.isMainStudioViewPresented) { _, isPresented in
            if isPresented {
                storedDatabaseId = viewModel.selectedDittoConfigForDatabase?._id
            } else if !viewModel.isClosingDatabase {
                storedDatabaseId = nil
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
                    Task {
                        let hasApp = await DittoManager.shared.dittoSelectedApp != nil
                        let hasAppConfig = await DittoManager.shared.dittoSelectedAppConfig != nil
                        let hasConfig = hasApp && hasAppConfig
                        await performDownload(to: dest, configureEnv: hasConfig && !continueWithoutConfig)
                    }
                }
            }
            Button("Choose Different Location") {
                Task {
                    let hasApp = await DittoManager.shared.dittoSelectedApp != nil
                    let hasAppConfig = await DittoManager.shared.dittoSelectedAppConfig != nil
                    let hasConfig = hasApp && hasAppConfig
                    openFolderPickerAndDownload(configureEnv: hasConfig && !continueWithoutConfig)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("A quickstart-main folder already exists at this location. Would you like to replace it or choose a different location?")
        }
        .sheet(isPresented: $showProgressSheet) {
            QuickstartProgressWindow(
                service: quickstartService,
                onCancel: { showProgressSheet = false }
            )
            .interactiveDismissDisabled(quickstartService.isDownloading)
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
                    idealHeight: 800
                )
                .environment(appState)
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
        continueWithoutConfig = false

        Task {
            let hasApp = await DittoManager.shared.dittoSelectedApp != nil
            let hasAppConfig = await DittoManager.shared.dittoSelectedAppConfig != nil
            let hasConnection = hasApp && hasAppConfig

            if !hasConnection {
                showNoConnectionAlert = true
            } else {
                openFolderPickerAndDownload(configureEnv: true)
            }
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
        // Reset and show progress
        quickstartService.reset()
        showProgressSheet = true

        do {
            let extractedDir = try await quickstartService.downloadAndExtract(to: destination)

            if configureEnv, let config = await DittoManager.shared.dittoSelectedAppConfig {
                quickstartService.updateStatus("Configuring .env files...")
                quickstartService.configureEnvFiles(
                    in: extractedDir,
                    databaseId: config.databaseId,
                    token: config.token,
                    authUrl: config.authUrl,
                    websocketUrl: config.websocketUrl
                )

                quickstartService.updateStatus("Configuring edge-server...")
                try? quickstartService.configureEdgeServerYaml(
                    in: extractedDir,
                    databaseId: config.databaseId,
                    token: config.token,
                    authUrl: config.authUrl
                )
            }

            quickstartService.updateStatus("Discovering projects...")
            quickstartService.discoverProjects(in: extractedDir, isConfigured: configureEnv)

            quickstartService.setComplete()

            // Brief pause to show "Complete" before transitioning
            try? await Task.sleep(for: .milliseconds(500))

            // Close progress sheet, open browser
            showProgressSheet = false

            let projects = quickstartService.projects
            WindowController.showQuickstartBrowser(
                projects: projects,
                isConfigured: configureEnv,
                directory: extractedDir
            )
        } catch {
            quickstartService.setError(error.localizedDescription)
            // Progress sheet stays open showing error — user clicks OK to dismiss
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
                    .environment(appState)
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
                } else if let initError = viewModel.sqlCipherInitError {
                    sqlCipherInitErrorView(initError)
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
                                    .overlay {
                                        if viewModel.openingDatabaseId == app._id {
                                            ZStack {
                                                Color.black.opacity(0.35)
                                                ProgressView()
                                                    .controlSize(.large)
                                                    .tint(.white)
                                            }
                                            .clipShape(RoundedRectangle(cornerRadius: 12))
                                            .accessibilityIdentifier("DatabaseOpeningSpinner")
                                        }
                                    }
                                    .opacity(
                                        (viewModel.openingDatabaseId != nil &&
                                            viewModel.openingDatabaseId != app._id) ? 0.5 : 1.0
                                    )
                                    .allowsHitTesting(viewModel.openingDatabaseId == nil)
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

    /// Distinct error/retry state for SQLCipher initialization failures.
    /// Used in place of the indefinite spinner from before C3.
    func sqlCipherInitErrorView(_ error: Error) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            Text("Database Storage Unavailable")
                .font(.title2)
                .foregroundColor(.primary)
            Text(error.localizedDescription)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button {
                Task { await viewModel.loadApps(appState: appState) }
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(.dittoYellow)
            .accessibilityIdentifier("RetrySQLCipherInitButton")
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
#endif

// MARK: - ViewModel

extension ContentView {
    @Observable
    @MainActor
    class ViewModel {
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

        /// `_id` of the database whose hydration is currently in flight, if any.
        /// Drives the per-card spinner overlay and disables further taps in the picker
        /// so users get visible feedback during the (sometimes multi-second) open.
        var openingDatabaseId: String?

        /// Set when the SQLCipher initialization fails. Drives the distinct
        /// "storage error + Retry" picker state so users aren't left staring at
        /// an indefinite spinner. Cleared on every `loadApps` invocation.
        var sqlCipherInitError: Error?

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
            sqlCipherInitError = nil

            // C3: Gate every downstream repository call on SQLCipher being ready.
            // `initialize()` is idempotent — it short-circuits when already complete,
            // so we don't race AppState's eager warm-up Task. If init fails we bail
            // here and the picker view renders the dedicated retry state instead of
            // an indefinite spinner.
            do {
                try await SQLCipherService.shared.initialize()
            } catch {
                Log.error("SQLCipher initialization failed: \(error.localizedDescription)")
                sqlCipherInitError = error
                isLoading = false
                return
            }

            do {
                // 1. Set appState in DittoManager
                await DittoManager.shared.setAppState(appState)

                // 2. Load database configs from secure storage
                await databaseRepository.setAppState(appState)
                let configs = try await databaseRepository.loadDatabaseConfigs()
                dittoApps = configs

                // 3. Set up callback for future updates. The callback type is
                //    @MainActor, so we can assign directly without an inner Task.
                await databaseRepository.setOnDittoDatabaseConfigUpdate { [weak self] configs in
                    self?.dittoApps = configs
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
            // Guard against double-taps while another open is already in flight.
            guard openingDatabaseId == nil else { return }

            openingDatabaseId = dittoApp._id
            defer { openingDatabaseId = nil }

            do {
                selectedDittoConfigForDatabase = dittoApp
                let didSetupDitto = try await DittoManager.shared
                    .hydrateDittoSelectedDatabase(
                        dittoApp
                    )
                if didSetupDitto {
                    isMainStudioViewPresented = true
                } else {
                    // C2: hydration returned `false` without throwing — the silent
                    // abort would otherwise leave the user staring at the picker
                    // with no feedback. Surface a real error so the alert fires.
                    selectedDittoConfigForDatabase = nil
                    appState.setError(AppError.error(
                        message: "Failed to initialize database '\(dittoApp.name)'. " +
                            "Please verify the configuration and try again."
                    ))
                }
            } catch {
                selectedDittoConfigForDatabase = nil
                appState.setError(error)
            }
        }
    }
}

#Preview {
    ContentView()
        .environment(DittoConfigForDatabase.new())
}
