import SwiftUI

/// Namespace filter for the system-metrics table.
enum SystemMetricsNamespaceFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case network = "Network"
    case store = "Store"
    case sync = "Sync"
    case other = "Other"

    var id: String {
        rawValue
    }

    var prefixes: [String]? {
        switch self {
        case .all: return nil
        case .network: return ["ditto.network."]
        case .store: return ["ditto.backend."]
        case .sync: return ["ditto.sync.", "ditto.replication."]
        case .other: return []
        }
    }

    func matches(_ sample: SystemMetricSample) -> Bool {
        switch self {
        case .all:
            return true
        case .other:
            return Self.allCases.compactMap(\.prefixes).flatMap(\.self)
                .contains { sample.key.hasPrefix($0) } == false
        default:
            return prefixes?.contains { sample.key.hasPrefix($0) } ?? false
        }
    }
}

/// The `system:metrics` screen (SDK 5.1) — parity with the VS Code extension's
/// System Metrics panel and the Android `SystemMetricsScreen`.
///
/// Every series the SDK reports renders as a row: the metric name (with the
/// `ditto.` prefix dropped) and its labels on the left, the since-connect total
/// and the last poll's delta on the right. On each row an **info** button
/// expands the series' details and a **pin** button lifts it into a collapsible
/// **Pinned** accordion above the filters — pins persist per database, so a
/// troubleshooting set survives leaving the screen and relaunching the app. A
/// namespace segment control and a search field narrow the master list (the
/// pinned section is deliberately exempt from both: it is the user's stable set).
struct SystemMetricsDetailView: View {
    /// Database the pins belong to (`DittoConfigForDatabase._id`).
    let databaseId: String

