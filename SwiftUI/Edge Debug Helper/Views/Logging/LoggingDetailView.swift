import DittoSwift
import SwiftUI
import UniformTypeIdentifiers

/// The main logging detail view, accessible from the Logging sidebar item.
struct LoggingDetailView: View {
    @EnvironmentObject var appState: AppState
    @State private var capture = DittoLogCaptureService.shared

    // MARK: - Filter State

    @State private var selectedSource: SourceTab = .dittoSDK
    @State private var selectedLevels: Set<DittoLogLevel> = [.error, .warning, .info, .debug, .verbose]
    @State private var selectedComponent: LogComponent = .all
    @State private var searchText = ""
    @State private var isDateFilterEnabled = false
    @State private var dateFilterStart: Date = Calendar.current.startOfDay(for: Date())
    @State private var dateFilterEnd = Date()

    // MARK: - Import State

    #if os(macOS)
    @State private var isShowingImportPanel = false
    #endif

    // MARK: - Source tabs

    enum SourceTab: String, CaseIterable {
        case dittoSDK = "Ditto SDK"
        case application = "App Logs"
        case imported = "Imported"
    }

    // MARK: - Display Cap

    private let maxDisplayedEntries = 200

    // MARK: - Toolbar State

    @State private var activeLogLevel = "info"

    var body: some View {
        VStack(spacing: 0) {
            // ── Toolbar ─────────────────────────────────────────────────────
            toolbarRow

            Divider()

            // ── Source Selector ──────────────────────────────────────────────
            sourceRow

            Divider()

            // ── Level & Component Filters ────────────────────────────────────
            filterRow

            Divider()

            // ── Date Range Filter ─────────────────────────────────────────────
            dateFilterRow

            Divider()

            // ── Log List ─────────────────────────────────────────────────────
            logList

            Divider()

            // ── Footer ───────────────────────────────────────────────────────
            footerRow
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
                        if let config = await DittoManager.shared.dittoSelectedAppConfig {
                            try? await DittoManager.shared.changeDittoLogLevel(newLevel, for: config)
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
            ForEach(SourceTab.allCases, id: \.self) { tab in
                Button {
                    selectedSource = tab
                } label: {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(selectedSource == tab ? Color.accentColor : Color.secondary.opacity(0.4))
                            .frame(width: 7, height: 7)
                        Text(tab.rawValue)
                            .font(.caption)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(selectedSource == tab ? Color.accentColor.opacity(0.12) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)

                if tab != SourceTab.allCases.last {
                    Divider().frame(height: 16)
                }
            }

            // Imported label + clear button
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
                if selectedSource == .dittoSDK || selectedSource == .imported {
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
                if enabled { dateFilterEnd = Date() }
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
                    dateFilterStart = Calendar.current.startOfDay(for: Date())
                    dateFilterEnd = Date()
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
            } else if filteredEntries.isEmpty {
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
                    ForEach(filteredEntries) { entry in
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
        HStack(spacing: 12) {
            let displayed = filteredEntries.count
            let total = activeSourceEntries.count
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
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            #if os(macOS)
            Button {
                isShowingImportPanel = true
            } label: {
                Label("Import External Logs…", systemImage: "folder.badge.plus")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .fileImporter(
                isPresented: $isShowingImportPanel,
                allowedContentTypes: [UTType.folder],
                allowsMultipleSelection: false
            ) { result in
                if case let .success(urls) = result, let url = urls.first {
                    Task { await capture.importFromDirectory(url) }
                }
            }
            #endif

            Button {
                switch selectedSource {
                case .dittoSDK:
                    capture.clearLive()
                    capture.clearHistorical()
                case .application:
                    LoggingService.shared.clearAllLogs()
                    Task { await capture.loadAppLogs() }
                case .imported:
                    capture.clearImported()
                }
            } label: {
                Label("Clear", systemImage: "trash")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.red)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Filtered Entries

    private var activeSourceEntries: [LogEntry] {
        switch selectedSource {
        case .dittoSDK:
            return capture.historicalEntries + capture.liveEntries
        case .application:
            return capture.appEntries
        case .imported:
            return capture.importedEntries
        }
    }

    private var filteredEntries: [LogEntry] {
        let searchLower = searchText.isEmpty ? "" : searchText.lowercased()
        let filtered = activeSourceEntries.filter { entry in
            if isDateFilterEnabled {
                guard LogEntry.isWithinDateRange(entry, start: dateFilterStart, end: dateFilterEnd) else { return false }
            }
            guard selectedLevels.contains(entry.level) else { return false }
            if selectedSource == .dittoSDK || selectedSource == .imported,
               selectedComponent != .all,
               entry.component != selectedComponent { return false }
            if !searchLower.isEmpty {
                guard entry.message.lowercased().contains(searchLower) else { return false }
            }
            return true
        }
        return Array(filtered.suffix(maxDisplayedEntries))
    }
}
