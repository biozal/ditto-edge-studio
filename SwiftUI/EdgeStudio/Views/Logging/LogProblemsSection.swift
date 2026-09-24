import SwiftUI

/// Collapsible strip summarizing pattern matches in the current log view (parity
/// with the VS Code analyzer's Problems list): groups by pattern key sorted by
/// severity, shows hit counts and recommendations, and each hit can jump the
/// user to the matching line in the table. Renders nothing when no patterns match.
struct LogProblemsSection: View {
    let problems: [LogPatternEngine.Match]
    let onJumpToEntry: (LogEntry) -> Void

    @State private var isExpanded = false
    @State private var expandedKeys: Set<String> = []

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private let maxShownHitsPerPattern = 10

    private var groups: [(key: String, matches: [LogPatternEngine.Match])] {
        Dictionary(grouping: problems) { $0.pattern.key }
            .map { (key: $0.key, matches: $0.value) }
            .sorted { ($0.matches.first?.pattern.severity ?? 0) > ($1.matches.first?.pattern.severity ?? 0) }
    }

    var body: some View {
        if problems.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 0) {
                headerRow

                if isExpanded {
                    Divider()
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(groups, id: \.key) { group in
                                groupRow(group)
                            }
                        }
                    }
                    .frame(maxHeight: 200)
                }
            }
        }
    }

    private var headerRow: some View {
        let worstSeverity = groups.first?.matches.first?.pattern.severity ?? 1
        let distinctLines = Set(problems.map(\.entry.id)).count
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(logSeverityColor(worstSeverity))
                Text("\(problems.count) problems matched on \(distinctLines) log lines")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(logSeverityColor(worstSeverity))
                Spacer()
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption)
                    .foregroundStyle(logSeverityColor(worstSeverity))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(logSeverityColor(worstSeverity).opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("LogProblemsToggle")
    }

    private func groupRow(_ group: (key: String, matches: [LogPatternEngine.Match])) -> some View {
        let pattern = group.matches.first?.pattern
        let expanded = expandedKeys.contains(group.key)
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                if expanded {
                    expandedKeys.remove(group.key)
                } else {
                    expandedKeys.insert(group.key)
                }
            } label: {
                HStack(spacing: 6) {
                    Text(severityLabel(pattern?.severity ?? 1))
                        .font(.system(.caption2, design: .monospaced, weight: .bold))
                        .foregroundStyle(logSeverityColor(pattern?.severity ?? 1))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(logSeverityColor(pattern?.severity ?? 1).opacity(0.18))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(group.key) ×\(group.matches.count)")
                            .font(.caption)
                            .fontWeight(.medium)
                        Text(pattern?.recommendation ?? "")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)

            if expanded {
                ForEach(group.matches.prefix(maxShownHitsPerPattern), id: \.entry.id) { match in
                    Button {
                        onJumpToEntry(match.entry)
                    } label: {
                        HStack(spacing: 8) {
                            Text(Self.timeFormatter.string(from: match.entry.timestamp))
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Text(match.entry.message)
                                .font(.system(.caption2, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Spacer(minLength: 0)
                        }
                        .padding(.leading, 16)
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if group.matches.count > maxShownHitsPerPattern {
                    Text("+\(group.matches.count - maxShownHitsPerPattern) more")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 16)
                }
            }
        }
    }
}
