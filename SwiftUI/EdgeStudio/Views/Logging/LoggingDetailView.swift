import DittoSwift
import SwiftUI
import UniformTypeIdentifiers

/// The main logging detail view, accessible from the Logging sidebar item.
struct LoggingDetailView: View {
    @Environment(AppState.self) var appState
    @State private var capture = DittoLogCaptureService.shared

    // MARK: - Filter State

    @State private var selectedLevels: Set<DittoLogLevel> = [.error, .warning, .info, .debug, .verbose]
    @State private var selectedComponent: LogComponent = .all
    @State private var searchText = ""
    @State private var isDateFilterEnabled = false
    @State private var dateFilterStart: Date = Calendar.current.startOfDay(for: Date.now)
    @State private var dateFilterEnd = Date.now

    // MARK: - Import / Export State

    #if os(macOS)
    @State private var isShowingImportPanel = false
    @State private var isShowingExportPanel = false
    @State private var exportError: String?
    @State private var isShowingExportError = false
    #endif

    // MARK: - Display Cap

    private let maxDisplayedEntries = 200

    /// Source tabs visible in the current platform.
    /// The Imported tab is macOS-only because log file import uses a macOS file picker.
    /// Platform-constant — computed once rather than rebuilt on every body render.
    private static let visibleSourceTabs: [LoggingSourceTab] = {
        #if os(macOS)
        return LoggingSourceTab.allCases
        #else
        return [.dittoSDK, .connectionRequests, .transportConditions, .application]
        #endif
    }()

    // MARK: - Footer State

    @State private var isFooterCollapsed = false

    // MARK: - Toolbar State

    @State private var activeLogLevel = "info"

    // MARK: - Log Pattern Analysis (VS Code extension log-analyzer parity)

    @State private var patternStore = LogPatternStore()
    @State private var isShowingPatternManager = false
    @State private var patternProblems: [LogPatternEngine.Match] = []
    @State private var analytics = LogAnalytics()
    /// Entry ids the Problems / Critical filter tabs can list. Derived off the
    /// main actor alongside the pattern scan rather than rebuilt per body pass.
    @State private var problemEntryIDs: Set<UUID> = []
    @State private var criticalEntryIDs: Set<UUID> = []
    @State private var userTagsByID: [UUID: [String]] = [:]

    // MARK: - Analyzer Filter Tab

    @State private var selectedFilterTab: LogFilterTab = .all

    // MARK: - Pause

    /// Freezes the *display* only. Ingestion keeps running into the capture
    /// service's (capped) buffers, exactly as the VS Code analyzer's pause
    /// does, so nothing is lost while paused and resuming shows the full
    /// picture rather than a gap. Included in both task ids so toggling it
    /// re-fires them: resuming has to recompute immediately, not wait for the
    /// next log line.
    @State private var isPaused = false

    // MARK: - Row Expansion

    /// The one open row, if any. Owned here rather than in `LogEntryRowView`
    /// because the row cannot reach the unfiltered buffer that context comes
    /// from, and because one drawer at a time keeps the list readable.
    @State private var expandedEntryID: UUID?
    @State private var expandedContext: LogEntryContext = .empty

    // MARK: - Filtered Entry Cache (debounced)

    @State private var cachedFilteredEntries: [LogEntry] = []

