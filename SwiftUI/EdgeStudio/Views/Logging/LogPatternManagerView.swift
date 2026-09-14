import SwiftUI

/// Severity → color mapping, matching the VS Code analyzer palette and Android.
func logSeverityColor(_ severity: Int) -> Color {
    switch severity {
    case 5: return Color(red: 1.0, green: 0.32, blue: 0.32) // #ff5252
    case 4: return Color(red: 1.0, green: 0.54, blue: 0.32) // #ff8a52
    case 3: return Color(red: 0.83, green: 0.63, blue: 0.09) // #d4a017
    case 2: return Color(red: 0.31, green: 0.63, blue: 1.0) // #4ea1ff
    default: return .gray
    }
}

/// The user-tag chip color — matches the VS Code analyzer's purple (#b08fff).
let logUserTagColor = Color(red: 0.69, green: 0.56, blue: 1.0)

/// Pattern manager sheet (parity with the VS Code extension's Pattern Editor
/// panel): bundled read-only catalog plus user CRUD with live validation.
struct LogPatternManagerView: View {
    @Bindable var store: LogPatternStore
    @Environment(\.dismiss) private var dismiss

    @State private var editingPattern: LogPattern?
    @State private var isCreating = false
    @State private var actionError: String?

    var body: some View {
        NavigationStack {
            List {
                if !store.patternErrors.isEmpty {
                    Section {
                        ForEach(store.patternErrors.sorted(by: { $0.key < $1.key }), id: \.key) { key, reason in
                            Label("\(key): \(reason)", systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    } header: {
                        Text("Rejected Patterns")
                    }
                }

                if let actionError {
                    Section {
                        Text(actionError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    ForEach(store.patterns.values.filter { $0.source == .bundled }.sorted { $0.key < $1.key }, id: \.key) { pattern in
                        LogPatternRowView(pattern: pattern)
                    }
                } header: {
                    Label("Bundled (read-only)", systemImage: "lock")
                }

                Section {
                    ForEach(store.patterns.values.filter { $0.source == .user }.sorted { $0.key < $1.key }, id: \.key) { pattern in
                        LogPatternRowView(pattern: pattern)
                            .swipeActions {
                                Button(role: .destructive) {
                                    do {
                                        try store.delete(key: pattern.key)
                                    } catch {
                                        actionError = error.localizedDescription
                                    }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                Button {
                                    editingPattern = pattern
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                            }
                            .contextMenu {
                                Button {
                                    editingPattern = pattern
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                Button(role: .destructive) {
                                    do {
                                        try store.delete(key: pattern.key)
                                    } catch {
                                        actionError = error.localizedDescription
                                    }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                } header: {
                    HStack {
                        Text("Your Patterns")
                        Spacer()
                        Button {
                            isCreating = true
                        } label: {
                            Label("Add", systemImage: "plus")
                                .labelStyle(.iconOnly)
                        }
                        .accessibilityIdentifier("AddLogPatternButton")
                    }
                }
            }
            .navigationTitle("Log Patterns")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("LogPatternsDoneButton")
                }
            }
            .sheet(isPresented: $isCreating) {
                LogPatternEditorView(
                    store: store,
                    title: "New Pattern",
                    initialKey: "",
                    initial: LogPatternBody(pattern: "", severity: 3, recommendation: ""),
                    keyEditable: true
                )
            }
            .sheet(item: $editingPattern) { pattern in
                LogPatternEditorView(
                    store: store,
                    title: "Edit Pattern",
                    initialKey: pattern.key,
                    initial: pattern.body,
                    keyEditable: false
                )
            }
        }
        #if os(macOS)
        .frame(minWidth: 640, minHeight: 480)
        #endif
    }
}

extension LogPattern: Identifiable {
    var id: String {
        key
    }
}

private struct LogPatternRowView: View {
    let pattern: LogPattern

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(severityLabel(pattern.severity))
                    .font(.system(.caption2, design: .monospaced, weight: .bold))
                    .foregroundStyle(logSeverityColor(pattern.severity))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(logSeverityColor(pattern.severity).opacity(0.18))
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                Text(pattern.key)
                    .font(.callout)
                    .fontWeight(.medium)

                if pattern.source == .bundled {
                    Image(systemName: "lock")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }

                if let tag = pattern.body.userTag {
                    Text("#\(tag)")
                        .font(.caption)
                        .foregroundStyle(logUserTagColor)
                }
            }
            Text(pattern.body.pattern)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(pattern.body.recommendation)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 2)
    }
}

/// Pattern editor with live validation and a test-line field (parity with the
/// extension's `pattern-form`): shows ✓/✗ match against a pasted log line.
struct LogPatternEditorView: View {
    let store: LogPatternStore
    let title: String
    let initialKey: String
    let initial: LogPatternBody
    let keyEditable: Bool
    @Environment(\.dismiss) private var dismiss

    @State private var key = ""
    @State private var pattern = ""
    @State private var severity = 3
    @State private var recommendation = ""
    @State private var levelFilterName = ""
    @State private var tagFilter = ""
    @State private var userTag = ""
    @State private var testLine = ""
    @State private var saveError: String?

    private var draftBody: LogPatternBody {
        LogPatternBody(
            pattern: pattern,
            severity: severity,
            recommendation: recommendation,
            levelFilter: levelFilterName.isEmpty ? nil : levelFilterName,
            tagFilter: tagFilter.isEmpty ? nil : tagFilter,
            userTag: userTag.isEmpty ? nil : userTag
        )
    }

    private var keyError: String? {
        let trimmed = key.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            return "Key is required"
        }
        if keyEditable {
            if store.bundledKeys.contains(trimmed) {
                return "Key collides with a bundled pattern"
            }
            if store.patterns[trimmed] != nil {
                return "A pattern with this key already exists"
            }
        }
        return nil
    }

    private var validationError: String? {
        if let keyError {
            return keyError
        }
        return LogPatternEngine.rejectReason(
            key: key.isEmpty ? "draft" : key,
            body: draftBody,
            source: .user
        )
    }

    private var testResult: (matched: Bool, label: String)? {
        guard !testLine.isEmpty else { return nil }
        if (try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)) == nil {
            return (false, "Pattern is not a valid regex")
        }
        // Level filter is an exact equality, so test at the filter's level; the
        // component is derived from the pasted line via the heuristic the
        // capture pipeline also uses.
        let level = parseLogLevelFilter(draftBody.levelFilter) ?? .warning
        let tag = LogComponent.heuristic(from: testLine).rawValue
        let matched = LogPatternEngine.testMatch(body: draftBody, level: level, tag: tag, message: testLine)
        return (matched, matched ? "Matches" : "No match")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Pattern") {
                    if keyEditable {
                        TextField("Key", text: $key)
                            .accessibilityIdentifier("LogPatternKeyField")
                    } else {
                        LabeledContent("Key", value: initialKey)
                    }
                    TextField("Regex (case-insensitive)", text: $pattern, axis: .vertical)
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(2 ... 6)
                        .accessibilityIdentifier("LogPatternRegexField")
                }

                Section("Classification") {
                    Picker("Severity", selection: $severity) {
                        ForEach((1 ... 5).reversed(), id: \.self) { sev in
                            Text("\(sev) — \(severityLabel(sev))")
                                .foregroundStyle(logSeverityColor(sev))
                                .tag(sev)
                        }
                    }
                    Picker("Level (exact match)", selection: $levelFilterName) {
                        Text("Any").tag("")
                        ForEach(["error", "warning", "info", "debug", "verbose"], id: \.self) { lvl in
                            Text(lvl).tag(lvl)
                        }
                    }
                    TextField("Component filter (regex, optional)", text: $tagFilter)
                        .font(.system(.body, design: .monospaced))
                    TextField("User tag (optional label)", text: $userTag)
                }

                Section("Recommendation") {
                    TextField("What should the developer do?", text: $recommendation, axis: .vertical)
                        .lineLimit(2 ... 4)
                        .accessibilityIdentifier("LogPatternRecommendationField")
                }

                Section("Test") {
                    TextField("Paste a log line to try the pattern", text: $testLine, axis: .vertical)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(2 ... 4)
                    if let testResult {
                        Text("\(testResult.matched ? "✓" : "✗") \(testResult.label)")
                            .font(.caption)
                            .foregroundStyle(testResult.matched ? .green : .red)
                    }
                }

                if let validationError {
                    Section {
                        Text(validationError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                if let saveError {
                    Section {
                        Text(saveError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("LogPatternCancelButton")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do {
                            if keyEditable {
                                try store.add(key: key.trimmingCharacters(in: .whitespaces), body: draftBody)
                            } else {
                                try store.update(key: initialKey, body: draftBody)
                            }
                            dismiss()
                        } catch {
                            saveError = error.localizedDescription
                        }
                    }
                    .disabled(validationError != nil)
                    .accessibilityIdentifier("LogPatternSaveButton")
                }
            }
        }
        .onAppear {
            key = initialKey
            pattern = initial.pattern
            severity = initial.severity
            recommendation = initial.recommendation
            levelFilterName = initial.levelFilter ?? ""
            tagFilter = initial.tagFilter ?? ""
            userTag = initial.userTag ?? ""
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 560)
        #endif
    }
}
