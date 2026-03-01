import DittoSwift
import SwiftUI

/// A single row in the log viewer list.
struct LogEntryRowView: View {
    let entry: LogEntry

    @State private var isExpanded = false

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm:ss.SSS a"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                // Timestamp
                Text(Self.timeFormatter.string(from: entry.timestamp))
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 80, alignment: .leading)

                // Level badge
                levelBadge(entry.level)

                // Component pill (SDK source only)
                if entry.source == .dittoSDK || isImportedSDKSource {
                    componentPill(entry.component)
                }

                Spacer()
            }

            // Message text
            Text(entry.message)
                .font(.system(.callout, design: .monospaced))
                .lineLimit(isExpanded ? nil : 2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(.primary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.15)) {
                isExpanded.toggle()
            }
        }
        .contextMenu {
            Button {
                #if os(macOS)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.rawLine, forType: .string)
                #else
                UIPasteboard.general.string = entry.rawLine
                #endif
            } label: {
                Label("Copy Line", systemImage: "doc.on.doc")
            }

            Button {
                #if os(macOS)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.message, forType: .string)
                #else
                UIPasteboard.general.string = entry.message
                #endif
            } label: {
                Label("Copy Message", systemImage: "text.document")
            }
        }
    }

    private var isImportedSDKSource: Bool {
        if case .imported = entry.source { return true }
        return false
    }

    private func levelBadge(_ level: DittoLogLevel) -> some View {
        Text(level.shortName)
            .font(.system(size: 15, weight: .bold, design: .monospaced))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(levelColor(level).opacity(0.18))
            .foregroundStyle(levelColor(level))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .frame(minWidth: 36)
    }

    @ViewBuilder
    private func componentPill(_ component: LogComponent) -> some View {
        if component != .other && component != .all {
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
