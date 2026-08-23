import SwiftUI

/// Shared row-level context menu used by both `ResultJsonViewer` and
/// `ResultTableViewer`. Centralising the menu keeps the two viewers
/// from drifting — they both end up offering Copy Document / Copy _id /
/// Add Attachment… / Delete Attachment… in the same order with the
/// same disabled-state semantics.
///
/// Why this exists at all (root cause notes for future maintainers):
/// the previous inline `.contextMenu` blocks were duplicated between
/// JSON viewer and Table viewer, and the right-click in each was being
/// shadowed by `Text(...).textSelection(.enabled)` on the row content.
/// On macOS that modifier hosts an `NSTextView` which claims pointer
/// events inside the text bounds and presents the system selection
/// menu, suppressing the parent `.contextMenu`. The fix is twofold:
/// drop `.textSelection(.enabled)` on row cells (do fine-grained text
/// selection in the Inspector pane instead), and share this single
/// menu builder so both viewers stay aligned.
@MainActor
@ViewBuilder
func queryResultRowMenu(
    hasAttachments: Bool,
    onCopyDocument: @escaping () -> Void,
    onCopyId: @escaping () -> Void,
    onAddAttachment: @escaping () -> Void,
    onDeleteAttachment: @escaping () -> Void
) -> some View {
    Button {
        onCopyDocument()
    } label: {
        Label("Copy Document", systemImage: "doc.on.doc")
    }
    Button {
        onCopyId()
    } label: {
        Label("Copy _id", systemImage: "number")
    }
    Divider()
    Button {
        onAddAttachment()
    } label: {
        Label("Add Attachment…", systemImage: "paperclip")
    }
    Button {
        onDeleteAttachment()
    } label: {
        Label("Delete Attachment…", systemImage: "trash")
    }
    .disabled(!hasAttachments)
}

/// Extracts the `_id` field from a JSON document string and returns a
/// clipboard-safe representation.
///
/// Handles the three cases Ditto users actually encounter:
///   - **String** _ids → returned raw (the common case).
///   - **Numeric** _ids → stringified digits.
///   - **Composite-key / object** _ids → re-encoded as compact JSON
///     with sorted keys so the value round-trips into a
///     `WHERE _id = …` clause without re-quoting.
///
/// Returns `nil` if the input isn't valid JSON, isn't a top-level
/// object, or doesn't contain `_id`. Callers should fall back to a
/// no-op (and optionally a toast) on `nil`.
func extractIdString(fromJSON jsonString: String) -> String? {
    guard let data = jsonString.data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let id = obj["_id"] else
    {
        return nil
    }
    if let stringId = id as? String {
        return stringId
    }
    if let nsnum = id as? NSNumber {
        return nsnum.stringValue
    }
    if let nested = try? JSONSerialization.data(withJSONObject: id, options: [.sortedKeys]),
       let encoded = String(data: nested, encoding: .utf8)
    {
        return encoded
    }
    return String(describing: id)
}

/// Writes a string to the platform clipboard. Centralising this avoids
/// scattering `#if os(macOS)` switches across every viewer.
func setClipboardString(_ value: String) {
    #if os(macOS)
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(value, forType: .string)
    #else
    UIPasteboard.general.string = value
    #endif
}
