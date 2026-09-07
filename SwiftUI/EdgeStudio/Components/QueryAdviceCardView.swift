import SwiftUI

/// Card surfacing the result of an `ADVISE` run (SDK 5.1): the advised statement,
/// either the outcome text ("no keys to advise on") or one row per index
/// suggestion with an Apply button. Applying a suggestion executes its CREATE
/// INDEX statement verbatim — only after the confirmation dialog
/// (parity with the VS Code extension's confirm modal).
struct QueryAdviceCardView: View {
    let advice: QueryAdvice
    let onApply: (QueryIndexSuggestion) async -> Bool
    let onDismiss: () -> Void

    /// Per-suggestion state keyed by statement (parity with the extension's
    /// adviseStates map: pending → created/failed/declined).
    @State private var states: [String: SuggestionState] = [:]
    @State private var confirming: QueryIndexSuggestion?

    private enum SuggestionState {
        case pending, created, failed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "lightbulb")
                    .foregroundStyle(Color.dittoYellow)
                    .accessibilityHidden(true)
                Text("Index advice")
                    .font(.callout.weight(.semibold))
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("QueryAdviceDismissButton")
            }

            Text(advice.statement)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.tail)

            if advice.suggestions.isEmpty {
                Text(advice.outcome ?? "No index suggestions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(advice.suggestions, id: \.statement) { suggestion in
                    suggestionRow(suggestion)
                }
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
        )
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .alert(
            "Create index on \(confirming?.collection ?? "")?",
            isPresented: Binding(
                get: { confirming != nil },
                set: {
                    if !$0 {
                        confirming = nil
                    }
                }
            ),
            presenting: confirming
        ) { suggestion in
            Button("Create Index") {
                Task {
                    let ok = await onApply(suggestion)
                    states[suggestion.statement] = ok ? .created : .failed
                }
            }
            Button("Cancel", role: .cancel) { confirming = nil }
        } message: { suggestion in
            Text(suggestion.statement)
                .font(.system(.caption, design: .monospaced))
        }
    }

    private func suggestionRow(_ suggestion: QueryIndexSuggestion) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(suggestion.statement)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(2)
                if !suggestion.reason.isEmpty {
                    Text(suggestion.reason)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            switch states[suggestion.statement] ?? .pending {
            case .pending:
                Button("Apply") { confirming = suggestion }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .accessibilityIdentifier("QueryAdviceApply-\(suggestion.collection)")
            case .created:
                Label("Created", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            case .failed:
                Label("Failed", systemImage: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }
}
