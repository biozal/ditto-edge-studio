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

    /// Tracks unsaved edits in the active `DatabaseEditorView` sheet so we can
    /// disable interactive dismiss (iOS swipe-down) until the user resolves
    /// them. Reset whenever the editor sheet opens or closes.
    @State private var databaseEditorHasUnsavedChanges = false

    // Quickstart download flow state lives on `ContentView.ViewModel` as of
    // Phase 10c — the View used to own seven @State properties + the
    // orchestration methods (NSOpenPanel, performDownload). Moving it to the
    // VM makes the flow unit-testable and keeps the View as a thin trigger.

    var body: some View {
        // Local `@Bindable` projection so `$viewModel.x` produces a
        // `Binding<X>` for inner properties of the @Observable VM. Replaces a
        // dozen `Binding(get:set:)` long-forms across this view.
        @Bindable var viewModel = viewModel
        return Group {
            if viewModel.isClosingDatabase {
                closingDatabaseView
                #if os(macOS)
                .frame(minWidth: 1400, minHeight: 820)
                #endif
            } else if viewModel.isMainStudioViewPresented,
                      let selectedApp = viewModel.selectedDittoConfigForDatabase
            {
                MainStudioView(
                    isMainStudioViewPresented: $viewModel.isMainStudioViewPresented,
                    isClosingDatabase: $viewModel.isClosingDatabase,
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
                // Xcode-launch-style fixed-size, non-resizable window.
                // The Scene uses `.windowResizability(.contentSize)`, so
                // declaring a fixed `.frame(width:height:)` here locks
                // the window to that exact size — guarantees all 3 CTA
                // buttons (Database Config, Ditto Portal, Import from
                // QR Code) and the database list panel are always
                // fully drawn regardless of which screen the user is
                // on. Once a database is opened MainStudioView's
                // `.frame(minWidth:minHeight:)` lets the window grow.
                macOSPickerView
                    .frame(width: 900, height: 640)
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
            Task { await viewModel.startQuickstartDownload() }
        }
        .alert("No Database Connection", isPresented: $viewModel.showNoConnectionAlert) {
            Button("Continue Anyway") {
                Task { await viewModel.continueDownloadWithoutConfig() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You are not connected to a database. Quickstart projects will be downloaded but .env files will not be auto-configured.")
        }
        .alert("Quickstarts Folder Exists", isPresented: $viewModel.showExistingFolderAlert) {
            Button("Replace", role: .destructive) {
                Task { await viewModel.replaceExistingFolderAndDownload() }
            }
            Button("Choose Different Location") {
                Task { await viewModel.chooseDifferentLocationAndDownload() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("A quickstart-main folder already exists at this location. Would you like to replace it or choose a different location?")
        }
        .sheet(isPresented: $viewModel.showProgressSheet) {
            QuickstartProgressWindow(
                service: viewModel.quickstartService,
                onCancel: { viewModel.showProgressSheet = false }
            )
            // Lock the sheet during an in-flight download, but allow dismissal
            // when an error has been surfaced so the user can recover.
            .interactiveDismissDisabled(viewModel.quickstartService.isDownloading && !viewModel.quickstartService.hasError)
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
        @Bindable var viewModel = viewModel
        return ZStack(alignment: .bottomLeading) {
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

            // Bottom-leading hero stack (logo + CTA buttons).
            //
            // Wrapped in a VStack with a leading Spacer(minLength: 0) so the
            // cluster is anchored to the bottom of the window but compresses
            // upward when the window gets short — without this, fixed
            // `.padding(.bottom, …)` in a ZStack lets the buttons overflow
            // past the window's bottom edge (Ditto Portal would clip on a
            // 14" MacBook). Edge padding (40 left / 40 bottom) keeps the
            // cluster off the window walls like Xcode's launch screen.
            VStack(spacing: 0) {
                Spacer(minLength: 0)

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
                                    .foregroundStyle(.black)
                                Text("Database Config")
                                    .foregroundStyle(.black)
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
                                    .foregroundStyle(.white)
                                Text("Ditto Portal")
                                    .foregroundStyle(.white)
                                    .fontWeight(.medium)
                                Spacer()
                                Image(systemName: "arrow.up.right.square")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.white.opacity(0.6))
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
                                    .foregroundStyle(.white)
                                Text("Import from QR Code")
                                    .foregroundStyle(.white)
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
            }
            .padding(.leading, 40)
            .padding(.bottom, 128)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(
            isPresented: $viewModel.isPresented,
            onDismiss: { databaseEditorHasUnsavedChanges = false },
            content: {
                if let dittoAppConfig = viewModel.dittoAppToEdit {
                    DatabaseEditorView(
                        isPresented: $viewModel.isPresented,
                        hasUnsavedChanges: $databaseEditorHasUnsavedChanges,
                        dittoAppConfig: dittoAppConfig
                    )
                    .frame(
                        minWidth: 600,
                        idealWidth: 1000,
                        maxWidth: 1920,
                        minHeight: 700,
                        idealHeight: 1000,
                        maxHeight: 1400
                    )
                    .environment(appState)
                    .presentationDetents([.medium, .large])
                    .interactiveDismissDisabled(databaseEditorHasUnsavedChanges)
                }
            }
        )
        .sheet(isPresented: $viewModel.isShowingQRCode) {
            if let config = viewModel.qrCodeConfig {
                QRCodeDisplayView(config: config, favorites: viewModel.qrCodeFavorites)
                    .frame(minWidth: 360, minHeight: 420)
            }
        }
        .sheet(isPresented: $viewModel.isShowingQRScanner) {
            QRCodeScannerView { config, favorites in
                Task { await viewModel.importFromQRCode(config, favorites: favorites, appState: appState) }
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
        @Bindable var viewModel = viewModel
        return compactPickerContent
            .sheet(
                isPresented: $viewModel.isPresented,
                onDismiss: { databaseEditorHasUnsavedChanges = false },
                content: {
                    if let dittoAppConfig = viewModel.dittoAppToEdit {
                        DatabaseEditorView(
                            isPresented: $viewModel.isPresented,
                            hasUnsavedChanges: $databaseEditorHasUnsavedChanges,
                            dittoAppConfig: dittoAppConfig
                        )
                        .environment(appState)
                        .presentationDetents([.large])
                        .interactiveDismissDisabled(databaseEditorHasUnsavedChanges)
                    }
                }
            )
            .sheet(isPresented: $viewModel.isShowingQRCode) {
                if let config = viewModel.qrCodeConfig {
                    QRCodeDisplayView(config: config, favorites: viewModel.qrCodeFavorites)
                }
            }
            .sheet(isPresented: $viewModel.isShowingQRScanner) {
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
                } else if let loadError = viewModel.loadAppsError {
                    loadAppsErrorView(loadError)
                } else if viewModel.dittoApps.isEmpty {
                    VStack(spacing: 20) {
                        FontAwesomeText(icon: DataIcon.databaseThin, size: 48, color: .secondary)
                        Text("No Databases")
                            .font(.title2)
                            .foregroundStyle(.primary)
                        Text("Tap + to add a database configuration.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
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
                        .foregroundStyle(.black)
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
                            .foregroundStyle(.primary)
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
                            .foregroundStyle(.primary)
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
                .foregroundStyle(.orange)
            Text("Database Storage Unavailable")
                .font(.title2)
                .foregroundStyle(.primary)
            Text(error.localizedDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)
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

    /// Distinct error/retry state for failures inside `loadApps` so users can
    /// tell a load failure apart from a genuinely empty configuration list.
    func loadAppsErrorView(_ error: Error) -> some View {
        ContentUnavailableView {
            Label("Couldn't Load Databases", systemImage: "exclamationmark.triangle.fill")
        } description: {
            Text(error.localizedDescription)
        } actions: {
            Button {
                Task { await viewModel.loadApps(appState: appState) }
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(.dittoYellow)
            .accessibilityIdentifier("RetryLoadAppsButton")
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
        // MARK: - Injected Dependencies

        //
        // Stored as protocol types so unit tests can swap mocks. Defaults wire
        // to the production singletons. See `Data/Protocols.swift`.

        @ObservationIgnored
        private let dittoManager: any DittoManagerProtocol
        @ObservationIgnored
        private let databaseRepository: any DatabaseRepositoryProtocol
        @ObservationIgnored
        private let subscriptionsRepository: any SubscriptionsRepositoryProtocol
        @ObservationIgnored
        private let systemRepository: any SystemRepositoryProtocol
        @ObservationIgnored
        private let historyRepository: any HistoryRepositoryProtocol
        @ObservationIgnored
        private let favoritesRepository: any FavoritesRepositoryProtocol
        @ObservationIgnored
        private let observableRepository: any ObservableRepositoryProtocol
        @ObservationIgnored
        private let collectionsRepository: any CollectionsRepositoryProtocol

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

        /// Set when `loadApps` fails reading from the database repository.
        /// Drives a separate "Couldn't Load Databases + Retry" picker state so
        /// users can distinguish a load failure from a genuinely empty
        /// configuration list. Cleared on every `loadApps` invocation.
        var loadAppsError: Error?

        init(
            dittoManager: any DittoManagerProtocol = DittoManager.shared,
            databaseRepository: any DatabaseRepositoryProtocol = DatabaseRepository.shared,
            subscriptionsRepository: any SubscriptionsRepositoryProtocol = SubscriptionsRepository.shared,
            systemRepository: any SystemRepositoryProtocol = SystemRepository.shared,
            historyRepository: any HistoryRepositoryProtocol = HistoryRepository.shared,
            favoritesRepository: any FavoritesRepositoryProtocol = FavoritesRepository.shared,
            observableRepository: any ObservableRepositoryProtocol = ObservableRepository.shared,
            collectionsRepository: any CollectionsRepositoryProtocol = CollectionsRepository.shared
        ) {
            self.dittoManager = dittoManager
            self.databaseRepository = databaseRepository
            self.subscriptionsRepository = subscriptionsRepository
            self.systemRepository = systemRepository
            self.historyRepository = historyRepository
            self.favoritesRepository = favoritesRepository
            self.observableRepository = observableRepository
            self.collectionsRepository = collectionsRepository
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
            loadAppsError = nil

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
                await dittoManager.setAppState(appState)

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
                await systemRepository.setAppState(appState)
                await observableRepository.setAppState(appState)
                await favoritesRepository.setAppState(appState)
                await historyRepository.setAppState(appState)
                await collectionsRepository.setAppState(appState)
                await subscriptionsRepository.setAppState(appState)
            } catch {
                Log.error("loadApps failed: \(error.localizedDescription)")
                loadAppsError = error
                appState.setError(error)
            }
            isLoading = false
        }

        func showAppEditor(_ dittoApp: DittoConfigForDatabase) {
            dittoAppToEdit = dittoApp
            isPresented = true
        }

        func showQRCode(_ config: DittoConfigForDatabase) async {
            let favorites = await (try? favoritesRepository.loadFavorites(for: config.databaseId)) ?? []
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
                    _ = try? await favoritesRepository.loadFavorites(for: config.databaseId)
                    for item in favorites {
                        let fav = DittoQueryHistory(
                            id: UUID().uuidString,
                            query: item.q,
                            createdDate: Date.now.ISO8601Format()
                        )
                        do {
                            try await favoritesRepository.saveFavorite(fav)
                        } catch {
                            Log.warning("Failed to save imported favorite: \(error.localizedDescription)")
                        }
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
                let didSetupDitto = try await dittoManager
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

        // MARK: - Quickstart Download Flow (macOS)

        //
        // Phase 10c moved this orchestration off of `ContentView` itself so the
        // flow is unit-testable and the View stays a thin trigger. The driver
        // is `startQuickstartDownload()` — it routes either through the "no
        // connection" alert (if Ditto isn't configured) or directly to the
        // folder picker, then into `performDownload(...)`. Alert button
        // handlers call into the small `replaceExistingFolderAndDownload()` /
        // `chooseDifferentLocationAndDownload()` / `continueDownloadWithoutConfig()`
        // helpers so the View doesn't reach into VM state.

        #if os(macOS)
        var quickstartService = QuickstartDownloadService()
        var showNoConnectionAlert = false
        var showExistingFolderAlert = false
        var showProgressSheet = false
        var quickstartDestination: URL?
        var existingFolderURL: URL?
        @ObservationIgnored
        private var continueWithoutConfig = false

        func startQuickstartDownload() async {
            continueWithoutConfig = false
            if await hasDittoConnection() {
                openFolderPickerAndDownload(configureEnv: true)
            } else {
                showNoConnectionAlert = true
            }
        }

        /// Triggered by the "Continue Anyway" button on the no-connection alert.
        func continueDownloadWithoutConfig() async {
            continueWithoutConfig = true
            openFolderPickerAndDownload(configureEnv: false)
        }

        /// Triggered by the "Replace" button on the folder-exists alert.
        func replaceExistingFolderAndDownload() async {
            guard let existing = existingFolderURL,
                  let dest = quickstartDestination else { return }
            try? quickstartService.removeExistingFolder(at: existing)
            let configureEnv = await hasDittoConnection() && !continueWithoutConfig
            await performDownload(to: dest, configureEnv: configureEnv)
        }

        /// Triggered by the "Choose Different Location" button on the folder-exists alert.
        func chooseDifferentLocationAndDownload() async {
            let configureEnv = await hasDittoConnection() && !continueWithoutConfig
            openFolderPickerAndDownload(configureEnv: configureEnv)
        }

        /// Returns `true` when both `dittoSelectedApp` and
        /// `dittoSelectedAppConfig` are populated — i.e. a database is fully
        /// hydrated and ready for the quickstart `.env` configurator to read
        /// from. Falls back to `false` on any partial state.
        private func hasDittoConnection() async -> Bool {
            let hasApp = await dittoManager.dittoSelectedApp != nil
            let hasAppConfig = await dittoManager.dittoSelectedAppConfig != nil
            return hasApp && hasAppConfig
        }

        private func openFolderPickerAndDownload(configureEnv: Bool) {
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

            // Existing-folder collision → surface the "Replace / Choose
            // Different Location / Cancel" alert instead of overwriting.
            if let existing = quickstartService.existingQuickstartFolder(in: selectedURL) {
                existingFolderURL = existing
                showExistingFolderAlert = true
                return
            }

            Task { await performDownload(to: selectedURL, configureEnv: configureEnv) }
        }

        private func performDownload(to destination: URL, configureEnv: Bool) async {
            quickstartService.reset()
            showProgressSheet = true

            do {
                let extractedDir = try await quickstartService.downloadAndExtract(to: destination)

                if configureEnv, let config = await dittoManager.dittoSelectedAppConfig {
                    quickstartService.updateStatus("Configuring .env files...")
                    quickstartService.configureEnvFiles(
                        in: extractedDir,
                        databaseId: config.databaseId,
                        token: config.token,
                        authUrl: config.authUrl
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

                showProgressSheet = false

                let projects = quickstartService.projects
                WindowController.showQuickstartBrowser(
                    projects: projects,
                    isConfigured: configureEnv,
                    directory: extractedDir
                )
            } catch {
                quickstartService.setError(error.localizedDescription)
                // Progress sheet stays open showing the error — user clicks OK
                // to dismiss; `interactiveDismissDisabled` is gated on
                // `quickstartService.hasError` so dismissal is allowed here.
            }
        }
        #endif
    }
}

#Preview {
    ContentView()
        .environment(DittoConfigForDatabase.new())
}
