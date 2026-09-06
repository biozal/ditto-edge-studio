import SwiftUI
import UniformTypeIdentifiers

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
    /// Which pinned row is mid-drag. See `PinDragCoordinator` for why this is a
    /// reference type rather than a plain `@State` value.
    @State private var pinDrag = PinDragCoordinator()

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var snapshot: SystemMetricsService.Snapshot {
        service.snapshot
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    pinnedSection
                    filterRow
                    contentBody
                }
                .padding()
            }
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

    @ViewBuilder
    private var pinnedSection: some View {
        if !pins.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                pinnedHeader
                if pinnedExpanded {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(pins.enumerated()), id: \.element.id) { index, ref in
                            ReorderablePinnedRow(
                                ref: ref,
                                // Reordering a single pin is meaningless — hide the
                                // handle rather than offer a no-op affordance.
                                isReorderable: pins.count > 1,
                                coordinator: pinDrag,
                                onDrop: { draggedID, insertBefore in
                                    setPins(
                                        SystemMetricsPinOrdering.moved(
                                            pins,
                                            draggedID: draggedID,
                                            targetID: ref.id,
                                            insertBefore: insertBefore
                                        )
                                    )
                                },
                                onMove: { destination in
                                    setPins(SystemMetricsPinOrdering.moved(pins, from: index, to: destination))
                                },
                                index: index,
                                count: pins.count,
                                // Labelled rather than trailing: the row already
                                // takes two other closures, and a trailing one
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
                            if index < pins.count - 1 {
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
                    .stroke(Color.secondary.opacity(0.2))
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
            .accessibilityIdentifier("SystemMetricsPinnedDisclosure")

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
            .accessibilityIdentifier("SystemMetricsClearPinsButton")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
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

/// Identity of the pinned row currently being dragged.
///
/// A reference type held in `@State` rather than a `@State` value: it is written
/// from inside `.onDrag`'s closure, and publishing a change from there invalidates
/// the view mid-gesture, which cancels the drag on macOS. Nothing renders from it —
/// only the drop delegates read it — so not publishing changes is exactly right.
@MainActor
final class PinDragCoordinator {
    var draggedID: String?
}

/// One row of the Pinned accordion, wrapped with the drag-to-reorder affordances:
/// the whole row is a drag source, a `line.3.horizontal` handle at the trailing
/// edge communicates that, and an insertion line shows where a drop would land.
///
/// Drop position follows the pointer against the row's own midpoint — above it
/// inserts before this row, at or below inserts after — which is what makes a
/// downward drag land where you pointed instead of one slot short. Same rule as
/// the VS Code panel and the Android screen.
private struct ReorderablePinnedRow<Content: View>: View {
    let ref: SystemMetricSeriesRef
    let isReorderable: Bool
    let coordinator: PinDragCoordinator
    /// `(draggedID, insertBefore)` — the drop landed on this row.
    let onDrop: (String, Bool) -> Void
    /// Move this row to the given index (the Move Up / Move Down commands).
    let onMove: (Int) -> Void
    let index: Int
    let count: Int
    @ViewBuilder let content: () -> Content

    /// Measured so the drop delegate can compare the pointer against the midpoint;
    /// rows differ in height (a label line, an expanded detail panel), so this
    /// cannot be a constant.
    @State private var height: CGFloat = 0
    /// Which edge the insertion line is drawn on, or `nil` when not a drop target.
    @State private var dropEdge: VerticalEdge?

    var body: some View {
        HStack(spacing: 6) {
            content()
            if isReorderable {
                Image(systemName: "line.3.horizontal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help("Drag to reorder")
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { height = proxy.size.height }
                    .onChange(of: proxy.size.height) { _, newHeight in height = newHeight }
            }
        }
        .overlay(alignment: .top) { insertionLine(on: .top) }
        .overlay(alignment: .bottom) { insertionLine(on: .bottom) }
        .modifier(
            PinReorderGestures(
                enabled: isReorderable,
                ref: ref,
                coordinator: coordinator,
                height: height,
                dropEdge: $dropEdge,
                onDrop: onDrop
            )
        )
        // Keyboard- and VoiceOver-reachable equivalent of dragging: the pointer
        // precision a drag needs is not available to every user.
        .contextMenu {
            if isReorderable {
                Button("Move Up") { onMove(index - 1) }
                    .disabled(index == 0)
                Button("Move Down") { onMove(index + 1) }
                    .disabled(index == count - 1)
            }
        }
    }

    @ViewBuilder
    private func insertionLine(on edge: VerticalEdge) -> some View {
        if dropEdge == edge {
            Rectangle()
                .fill(Color.accentColor)
                .frame(height: 2)
        }
    }
}

/// Splits the drag/drop wiring off the row so the `isReorderable == false` case
/// attaches no gesture at all, rather than attaching one that silently refuses.
private struct PinReorderGestures: ViewModifier {
    let enabled: Bool
    let ref: SystemMetricSeriesRef
    let coordinator: PinDragCoordinator
    let height: CGFloat
    @Binding var dropEdge: VerticalEdge?
    let onDrop: (String, Bool) -> Void

    func body(content: Content) -> some View {
        if enabled {
            content
                .onDrag {
                    coordinator.draggedID = ref.id
                    return NSItemProvider(object: ref.id as NSString)
                }
                .onDrop(
                    of: [UTType.text],
                    delegate: PinReorderDropDelegate(
                        targetID: ref.id,
                        height: height,
                        coordinator: coordinator,
                        dropEdge: $dropEdge,
                        onDrop: onDrop
                    )
                )
        } else {
            content
        }
    }
}

/// `DropDelegate` rather than `.dropDestination`: only the delegate reports the
/// pointer's live position while hovering, which is what the before/after
/// insertion line is drawn from.
///
/// The dragged identity is read from the coordinator, never from the drop payload,
/// so a text drag from another app is rejected instead of reordering anything.
private struct PinReorderDropDelegate: DropDelegate {
    let targetID: String
    let height: CGFloat
    let coordinator: PinDragCoordinator
    @Binding var dropEdge: VerticalEdge?
    let onDrop: (String, Bool) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        guard let dragged = coordinator.draggedID else { return false }
        return dragged != targetID
    }

    func dropEntered(info: DropInfo) {
        updateEdge(info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        updateEdge(info)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        dropEdge = nil
    }

    func performDrop(info: DropInfo) -> Bool {
        dropEdge = nil
        guard let dragged = coordinator.draggedID, dragged != targetID else { return false }
        coordinator.draggedID = nil
        onDrop(dragged, insertsBefore(info))
        return true
    }

    private func updateEdge(_ info: DropInfo) {
        guard let dragged = coordinator.draggedID, dragged != targetID else {
            dropEdge = nil
            return
        }
        dropEdge = insertsBefore(info) ? .top : .bottom
    }

    /// Above the row's vertical midpoint inserts before it; at or below, after.
    private func insertsBefore(_ info: DropInfo) -> Bool {
        info.location.y < height / 2
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