    var body: some View {
        VStack(spacing: 0) {
            toolbarRow

            Divider()

            sourceRow

            Divider()

            filterRow

            Divider()

            dateFilterRow

            Divider()

            LogAnalyticsSection(analytics: analytics)

            Divider()

            LogProblemsSection(problems: patternProblems) { entry in
                // Jump the table to the matched line via the search filter.
                searchText = entry.message
            }

            Divider()

            LogFilterTabs(selection: $selectedFilterTab, counts: analytics.counts)

            // The list is the only child that should absorb slack height. The
            // priority keeps it from being squeezed by the analytics section,
            // and — with that section now internally scrollable — keeps the
            // detail column's own minimum height small, which matters because
            // the window is sized by `.windowResizability(.contentSize)`.
            logList
                .layoutPriority(1)
        }
        .overlay(alignment: .bottom) {
            footerRow
                .padding(.bottom, 12)
        }
        .task {
            // Load active config log level
            if let config = await DittoManager.shared.dittoSelectedAppConfig {
                activeLogLevel = config.logLevel
            }
            // Start live capture if we have a persistence dir
            if let dir = await DittoManager.shared.activePersistenceDirectory {
                capture.startLiveCapture(persistenceDir: dir)
                await capture.loadHistoricalLogs(from: dir)
            }
            await capture.loadAppLogs()
        }
        .task(id: currentFilterInputs) {
            // Debounce filter recompute by 150ms — coalesces fast keystrokes
            // and bursty live-log appends into one filter pass.
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled, !isPaused else { return }
            let source = activeSourceEntries
            let filtered = computeFilteredEntries(from: source)
            cachedFilteredEntries = filtered
            refreshExpandedContext(visible: filtered, source: source)
        }
        .task(id: patternScanInputs) {
            // Throttled pattern scan: at most ~2 passes/sec, off-main actor,
            // window capped at LogPatternEngine.maxScanEntries. Mirrored from
            // the Android sample(1000) scan loop.
            //
            // The analytics snapshot is produced in the same detached pass and
            // over the *same* window as the scan. Computing it over the full
            // buffer instead would report a line total the problem counts were
            // never measured against.
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, !isPaused else { return }
            let engine = LogPatternEngine(patterns: patternStore.patterns)
            let entries = activeSourceEntries
            let result = await Task.detached(priority: .utility) { () -> LogScanResult in
                let window = entries.count > LogPatternEngine.maxScanEntries
                    ? Array(entries.suffix(LogPatternEngine.maxScanEntries))
                    : entries
                let matches = engine.scanAll(window)
                var problemIDs = Set<UUID>()
                var criticalIDs = Set<UUID>()
                var tags: [UUID: Set<String>] = [:]
                for match in matches {
                    problemIDs.insert(match.entry.id)
                    if match.pattern.severity >= 5 {
                        criticalIDs.insert(match.entry.id)
                    }
                    if let tag = match.pattern.userTag {
                        tags[match.entry.id, default: []].insert(tag)
                    }
                }
                return LogScanResult(
                    matches: matches,
                    analytics: LogAnalytics.compute(entries: window, matches: matches),
                    problemIDs: problemIDs,
                    criticalIDs: criticalIDs,
                    userTags: tags.mapValues { $0.sorted() }
                )
            }.value
            guard !Task.isCancelled else { return }
            patternProblems = result.matches
            analytics = result.analytics
            problemEntryIDs = result.problemIDs
            criticalEntryIDs = result.criticalIDs
            userTagsByID = result.userTags
        }
        .sheet(isPresented: $isShowingPatternManager) {
            LogPatternManagerView(store: patternStore)
        }
        .onDisappear {
            capture.stopLiveCapture()
        }
    }

    // MARK: - Toolbar

