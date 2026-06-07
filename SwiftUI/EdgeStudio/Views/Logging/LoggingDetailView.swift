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

            logList
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
            guard !Task.isCancelled else { return }
            cachedFilteredEntries = computeFilteredEntries()
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
                // Level chips
                ForEach([DittoLogLevel.error, .warning, .info, .debug, .verbose], id: \.self) { level in
                    levelChip(level)
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
                if enabled { dateFilterEnd = Date.now }
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
                        LogEntryRowView(entry: entry)
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
                                    defer { if didStartAccess { url.stopAccessingSecurityScopedResource() } }
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
            dateEnd: dateFilterEnd
        )
    }

    private func computeFilteredEntries() -> [LogEntry] {
        let filtered = activeSourceEntries.filter { entry in
            if isDateFilterEnabled {
                guard LogEntry.isWithinDateRange(entry, start: dateFilterStart, end: dateFilterEnd) else { return false }
            }
            guard selectedLevels.contains(entry.level) else { return false }
            if capture.selectedSource == .dittoSDK || capture.selectedSource == .imported,
               selectedComponent != .all,
               entry.component != selectedComponent { return false }
            if !searchText.isEmpty {
                // Case-insensitive substring match without the per-entry
                // `lowercased()` allocation.
                guard entry.message.range(of: searchText, options: .caseInsensitive) != nil else { return false }
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
