/// Tracks the last text synchronized in either direction between a code editor
/// and its model. A focused editor may have newer input than a repeated render,
/// but a changed model value must still replace the displayed query.
struct DQLTextReconciliation {
    private var lastSynchronizedText: String?

    mutating func recordEditorChange(_ text: String) {
        lastSynchronizedText = text
    }

    mutating func shouldApply(modelText: String, editorText: String, isFocused: Bool) -> Bool {
        guard modelText != editorText else {
            lastSynchronizedText = modelText
            return false
        }
        guard !isFocused || modelText != lastSynchronizedText else { return false }

        // A programmatic write also advances the baseline. Otherwise a later
        // selection of the last typed query is mistaken for a stale render.
        lastSynchronizedText = modelText
        return true
    }
}
