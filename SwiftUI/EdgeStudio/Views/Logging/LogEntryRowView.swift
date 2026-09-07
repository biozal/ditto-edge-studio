import DittoSwift
import SwiftUI

/// A single row in the log viewer list.
///
/// ## Why expansion state lives in the parent
///
/// This used to hold `@State private var isExpanded`. That made the row the
/// only thing that knew it was open, which had two consequences:
///
/// 1. **It could not show context.** A row has no view of its neighbours, and
///    the neighbours that matter are the ones the current filter *hides* (see
///    `LogEntryContext`). Only the list's owner can reach the unfiltered
///    buffer.
/// 2. **Expansion did not survive a refresh.** `LogFileParser` mints a fresh
///    `UUID` for every entry each time it re-reads the files, so a Refresh
///    replaced every row identity and silently collapsed whatever was open.
///
/// The parent now owns a single `expandedEntryID`, which also keeps the list
/// readable: one drawer at a time rather than an arbitrary number of them
/// pushing rows off-screen.
struct LogEntryRowView: View {
    let entry: LogEntry
    /// User-defined labels applied by matching log patterns.
    var userTags: [String] = []
    /// Whether this row's detail drawer is open.
    var isExpanded = false
    /// Surrounding entries from the unfiltered source buffer. Supplied only for
    /// the expanded row; every other row is handed `.empty` and pays nothing.
    var context: LogEntryContext = .empty
    /// Invoked when the row is activated. The parent decides what expanding
    /// means — it is the only thing that can resolve the context.
    var onToggleExpanded: () -> Void = {}

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm:ss.SSS a"
        return f
    }()

    /// Wide enough for the full `h:mm:ss.SSS a` format. The previous 80pt
    /// truncated or shoved the badges out of alignment on every row.
    private static let timestampWidth: CGFloat = 116

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            headerRow

            Text(entry.message)
                .font(.system(.callout, design: .monospaced))
                .lineLimit(isExpanded ? nil : 2)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(.primary)

            if isExpanded {
                expandedDetail
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.15)) {
                onToggleExpanded()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("LogEntryRow")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(isExpanded ? "Collapse entry details" : "Expand to see surrounding log lines")
        .contextMenu { contextMenuItems }
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(Self.timeFormatter.string(from: entry.timestamp))
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: Self.timestampWidth, alignment: .leading)

            levelBadge(entry.level)

            if entry.source == .dittoSDK || isImportedSDKSource {
                componentPill(entry.component)
            }

            ForEach(userTags, id: \.self) { tag in
                Text(tag)
                    .font(.caption2)
                    .foregroundStyle(logUserTagColor)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(logUserTagColor.opacity(0.18))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            Spacer(minLength: 0)

            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Expanded detail

    private var expandedDetail: some View {
        VStack(alignment: .leading, spacing: 6) {
            // The raw line is worth showing only when it carries more than the
            // message does. For SDK file logs it is the JSON record, whose
            // sibling fields (remote, role, transport_type, connection_id) are
            // exactly what a sync investigation needs and are absent from the
            // message body.
            if entry.rawLine != entry.message, !entry.rawLine.isEmpty {
                labelledBlock("Raw") {
                    Text(entry.rawLine)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if context.isEmpty {
                labelledBlock("Context") {
                    Text("No surrounding entries in this buffer.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            } else {
                labelledBlock("Context") {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(context.before) { contextLine($0, isFocused: false) }
                        contextLine(entry, isFocused: true)
                        ForEach(context.after) { contextLine($0, isFocused: false) }
                    }
                }
            }
        }
        .padding(.top, 2)
        .accessibilityIdentifier("LogEntryDetail")
    }

    private func labelledBlock(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(.tertiary)
            content()
        }
        .padding(.leading, 8)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.secondary.opacity(0.25))
                .frame(width: 2)
        }
    }

    /// One line of surrounding context. The focused entry is repeated inside
    /// the drawer so the neighbours read in order rather than as two
    /// disconnected groups above and below.
    private func contextLine(_ line: LogEntry, isFocused: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(Self.timeFormatter.string(from: line.timestamp))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
            Text(line.level.shortName)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(levelColor(line.level))
                .frame(width: 34, alignment: .leading)
            Text(line.message)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(isFocused ? .primary : .secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .fontWeight(isFocused ? .semibold : .regular)
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
        .background(isFocused ? Color.accentColor.opacity(0.14) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    // MARK: - Context menu

    @ViewBuilder
    private var contextMenuItems: some View {
        Button {
            copyToPasteboard(entry.rawLine)
        } label: {
            Label("Copy Line", systemImage: "doc.on.doc")
        }

        Button {
            copyToPasteboard(entry.message)
        } label: {
            Label("Copy Message", systemImage: "text.document")
        }

        if !context.isEmpty {
            Button {
                let lines = context.before + [entry] + context.after
                copyToPasteboard(lines.map(\.rawLine).joined(separator: "\n"))
            } label: {
                Label("Copy With Context", systemImage: "doc.on.doc.fill")
            }
        }
    }

    private func copyToPasteboard(_ string: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #else
        UIPasteboard.general.string = string
        #endif
    }

    // MARK: - Pieces

    private var isImportedSDKSource: Bool {
        if case .imported = entry.source {
            return true
        }
        return false
    }

    private func levelBadge(_ level: DittoLogLevel) -> some View {
        // The width constraint has to come *before* the background and clip, or
        // it sizes the already-painted badge instead of the badge itself and the
        // pills end up ragged from row to row.
        Text(level.shortName)
            .font(.system(size: 15, weight: .bold, design: .monospaced))
            .frame(minWidth: 36)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(levelColor(level).opacity(0.18))
            .foregroundStyle(levelColor(level))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    @ViewBuilder
    private func componentPill(_ component: LogComponent) -> some View {
        if component != .other, component != .all {
            Text(component.rawValue)
                .font(.system(size: 15, weight: .medium))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.12))
                .foregroundStyle(.secondary)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }

    private func levelColor(_ level: DittoLogLevel) -> Color {
        switch level {
        case .error: return .red
        case .warning: return .orange
        case .info: return .blue
        case .debug: return .secondary
        case .verbose: return Color.secondary.opacity(0.6)
        @unknown default: return .secondary
        }
    }
}