    private var toolbarRow: some View {
        HStack(spacing: 12) {
            Text("Logs")
                .font(.headline)

            Spacer()

            // SDK Log Level picker (changes active level immediately)
            HStack(spacing: 4) {
                Text("SDK Level:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("", selection: $activeLogLevel) {
                    Text("Error").tag("error")
                    Text("Warning").tag("warning")
                    Text("Info").tag("info")
                    Text("Debug").tag("debug")
                    Text("Verbose").tag("verbose")
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: 100)
                .onChange(of: activeLogLevel) { _, newLevel in
                    Task {
                        do {
                            if let config = await DittoManager.shared.dittoSelectedAppConfig {
                                // Mutate the shared config on the MainActor (this
                                // onChange runs on the MainActor), then hand it to
                                // the actor only for persistence + live apply.
                                config.logLevel = newLevel
                                try await DittoManager.shared.changeDittoLogLevel(newLevel, for: config)
                            }
                        } catch {
                            Log.error("Failed to change log level to '\(newLevel)': \(error.localizedDescription)")
                            appState.setError(error)
                        }
                    }
                }
            }

            Button {
                Task {
                    if let dir = await DittoManager.shared.activePersistenceDirectory {
                        await capture.loadHistoricalLogs(from: dir)
                    }
                    await capture.loadAppLogs()
                }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .help("Reload log files from disk")

            Button {
                isPaused.toggle()
            } label: {
                Label(isPaused ? "Resume" : "Pause", systemImage: isPaused ? "play.fill" : "pause.fill")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .help(isPaused ? "Resume live log updates" : "Freeze the view; capture continues in the background")
            .accessibilityIdentifier("LogPauseToolbarButton")

            Button {
                isShowingPatternManager = true
            } label: {
                Label("Patterns", systemImage: "slider.horizontal.3")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .help("Manage log patterns (problem matching)")
            .accessibilityIdentifier("LogPatternsToolbarButton")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Source Row

    private var sourceRow: some View {
        HStack(spacing: 0) {
            ForEach(Self.visibleSourceTabs, id: \.self) { tab in
                Button {
                    capture.selectedSource = tab
                } label: {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(capture.selectedSource == tab ? Color.green : Color.secondary.opacity(0.4))
                            .frame(width: 7, height: 7)
                        Text(tab.rawValue)
                            .font(.caption)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(capture.selectedSource == tab ? Color.accentColor.opacity(0.12) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)

                if tab != Self.visibleSourceTabs.last {
                    Divider().frame(height: 16)
                }
            }

            // Imported label + clear button (macOS only — import is not available on iOS)
            #if os(macOS)
            if !capture.importedLabel.isEmpty {
                Text("[\(capture.importedLabel)]")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)

                Button {
                    capture.clearImported()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            #endif

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    // MARK: - Filter Row

    private var filterRow: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                // Level chips. Hidden while a filter tab already constrains the
                // level — an Errors tab with the ERR chip deselected would show
                // nothing and read as a broken filter rather than two filters
                // contradicting each other.
                if !selectedFilterTab.overridesLevelChips {
                    ForEach([DittoLogLevel.error, .warning, .info, .debug, .verbose], id: \.self) { level in
                        levelChip(level)
                    }
                } else {
                    Text("Level filtered by the \(selectedFilterTab.label) tab")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Component filter (SDK source only)
                if capture.selectedSource == .dittoSDK || capture.selectedSource == .imported {
                    Picker("Component", selection: $selectedComponent) {
                        ForEach(LogComponent.allCases, id: \.self) { comp in
                            Text(comp.rawValue).tag(comp)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(maxWidth: 110)
                }
            }

            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                TextField("Search…", text: $searchText)
                    .font(.caption)
                #if os(macOS)
                    .textFieldStyle(.roundedBorder)
                #endif

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func levelChip(_ level: DittoLogLevel) -> some View {
        let isSelected = selectedLevels.contains(level)
        Button {
            if isSelected {
                selectedLevels.remove(level)
            } else {
                selectedLevels.insert(level)
            }
        } label: {
            Text(level.shortName)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(isSelected ? levelChipColor(level).opacity(0.18) : Color.secondary.opacity(0.08))
                .foregroundStyle(isSelected ? levelChipColor(level) : Color.secondary)
                .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
    }

    private func levelChipColor(_ level: DittoLogLevel) -> Color {
        switch level {
        case .error: return .red
        case .warning: return .orange
        case .info: return .blue
        case .debug: return .secondary
        case .verbose: return .secondary
        @unknown default: return .secondary
        }
    }

    // MARK: - Date Filter Row

    private var dateFilterRow: some View {
        HStack(spacing: 8) {
            Toggle(isOn: $isDateFilterEnabled) {
                Label("Date Range", systemImage: "calendar.badge.clock")
                    .font(.caption)
            }
            .toggleStyle(.button)
            .buttonStyle(.borderless)
            .font(.caption)
            .onChange(of: isDateFilterEnabled) { _, enabled in
                if enabled {
                    dateFilterEnd = Date.now
                }
            }

            if isDateFilterEnabled {
                DatePicker(
                    "",
                    selection: $dateFilterStart,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .labelsHidden()
                .datePickerStyle(.compact)
                .font(.caption)

                Text("–")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                DatePicker(
                    "",
                    selection: $dateFilterEnd,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .labelsHidden()
                .datePickerStyle(.compact)
                .font(.caption)

                Button {
                    isDateFilterEnabled = false
                    dateFilterStart = Calendar.current.startOfDay(for: Date.now)
                    dateFilterEnd = Date.now
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help("Clear date range filter")
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    // MARK: - Log List

    private var logList: some View {
        Group {
            if capture.isLoading {
                VStack(spacing: 12) {
                    Spacer()
                    ProgressView("Loading logs…")
                        .font(.subheadline)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else if cachedFilteredEntries.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "doc.plaintext")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("No log entries")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("Adjust filters or perform actions to generate logs.")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .padding()
            } else {
                List {
                    ForEach(cachedFilteredEntries) { entry in
                        LogEntryRowView(
                            entry: entry,
                            userTags: userTagsByID[entry.id] ?? [],
                            isExpanded: expandedEntryID == entry.id,
                            // Only the open row carries context; the rest cost
                            // nothing to render.
                            context: expandedEntryID == entry.id ? expandedContext : .empty,
                            onToggleExpanded: { toggleExpansion(for: entry) }
                        )
                    }
                }
                .listStyle(.plain)
                #if os(macOS)
                    .scrollContentBackground(.hidden)
                #endif
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Footer

    private var footerRow: some View {
        HStack {
            if isFooterCollapsed {
                Spacer()
                GlassEffectContainer {
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            isFooterCollapsed = false
                        }
                    } label: {
                        Image(systemName: "chevron.left.chevron.left.dotted")
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                    .glassEffect(in: RoundedRectangle(cornerRadius: 20))
                }
                .subtleShadow()
            } else {
                GlassEffectContainer {
                    HStack(spacing: 12) {
                        let displayed = cachedFilteredEntries.count
                        let total = activeSourceEntryCount
                        let isFiltered = isDateFilterEnabled || !searchText.isEmpty || selectedComponent != .all
                        let footerLabel: String = {
                            if isFiltered {
                                return "\(displayed) entries"
                            } else if displayed < total {
                                return "Showing \(displayed) of \(total) (most recent)"
                            } else {
                                return "\(displayed) entries"
                            }
                        }()
                        Text(footerLabel)
                            .font(.system(size: 14, design: .monospaced))
                            .foregroundStyle(.secondary)

                        Spacer()

                        // Import — macOS only, icon only
                        #if os(macOS)
                        Button { isShowingImportPanel = true } label: {
                            Image(systemName: "folder.badge.plus")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Import External Logs…")
                        .fileImporter(
                            isPresented: $isShowingImportPanel,
                            allowedContentTypes: [UTType.folder],
                            allowsMultipleSelection: false
                        ) { result in
                            if case let .success(urls) = result, let url = urls.first {
                                Task { await capture.importFromDirectory(url) }
                            }
                        }

                        // Export — App Logs and Ditto SDK sources have on-disk
                        // files. App Logs copies the rolling CocoaLumberjack
                        // files (see LoggingService); Ditto SDK copies the
                        // `.log` / `.log.gz` files the SDK writes inside the
                        // active database's persistence directory. The other
                        // sources hold in-memory entries only and don't have
                        // files to copy.
                        if capture.selectedSource == .application || capture.selectedSource == .dittoSDK {
                            Button { isShowingExportPanel = true } label: {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help(capture.selectedSource == .dittoSDK ? "Export Ditto SDK Logs…" : "Export App Logs…")
                            .fileImporter(
                                isPresented: $isShowingExportPanel,
                                allowedContentTypes: [UTType.folder],
                                allowsMultipleSelection: false
                            ) { result in
                                guard case let .success(urls) = result, let url = urls.first else { return }
                                let source = capture.selectedSource
                                Task { @MainActor in
                                    let didStartAccess = url.startAccessingSecurityScopedResource()
                                    defer {
                                        if didStartAccess {
                                            url.stopAccessingSecurityScopedResource()
                                        }
                                    }
                                    do {
                                        switch source {
                                        case .application:
                                            try LoggingService.shared.exportLogs(to: url)
                                        case .dittoSDK:
                                            try await exportDittoSDKLogs(to: url)
                                        default:
                                            break
                                        }
                                    } catch {
                                        exportError = error.localizedDescription
                                        isShowingExportError = true
                                    }
                                }
                            }
                            .alert("Export Failed", isPresented: $isShowingExportError, presenting: exportError) { _ in
                                Button("OK", role: .cancel) {}
                            } message: { message in
                                Text(message)
                            }
                        }
                        #endif

                        // Clear — icon only, red tint
                        Button {
                            switch capture.selectedSource {
                            case .dittoSDK:
                                capture.clearLive()
                                capture.clearHistorical()
                            case .application:
                                LoggingService.shared.clearAllLogs()
                                Task { await capture.loadAppLogs() }
                            case .imported:
                                capture.clearImported()
                            case .transportConditions:
                                capture.clearTransportEntries()
                            case .connectionRequests:
                                capture.clearConnectionRequestEntries()
                            }
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 14))
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                        .help("Clear \(capture.selectedSource.rawValue) logs")

                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                isFooterCollapsed = true
                            }
                        } label: {
                            Image(systemName: "chevron.right.dotted.chevron.right")
                                .font(.system(size: 16))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Collapse toolbar")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .glassEffect(in: RoundedRectangle(cornerRadius: 20))
                }
                .subtleShadow()
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isFooterCollapsed)
    }

    // MARK: - Filtered Entries

    private var activeSourceEntries: [LogEntry] {
        switch capture.selectedSource {
        case .dittoSDK:
            return capture.historicalEntries + capture.liveEntries
        case .application:
            return capture.appEntries
        case .imported:
            return capture.importedEntries
        case .transportConditions:
            return capture.transportEntries
        case .connectionRequests:
            return capture.connectionRequestEntries
        }
    }

    /// O(1) per-source entry count — avoids the array concat that
    /// `activeSourceEntries` does for `.dittoSDK`. Used in the footer label
    /// and as a cheap filter-input invalidator.
    private var activeSourceEntryCount: Int {
        switch capture.selectedSource {
        case .dittoSDK:
            return capture.historicalEntries.count + capture.liveEntries.count
        case .application:
            return capture.appEntries.count
        case .imported:
            return capture.importedEntries.count
        case .transportConditions:
            return capture.transportEntries.count
        case .connectionRequests:
            return capture.connectionRequestEntries.count
        }
    }

    /// Inputs that trigger a pattern rescan: source, buffer size, catalog revision.
    private struct PatternScanInputs: Equatable {
        let selectedSource: LoggingSourceTab
        let entryCount: Int
        let patternRevision: Int
        let isPaused: Bool
    }

    private var patternScanInputs: PatternScanInputs {
        PatternScanInputs(
            selectedSource: capture.selectedSource,
            entryCount: activeSourceEntryCount,
            patternRevision: patternStore.revision,
            isPaused: isPaused
        )
    }

    /// All inputs that affect the filtered output. When this changes,
    /// `.task(id:)` cancels any in-flight debounce and schedules a fresh one.
    private struct FilterInputs: Equatable {
        let selectedSource: LoggingSourceTab
        let entryCount: Int
        let levels: Set<DittoLogLevel>
        let component: LogComponent
        let searchText: String
        let dateEnabled: Bool
        let dateStart: Date
        let dateEnd: Date
        let filterTab: LogFilterTab
        let isPaused: Bool
        /// Proxy for "the scan produced new results" — the tab predicates read
        /// the id sets, so the filtered list has to be rebuilt when they change.
        let problemCount: Int
        let criticalCount: Int
    }

    private var currentFilterInputs: FilterInputs {
        FilterInputs(
            selectedSource: capture.selectedSource,
            entryCount: activeSourceEntryCount,
            levels: selectedLevels,
            component: selectedComponent,
            searchText: searchText,
            dateEnabled: isDateFilterEnabled,
            dateStart: dateFilterStart,
            dateEnd: dateFilterEnd,
            filterTab: selectedFilterTab,
            isPaused: isPaused,
            problemCount: problemEntryIDs.count,
            criticalCount: criticalEntryIDs.count
        )
    }

    /// Opens `entry`'s drawer (closing any other), or closes it if it is
    /// already open. Context is resolved against the **unfiltered** source
    /// buffer — see `LogEntryContext` for why the filtered list would be
    /// useless here.
    private func toggleExpansion(for entry: LogEntry) {
        if expandedEntryID == entry.id {
            expandedEntryID = nil
            expandedContext = .empty
        } else {
            expandedEntryID = entry.id
            expandedContext = LogEntryContext.around(entry.id, in: activeSourceEntries)
        }
    }

    /// Keeps the open drawer honest as the buffer moves underneath it.
    ///
    /// Two things go wrong without this. Expanding the newest row captures an
    /// empty `after` context, and it would stay empty forever even as new lines
    /// arrived. And when a filter change drops the open row from the list,
    /// `expandedEntryID` would dangle — harmless on screen, but it would
    /// silently re-open the row if the filter later let it back in.
    private func refreshExpandedContext(visible: [LogEntry], source: [LogEntry]) {
        guard let expandedEntryID else { return }
        guard visible.contains(where: { $0.id == expandedEntryID }) else {
            self.expandedEntryID = nil
            expandedContext = .empty
            return
        }
        expandedContext = LogEntryContext.around(expandedEntryID, in: source)
    }

    /// - Parameter source: the active source buffer. Passed in rather than
    ///   read from `activeSourceEntries` so one debounce pass materialises it
    ///   once — for the Ditto SDK source that property concatenates the
    ///   historical and live arrays, which is up to 20k entries of copying and
    ///   ARC traffic per call.
    private func computeFilteredEntries(from source: [LogEntry]) -> [LogEntry] {
        let filtered = source.filter { entry in
            if isDateFilterEnabled {
                guard LogEntry.isWithinDateRange(entry, start: dateFilterStart, end: dateFilterEnd) else { return false }
            }
            guard selectedFilterTab.accepts(
                entry, problemIDs: problemEntryIDs, criticalIDs: criticalEntryIDs
            ) else { return false }
            // The level chips are hidden while a tab constrains the level, so
            // they must not also filter — a stale chip selection would silently
            // subtract rows from a tab the user just picked.
            if !selectedFilterTab.overridesLevelChips {
                guard selectedLevels.contains(entry.level) else { return false }
            }
            if capture.selectedSource == .dittoSDK || capture.selectedSource == .imported,
               selectedComponent != .all,
               entry.component != selectedComponent
            {
                return false
            }
            if !searchText.isEmpty {
                // Case-insensitive substring match without the per-entry
                // `lowercased()` allocation. User tags are part of the search
                // haystack (parity with the VS Code analyzer's webview search).
                let inTags = userTagsByID[entry.id]?.contains {
                    $0.range(of: searchText, options: .caseInsensitive) != nil
                } ?? false
                guard entry.message.range(of: searchText, options: .caseInsensitive) != nil || inTags else {
                    return false
                }
            }
            return true
        }
        return Array(filtered.suffix(maxDisplayedEntries))
    }

    #if os(macOS)
    /// Copies the SDK-emitted `.log` / `.log.gz` files from the active
    /// database's persistence directory into the user-chosen folder. Looks
    /// in `ditto_logs/` first (current SDK) and falls back to `logs/` for
    /// older SDK layouts.
    private func exportDittoSDKLogs(to destinationURL: URL) async throws {
        guard let persistenceDir = await DittoManager.shared.activePersistenceDirectory else {
            throw NSError(
                domain: "EdgeStudio.LoggingDetailView",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "No active database — open a database first."]
            )
        }

        let fileManager = FileManager.default
        let sourceDir: URL? = ["ditto_logs", "logs"]
            .map { persistenceDir.appendingPathComponent($0) }
            .first { fileManager.fileExists(atPath: $0.path) }

        guard let sourceDir else {
            throw NSError(
                domain: "EdgeStudio.LoggingDetailView",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "No SDK log directory found under \(persistenceDir.path)"]
            )
        }

        let contents = try fileManager.contentsOfDirectory(at: sourceDir, includingPropertiesForKeys: nil)
        let logFiles = contents.filter {
            $0.pathExtension == "log" || $0.lastPathComponent.hasSuffix(".log.gz")
        }

        guard !logFiles.isEmpty else {
            throw NSError(
                domain: "EdgeStudio.LoggingDetailView",
                code: -3,
                userInfo: [NSLocalizedDescriptionKey: "No log files found in \(sourceDir.path)"]
            )
        }

        for fileURL in logFiles {
            let destFileURL = destinationURL.appendingPathComponent(fileURL.lastPathComponent)
            if fileManager.fileExists(atPath: destFileURL.path) {
                try fileManager.removeItem(at: destFileURL)
            }
            try fileManager.copyItem(at: fileURL, to: destFileURL)
        }

        Log.info("Exported \(logFiles.count) SDK log files from \(sourceDir.path) to \(destinationURL.path)")
    }
    #endif
}
