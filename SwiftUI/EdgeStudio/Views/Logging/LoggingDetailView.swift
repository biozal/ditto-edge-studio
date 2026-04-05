import DittoSwift
import SwiftUI
import UniformTypeIdentifiers

/// The main logging detail view, accessible from the Logging sidebar item.
struct LoggingDetailView: View {
    @EnvironmentObject var appState: AppState
    @State private var capture = DittoLogCaptureService.shared

    // MARK: - Filter State

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

    // MARK: - Display Cap

    private let maxDisplayedEntries = 200

    /// Source tabs visible in the current platform.
    /// The Imported tab is macOS-only because log file import uses a macOS file picker.
    private var visibleSourceTabs: [LoggingSourceTab] {
        #if os(macOS)
        return LoggingSourceTab.allCases
        #else
        return [.dittoSDK, .connectionRequests, .transportConditions, .application]
        #endif
    }

    // MARK: - Footer State

    @State private var isFooterCollapsed = false

    // MARK: - Toolbar State

    @State private var activeLogLevel = "info"

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
            ForEach(visibleSourceTabs, id: \.self) { tab in
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

                if tab != visibleSourceTabs.last {
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

    private var filteredEntries: [LogEntry] {
        let searchLower = searchText.isEmpty ? "" : searchText.lowercased()
        let filtered = activeSourceEntries.filter { entry in
            if isDateFilterEnabled {
                guard LogEntry.isWithinDateRange(entry, start: dateFilterStart, end: dateFilterEnd) else { return false }
            }
            guard selectedLevels.contains(entry.level) else { return false }
            if capture.selectedSource == .dittoSDK || capture.selectedSource == .imported,
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
