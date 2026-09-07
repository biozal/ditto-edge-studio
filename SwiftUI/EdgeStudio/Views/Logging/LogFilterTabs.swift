import DittoSwift
import SwiftUI

/// The five analyzer filter tabs, matching the VS Code extension's `FilterKey`
/// and its `queryLines` filter semantics exactly.
enum LogFilterTab: String, CaseIterable, Identifiable, Hashable {
    case all
    case critical
    case error
    case warning
    case problem

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .all: return "All"
        case .critical: return "Critical"
        case .error: return "Errors"
        case .warning: return "Warnings"
        case .problem: return "Problems"
        }
    }

    var tint: Color {
        switch self {
        case .all, .problem: return .primary
        case .critical, .error: return logSeverityColor(5)
        case .warning: return logSeverityColor(3)
        }
    }

    /// Badge count for this tab.
    ///
    /// Critical and Problems deliberately read the **distinct-entry** counters,
    /// not the occurrence counters. A line matched by three patterns adds three
    /// to `counts.problems` but can only ever appear once in the table, so a
    /// badge sourced from `problems` would promise rows the list cannot render.
    /// The Summary header is where the occurrence totals belong.
    func badgeCount(_ counts: LogAnalytics.Counts) -> Int {
        switch self {
        case .all: return counts.totalLines
        case .critical: return counts.criticalEntries
        case .error: return counts.errors
        case .warning: return counts.warnings
        case .problem: return counts.problemEntries
        }
    }

    /// Whether `entry` passes this tab.
    ///
    /// - `critical` — the entry was matched by a severity-5 pattern.
    /// - `problem` — the entry was matched by any pattern.
    /// - `error` / `warning` — level equality.
    func accepts(_ entry: LogEntry, problemIDs: Set<UUID>, criticalIDs: Set<UUID>) -> Bool {
        switch self {
        case .all: return true
        case .critical: return criticalIDs.contains(entry.id)
        case .error: return entry.level == .error
        case .warning: return entry.level == .warning
        case .problem: return problemIDs.contains(entry.id)
        }
    }

    /// True when the tab already constrains the level, making the level chips
    /// redundant (and contradictory — an Errors tab with ERR deselected would
    /// render nothing and look broken).
    var overridesLevelChips: Bool {
        switch self {
        case .all: return false
        case .critical, .error, .warning, .problem: return true
        }
    }
}

/// Tab strip with count badges above the log list (parity with the VS Code
/// analyzer's `filter-tabs`).
struct LogFilterTabs: View {
    @Binding var selection: LogFilterTab
    let counts: LogAnalytics.Counts

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(LogFilterTab.allCases) { tab in
                    tabButton(tab)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
        .accessibilityIdentifier("LogFilterTabs")
    }

    private func tabButton(_ tab: LogFilterTab) -> some View {
        let isSelected = selection == tab
        return Button {
            selection = tab
        } label: {
            HStack(spacing: 5) {
                Text(tab.label)
                    .font(.caption)
                    .fontWeight(isSelected ? .semibold : .regular)
                Text("\(tab.badgeCount(counts))")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.18))
                    .clipShape(Capsule())
            }
            .foregroundStyle(isSelected ? tab.tint : Color.secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(isSelected ? Color.accentColor.opacity(0.14) : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.2), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("LogFilterTab_\(tab.rawValue)")
    }
}