    @State private var service = SystemMetricsService()
    @State private var namespaceFilter = SystemMetricsNamespaceFilter.all
    /// Free-text filter over the master list, composed with `namespaceFilter`.
    @State private var query = ""
    /// Series whose details are expanded, by `SystemMetricSeriesRef.id`.
    @State private var expandedSeriesIDs: Set<String> = []
    /// Pinned series in pin order. Loaded from `SystemMetricsPinStore` on appear;
    /// every edit writes the complete replacement list straight back.
    @State private var pins: [SystemMetricSeriesRef] = []
    /// Pinned accordion open/closed — session-local, like the VS Code panel's.
    @State private var pinnedExpanded = true
    /// Apple Music-style reorder mode for the Pinned accordion. Reordering is an
    /// explicit mode rather than a bare long-press-drag because on a touch screen
    /// the enclosing `ScrollView` wins that gesture — you get a scrolled page
    /// instead of a moved row. See `pinnedReorderButton`.
    @State private var isReorderingPins = false
    /// Series id of the row being dragged, or `nil` when no drag is in flight.
    @State private var pinDragID: String?
    /// Row heights by series id. Rows differ (a label line, an expanded detail
    /// panel), so the swap threshold has to come from a measurement.
    @State private var pinRowHeights: [String: CGFloat] = [:]
    /// Vertical distance already absorbed by completed swaps, so the dragged row
    /// keeps tracking the finger instead of jumping a full row each time.
    @State private var pinDragConsumed: CGFloat = 0
    /// Live order during a drag. Committed on release; `pins` is `@State`, so
    /// unlike Android there is no write round-trip to wait out afterwards.
    @State private var workingPins: [SystemMetricSeriesRef]?

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var snapshot: SystemMetricsService.Snapshot {
        service.snapshot
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            // Locked while reordering: this is exactly the contention that made
            // drag-to-reorder impossible by touch, and disabling the scroll is
            // what hands the gesture to the row.
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    pinnedSection
                    filterRow
                    contentBody
                }
                .padding()
            }
            .scrollDisabled(isReorderingPins)
        }
        .task {
            pins = SystemMetricsPinStore.read(databaseId: databaseId)
            service.start()
        }
        .onDisappear { service.stop() }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            Text("System Metrics")
                .font(.title2)
                .bold()
            Spacer()
            if let polledAt = snapshot.polledAt {
                Text("Updated \(polledAt.formatted(date: .omitted, time: .standard))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button {
                Task { await service.refreshNow() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.glass)
            .clipShape(Circle())
            .help("Poll system:metrics now")
            .accessibilityIdentifier("SystemMetricsRefreshButton")
        }
        .padding(.horizontal)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    // MARK: - Filters

    /// Segment control plus search field. Side by side where there is room; the
    /// search box drops to its own line in a compact column, where an inline
    /// field would squeeze the five segments into unreadable slivers.
    @ViewBuilder
    private var filterRow: some View {
        if horizontalSizeClass == .compact {
            VStack(spacing: 8) {
                namespacePicker
                searchField
            }
        } else {
            HStack(spacing: 10) {
                Spacer(minLength: 0)
                namespacePicker
                Spacer(minLength: 0)
                searchField
                    .frame(width: 220)
            }
        }
    }

    private var namespacePicker: some View {
        DittoSegmentedPicker(
            options: SystemMetricsNamespaceFilter.allCases,
            selection: $namespaceFilter
        ) { $0.rawValue }
            .frame(maxWidth: 320)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Filter metrics…", text: $query)
                .textFieldStyle(.plain)
                .font(.callout)
            #if os(iOS)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            #endif
                .accessibilityIdentifier("SystemMetricsSearchField")
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(0.12))
        )
    }

    // MARK: - Body

    @ViewBuilder
    private var contentBody: some View {
        switch snapshot.status {
        case .settingDisabled:
            statusNote(
                "System metrics collection is off. Enable \"Collect system metrics\" in Settings — the SDK reads the setting only when a database opens, so it takes effect the next time you open one."
            )
        case .exporterDisabled:
            statusNote(
                "The SDK exporter wasn't enabled for this session. Close and re-open the database after enabling \"Collect system metrics\" in Settings."
            )
        case .noConnection:
            statusNote("No active database connection.")
        case let .error(message):
            statusNote("system:metrics read failed: \(message)", isError: true)
        case .idle:
            statusNote("Collecting — the first poll lands shortly after this screen opens…")
        case .ready:
            readyBody
        }
    }

    private func statusNote(_ text: String, isError: Bool = false) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(isError ? Color.red : .secondary)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var readyBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            divergenceBanner

            let filtered = snapshot.samples.filter {
                namespaceFilter.matches($0) && matchesQuery($0)
            }
            if filtered.isEmpty {
                statusNote(emptyListMessage)
            } else {
                ForEach(filtered, id: \.seriesID) { sample in
                    metricRow(sample)
                    Divider()
                }
            }

            footer
        }
    }

    private var emptyListMessage: String {
        if snapshot.samples.isEmpty {
            return "No metrics reported yet — they accumulate while this screen is visible."
        }
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "No metrics in this namespace." : "No metrics match \"\(trimmed)\"."
    }

    @ViewBuilder
    private var footer: some View {
        if let since = snapshot.since {
            let updated = snapshot.polledAt
                .map { " — updated \($0.formatted(date: .omitted, time: .standard))" } ?? ""
            Text(
                "Since \(since.formatted(date: .omitted, time: .shortened))\(updated) · polled every 5s. "
                    + "Totals accumulate per-read deltas — reading system:metrics flushes Ditto's counters."
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.top, 4)
        }
    }

    /// Case-insensitive substring over the metric key AND its label keys and
    /// values, so `ble` finds the `transport=ble` series and `dsoq` every dsoq
    /// metric. An empty query matches everything.
    private func matchesQuery(_ sample: SystemMetricSample) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return true }
        if sample.key.lowercased().contains(needle) {
            return true
        }
        return sample.labels.contains { key, value in
            key.lowercased().contains(needle) || value.lowercased().contains(needle)
        }
    }

    @ViewBuilder
    private var divergenceBanner: some View {
        // Summed across label sets, not `first`: dsoq counters are reported per
        // transport, so a single series' total is only part of the picture.
        let opened = total(forKey: "ditto.network.dsoq.connection.opened")
        let closed = total(forKey: "ditto.network.dsoq.connection.closed")
        if opened + closed > 0, opened != closed {
            Label(
                "dsoq connections opened (\(formatValue(opened))) ≠ closed (\(formatValue(closed))) — possible connection leak or handshake issue. Check Log Analyzer → Transport Conditions.",
                systemImage: "exclamationmark.triangle"
            )
            .font(.caption)
            .foregroundStyle(.orange)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private func total(forKey key: String) -> Double {
        snapshot.samples.filter { $0.key == key }.reduce(0) { $0 + $1.sinceConnect }
    }

    // MARK: - Pinned accordion

    /// The order to render: the in-flight one while dragging, the committed one
    /// otherwise.
    private var displayedPins: [SystemMetricSeriesRef] {
        workingPins ?? pins
    }

    @ViewBuilder
    private var pinnedSection: some View {
        if !pins.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                pinnedHeader
                if pinnedExpanded {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(displayedPins.enumerated()), id: \.element.id) { index, ref in
                            ReorderablePinnedRow(
                                ref: ref,
                                isReordering: isReorderingPins,
                                isDragging: pinDragID == ref.id,
                                dragOffset: pinDragID == ref.id ? pinDragOffset : 0,
                                canMoveUp: index > 0,
                                canMoveDown: index < displayedPins.count - 1,
                                onMove: { delta in
                                    setPins(
                                        SystemMetricsPinOrdering.moved(
                                            displayedPins, from: index, to: index + delta
                                        )
                                    )
                                },
                                onHeight: { pinRowHeights[ref.id] = $0 },
                                onDragChanged: { translation in dragPin(ref.id, translation: translation) },
                                onDragEnded: endPinDrag,
                                // Labelled rather than trailing: the row already
                                // takes several other closures, and a trailing one
                                // among them reads as though it belongs to
                                // whichever argument happens to be last.
                                content: {
                                    if let sample = sample(for: ref) {
                                        metricRow(sample, idPrefix: "Pinned")
                                    } else {
                                        idlePinnedRow(ref)
                                    }
                                }
                            )
                            if index < displayedPins.count - 1 {
                                Divider()
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isReorderingPins ? Color.accentColor.opacity(0.6) : Color.secondary.opacity(0.2))
            )
            .accessibilityIdentifier("SystemMetricsPinnedSection")
        }
    }

    private var pinnedHeader: some View {
        HStack(spacing: 6) {
            Button {
                withAnimation(.snappy(duration: 0.2)) { pinnedExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: pinnedExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("Pinned")
                        .font(.subheadline.weight(.semibold))
                    Text("(\(pins.count))")
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // Collapsing mid-reorder would hide the rows being moved.
            .disabled(isReorderingPins)
            .accessibilityIdentifier("SystemMetricsPinnedDisclosure")

            pinnedReorderButton

            Button {
                setPins([])
            } label: {
                Label("Clear", systemImage: "xmark.circle")
                    .font(.caption)
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Unpin every metric")
            .disabled(isReorderingPins)
            .accessibilityIdentifier("SystemMetricsClearPinsButton")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    /// Reorder / Done toggle — the Apple Music "Edit" affordance. Only offered
    /// when there is more than one pin, since reordering one is a no-op.
    @ViewBuilder
    private var pinnedReorderButton: some View {
        if pins.count > 1 {
            Button {
                withAnimation(.snappy(duration: 0.2)) {
                    isReorderingPins.toggle()
                    // Entering reorder mode on a collapsed section would show
                    // nothing to drag.
                    if isReorderingPins {
                        pinnedExpanded = true
                    }
                }
            } label: {
                Text(isReorderingPins ? "Done" : "Reorder")
                    .font(.caption.weight(isReorderingPins ? .semibold : .regular))
            }
            .buttonStyle(.plain)
            .foregroundStyle(isReorderingPins ? Color.accentColor : .secondary)
            .help(isReorderingPins ? "Finish reordering pinned metrics" : "Reorder pinned metrics by dragging")
            .accessibilityIdentifier("SystemMetricsReorderPinsButton")
        }
    }

    // MARK: - Pin drag

    /// Offset applied to the dragged row: the finger's travel minus whatever
    /// completed swaps have already absorbed.
    @State private var pinDragTranslation: CGFloat = 0

    private var pinDragOffset: CGFloat {
        pinDragTranslation - pinDragConsumed
    }

    /// Live reorder: once the row has travelled past a neighbour's midpoint the
    /// two trade places, so the list reads as the final order throughout rather
    /// than only after release.
    private func dragPin(_ id: String, translation: CGFloat) {
        if pinDragID != id {
            pinDragID = id
            workingPins = pins
            pinDragConsumed = 0
        }
        pinDragTranslation = translation

        guard var order = workingPins,
              let index = order.firstIndex(where: { $0.id == id }) else { return }

        let offset = pinDragOffset
        if offset > 0, index < order.count - 1 {
            let height = pinRowHeights[order[index + 1].id] ?? 0
            if height > 0, offset > height / 2 {
                order = SystemMetricsPinOrdering.moved(order, from: index, to: index + 1)
                workingPins = order
                pinDragConsumed += height
            }
        } else if offset < 0, index > 0 {
            let height = pinRowHeights[order[index - 1].id] ?? 0
            if height > 0, -offset > height / 2 {
                order = SystemMetricsPinOrdering.moved(order, from: index, to: index - 1)
                workingPins = order
                pinDragConsumed -= height
            }
        }
    }

    private func endPinDrag() {
        if let order = workingPins {
            setPins(order)
        }
        workingPins = nil
        pinDragID = nil
        pinDragTranslation = 0
        pinDragConsumed = 0
    }

    /// A pinned series the current snapshot doesn't report — not observed yet
    /// this connection, or GC'd store-side. It stays visible with a placeholder
    /// rather than vanishing, so it can always be unpinned from here.
    private func idlePinnedRow(_ ref: SystemMetricSeriesRef) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            pinButton(for: ref, idPrefix: "Pinned")
            VStack(alignment: .leading, spacing: 1) {
                Text(strippedKey(ref.key))
                    .font(.system(.caption, design: .monospaced))
                if !ref.labelLine.isEmpty {
                    Text(ref.labelLine)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 1) {
                Text("—")
                    .font(.system(.caption, design: .monospaced).italic())
                Text("no data yet")
                    .font(.caption2)
            }
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func sample(for ref: SystemMetricSeriesRef) -> SystemMetricSample? {
        snapshot.samples.first { $0.seriesID == ref.id }
    }

    // MARK: - Rows

    private func metricRow(_ sample: SystemMetricSample, idPrefix: String = "") -> some View {
        let ref = SystemMetricSeriesRef(sample: sample)
        let isExpanded = expandedSeriesIDs.contains(ref.id)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                pinButton(for: ref, idPrefix: idPrefix)
                Button {
                    toggleDetails(ref.id)
                } label: {
                    Image(systemName: "info.circle")
                        .font(.caption)
                        .foregroundStyle(isExpanded ? Color.accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .help("Show details")
                .accessibilityLabel("Details for \(sample.key)")
                .accessibilityIdentifier("SystemMetrics\(idPrefix)InfoButton_\(ref.id)")

                VStack(alignment: .leading, spacing: 1) {
                    // Wraps rather than truncates: metric names are long
                    // dot-separated tokens whose distinguishing part is the
                    // suffix, which an ellipsis would quietly eat.
                    Text(strippedKey(sample.key))
                        .font(.system(.caption, design: .monospaced))
                        .fixedSize(horizontal: false, vertical: true)
                    if !ref.labelLine.isEmpty {
                        Text(ref.labelLine)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(formatHeadline(sample))
                        .font(.system(.caption, design: .monospaced))
                    Text(sample.periodDelta > 0 ? "▲ +\(formatDelta(sample))" : "—")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(sample.periodDelta > 0 ? Color.green : .secondary)
                }
                .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.vertical, 4)

            if isExpanded {
                detailPanel(sample)
            }
        }
    }

    private func pinButton(for ref: SystemMetricSeriesRef, idPrefix: String = "") -> some View {
        let pinned = isPinned(ref)
        return Button {
            togglePin(ref)
        } label: {
            Image(systemName: pinned ? "pin.fill" : "pin")
                .font(.caption)
                .foregroundStyle(pinned ? Color.accentColor : .secondary)
        }
        .buttonStyle(.plain)
        .help(pinned ? "Unpin metric" : "Pin to the Pinned section")
        .accessibilityLabel("\(pinned ? "Unpin" : "Pin") \(ref.key)")
        .accessibilityIdentifier("SystemMetrics\(idPrefix)PinButton_\(ref.id)")
    }

    private func detailPanel(_ sample: SystemMetricSample) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if !sample.description.isEmpty {
                Text(sample.description)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 3) {
                detailRow("Metric", sample.key)
                detailRow("Kind", sample.kind == .histogram ? "Histogram" : "Counter")
                if !sample.unit.isEmpty {
                    detailRow("Unit", sample.unit)
                }
                if let average = histogramAverage(sample) {
                    detailRow("Avg since connect", average)
                }
                if sample.kind == .histogram, let absMax = sample.absMax {
                    detailRow("Abs max", formatScaled(absMax, unit: sample.unit))
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(0.1))
        )
        // Aligns the panel with the key column, past the pin + info buttons.
        .padding(.leading, 44)
        .padding(.bottom, 6)
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label.uppercased())
                .font(.caption2)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.leading)
            Text(value)
                .font(.system(.caption2, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func histogramAverage(_ sample: SystemMetricSample) -> String? {
        guard sample.kind == .histogram,
              sample.sinceConnect > 0,
              let sum = sample.sumSinceConnect else
        {
            return nil
        }
        return formatScaled(sum / sample.sinceConnect, unit: sample.unit)
    }

    // MARK: - Pin state

    private func isPinned(_ ref: SystemMetricSeriesRef) -> Bool {
        pins.contains { $0.id == ref.id }
    }

    private func togglePin(_ ref: SystemMetricSeriesRef) {
        setPins(isPinned(ref) ? pins.filter { $0.id != ref.id } : pins + [ref])
    }

    /// Single write path for the pinned list — state and storage never diverge.
    private func setPins(_ next: [SystemMetricSeriesRef]) {
        withAnimation(.snappy(duration: 0.2)) { pins = next }
        SystemMetricsPinStore.write(next, databaseId: databaseId)
    }

    private func toggleDetails(_ id: String) {
        withAnimation(.snappy(duration: 0.2)) {
            if expandedSeriesIDs.contains(id) {
                expandedSeriesIDs.remove(id)
            } else {
                expandedSeriesIDs.insert(id)
            }
        }
    }

    // MARK: - Formatting

    /// `ditto.network.dsoq.connection.opened` → `network.dsoq.connection.opened`.
    private func strippedKey(_ key: String) -> String {
        key.hasPrefix("ditto.") ? String(key.dropFirst("ditto.".count)) : key
    }

    private func formatHeadline(_ sample: SystemMetricSample) -> String {
        // Histograms accumulate a COUNT of observations, so the headline is a
        // plain number regardless of the observed values' unit.
        sample.kind == .histogram
            ? formatValue(sample.sinceConnect)
            : formatScaled(sample.sinceConnect, unit: sample.unit)
    }

    private func formatDelta(_ sample: SystemMetricSample) -> String {
        sample.kind == .histogram
            ? formatValue(sample.periodDelta)
            : formatScaled(sample.periodDelta, unit: sample.unit)
    }

    /// Durations scale to µs / ms / s; everything else prints its raw unit.
    private func formatScaled(_ value: Double, unit: String) -> String {
        guard unit == "seconds" else {
            return formatValue(value) + (unit.isEmpty ? "" : " \(unit)")
        }
        if value < 0.001 {
            return String(format: "%.0f µs", value * 1_000_000)
        }
        if value < 1 {
            return String(format: "%.1f ms", value * 1000)
        }
        return String(format: "%.2f s", value)
    }

    private func formatValue(_ value: Double) -> String {
        if value == value.rounded() {
            return NumberFormatter.localizedString(from: NSNumber(value: value), number: .decimal)
        }
        return value < 10 ? String(format: "%.2f", value) : String(format: "%.1f", value)
    }
}

/// One row of the Pinned accordion.
///
/// Reordering is gated behind the section's **Reorder** mode rather than offered
/// as a bare long-press-drag. On a touch screen the enclosing `ScrollView` wins
/// that gesture — press and drag and you scroll the page, never move the row —
/// which is why the mode exists: it disables the scroll for the duration, and the
/// handle's drag then lands where it should. It is the same Edit-then-drag shape
/// Apple Music uses, and it works with a mouse too.
private struct ReorderablePinnedRow<Content: View>: View {
    let ref: SystemMetricSeriesRef
    let isReordering: Bool
    let isDragging: Bool
    /// Vertical displacement to draw this row at while it is being dragged.
    let dragOffset: CGFloat
    let canMoveUp: Bool
    let canMoveDown: Bool
    /// Move this row by the given offset — `-1` up, `+1` down. A delta rather
    /// than an absolute index so the row never has to know where it sits in the
    /// live order, which changes underneath it during a drag.
    let onMove: (Int) -> Void
    /// Reports the row's measured height, which the parent needs to decide when a
    /// drag has crossed a neighbour.
    let onHeight: (CGFloat) -> Void
    /// Cumulative vertical translation since the drag began.
    let onDragChanged: (CGFloat) -> Void
    let onDragEnded: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 6) {
            content()
                // While reordering, the row's own pin and info buttons would just
                // be mis-taps waiting to happen.
                .allowsHitTesting(!isReordering)
            if isReordering {
                dragHandle
            }
        }
        .contentShape(Rectangle())
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { onHeight(proxy.size.height) }
                    .onChange(of: proxy.size.height) { _, newHeight in onHeight(newHeight) }
            }
        }
        .offset(y: dragOffset)
        // The dragged row rides above its neighbours so the rows it passes cannot
        // paint over it.
        .zIndex(isDragging ? 1 : 0)
        .shadow(color: .black.opacity(isDragging ? 0.25 : 0), radius: 6, y: 2)
        // Keyboard- and VoiceOver-reachable equivalent of dragging: the pointer
        // precision a drag needs is not available to every user, and these work
        // whether or not reorder mode is on.
        .contextMenu {
            if canMoveUp || canMoveDown {
                Button("Move Up") { onMove(-1) }
                    .disabled(!canMoveUp)
                Button("Move Down") { onMove(1) }
                    .disabled(!canMoveDown)
            }
        }
    }

    private var dragHandle: some View {
        Image(systemName: "line.3.horizontal")
            .font(.body)
            .foregroundStyle(isDragging ? Color.accentColor : .secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .gesture(
                // minimumDistance 0 so the drag begins on touch-down. There is no
                // long press to wait out — the mode already established intent,
                // and the scroll that would have competed is disabled.
                DragGesture(minimumDistance: 0)
                    .onChanged { onDragChanged($0.translation.height) }
                    .onEnded { _ in onDragEnded() }
            )
            .accessibilityLabel("Reorder \(ref.key)")
            .accessibilityIdentifier("SystemMetricsPinDragHandle_\(ref.id)")
    }
}

extension SystemMetricSample {
    /// Stable per-series identity shared with `SystemMetricSeriesRef.id`, so a
    /// pin, an expanded detail panel, and a `ForEach` row all agree on which
    /// series they refer to across polls.
    var seriesID: String {
        SystemMetricSeriesRef(sample: self).id
    }
}
