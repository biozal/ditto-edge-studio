import HighlightSwift
import SwiftUI

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

/// Editable DQL editor with syntax highlighting powered by HighlightSwift — the
/// same Swift 6-clean engine the read-only JSON viewers use. Replaces the
/// unmaintained `CodeEditor`/`Highlightr` dependency, which was not compatible
/// with the Swift 6 language mode.
///
/// Highlighting is applied on a short debounce: as the user types, the plain
/// monospaced text is shown immediately and colours are layered on shortly
/// after, so editing never blocks on the (async) highlighter.
struct DQLCodeEditor: View {
    @Binding var text: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        DQLCodeEditorRepresentable(text: $text, isDark: colorScheme == .dark)
            // Stable identifier for XCUITest. The representable also sets the
            // identifier directly on the underlying NSTextView/UITextView (see
            // makeNSView/makeUIView) because AppKit/UIKit text views do not always
            // surface the SwiftUI-level identifier to the accessibility tree.
            .accessibilityIdentifier("QueryEditorTextView")
    }
}

private func dqlHighlightColors(isDark: Bool) -> HighlightColors {
    isDark ? .dark(.xcode) : .light(.xcode)
}

/// Upper bound on document size we attempt to syntax-highlight. Beyond this the
/// full-text re-highlight + attribute apply can stall the main thread, so very
/// large pastes fall back to plain monospaced text.
private let dqlMaxHighlightLength = 20000

// MARK: - macOS

#if os(macOS)
private struct DQLCodeEditorRepresentable: NSViewRepresentable {
    @Binding var text: String
    let isDark: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.hasVerticalScroller = true
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }

        textView.delegate = context.coordinator
        // NOTE: intentionally leave isRichText at its default (true). Setting it
        // false causes AppKit to strip the programmatic foreground-colour
        // attributes we apply for syntax highlighting. Substitutions are disabled
        // individually below so it still behaves like a code editor.
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.allowsUndo = true
        textView.font = Coordinator.editorFont
        textView.textContainerInset = NSSize(width: 6, height: 8)
        textView.string = text
        textView.typingAttributes = [
            .font: Coordinator.editorFont,
            .foregroundColor: NSColor.textColor
        ]
        // Surface a stable identifier to XCUITest directly on the AppKit view —
        // the SwiftUI `.accessibilityIdentifier` on the wrapper isn't reliably
        // mirrored onto NSViewRepresentable-hosted views.
        textView.setAccessibilityIdentifier("QueryEditorTextView")

        context.coordinator.textView = textView
        context.coordinator.scheduleHighlight()
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = nsView.documentView as? NSTextView else { return }
        // Only push the binding value INTO the text view for EXTERNAL changes
        // (e.g. a query prefilled by tapping a collection). While the text view
        // is being edited it is the source of truth — resetting it here to a
        // binding value that lags behind by a render cycle truncates in-flight
        // input (fast/programmatic typing loses everything after the lag point).
        let isEditing = textView.window?.firstResponder === textView
        if textView.string != text, !isEditing {
            let selected = textView.selectedRanges
            context.coordinator.isApplyingHighlight = true
            textView.string = text
            textView.selectedRanges = selected
            context.coordinator.isApplyingHighlight = false
            context.coordinator.scheduleHighlight()
        } else if context.coordinator.lastIsDark != isDark {
            context.coordinator.scheduleHighlight()
        }
        context.coordinator.lastIsDark = isDark
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        static let editorFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

        var parent: DQLCodeEditorRepresentable
        weak var textView: NSTextView?
        var highlightTask: Task<Void, Never>?
        var isApplyingHighlight = false
        var lastIsDark: Bool
        /// Per-editor highlighter (not a shared global) so multiple open editors
        /// don't serialize behind one another.
        private let highlighter = Highlight()

        init(_ parent: DQLCodeEditorRepresentable) {
            self.parent = parent
            lastIsDark = parent.isDark
        }

        isolated deinit {
            highlightTask?.cancel()
        }

        func textDidChange(_: Notification) {
            guard !isApplyingHighlight, let textView else { return }
            parent.text = textView.string
            scheduleHighlight()
        }

        func scheduleHighlight() {
            // Under UI tests, skip syntax highlighting entirely. It re-runs on
            // every keystroke and asynchronously rewrites the text storage,
            // which thrashes the app (multi-second idle waits) and races with
            // programmatically-typed input, dropping characters. Plain text is
            // all the tests need.
            guard !isRunningUITests() else { return }
            guard let textView else { return }
            let source = textView.string
            let isDark = parent.isDark
            highlightTask?.cancel()
            // Skip empty/whitespace-only input (HighlightSwift can trap on empty
            // rendered output — a trap the `try?` below would NOT catch) and very
            // large documents (avoid main-thread stalls). Plain text is shown as-is.
            guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  (source as NSString).length <= dqlMaxHighlightLength else { return }
            highlightTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled else { return }
                await self?.applyHighlight(source: source, isDark: isDark)
            }
        }

        private func applyHighlight(source: String, isDark: Bool) async {
            guard let textView, textView.string == source else { return }
            let colors = dqlHighlightColors(isDark: isDark)
            guard let attributed = try? await highlighter.attributedText(source, language: .sql, colors: colors) else { return }
            // Bail if the user edited while we were highlighting.
            guard textView.string == source else { return }

            let result = DQLHighlightApplier.styledString(
                source: source,
                highlighted: NSAttributedString(attributed),
                font: Self.editorFont,
                defaultColor: NSColor.textColor
            )
            let selected = textView.selectedRanges
            isApplyingHighlight = true
            textView.textStorage?.setAttributedString(result)
            textView.selectedRanges = selected
            textView.typingAttributes = [.font: Self.editorFont, .foregroundColor: NSColor.textColor]
            isApplyingHighlight = false
        }
    }
}

// MARK: - iOS

#elseif os(iOS)
private struct DQLCodeEditorRepresentable: UIViewRepresentable {
    @Binding var text: String
    let isDark: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.font = Coordinator.editorFont
        textView.autocorrectionType = .no
        textView.autocapitalizationType = .none
        textView.smartQuotesType = .no
        textView.smartDashesType = .no
        textView.spellCheckingType = .no
        textView.isEditable = true
        textView.isScrollEnabled = true
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 6, bottom: 8, right: 6)
        textView.text = text
        textView.typingAttributes = [
            .font: Coordinator.editorFont,
            .foregroundColor: UIColor.label
        ]
        // Surface a stable identifier to XCUITest directly on the UIKit view —
        // the SwiftUI `.accessibilityIdentifier` on the wrapper isn't reliably
        // mirrored onto UIViewRepresentable-hosted views.
        textView.accessibilityIdentifier = "QueryEditorTextView"

        context.coordinator.textView = textView
        context.coordinator.scheduleHighlight()
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        context.coordinator.parent = self
        if uiView.text != text {
            let selected = uiView.selectedRange
            context.coordinator.isApplyingHighlight = true
            uiView.text = text
            uiView.selectedRange = selected
            context.coordinator.isApplyingHighlight = false
            context.coordinator.scheduleHighlight()
        } else if context.coordinator.lastIsDark != isDark {
            context.coordinator.scheduleHighlight()
        }
        context.coordinator.lastIsDark = isDark
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        static let editorFont = UIFont.monospacedSystemFont(ofSize: 15, weight: .regular)

        var parent: DQLCodeEditorRepresentable
        weak var textView: UITextView?
        var highlightTask: Task<Void, Never>?
        var isApplyingHighlight = false
        var lastIsDark: Bool
        /// Per-editor highlighter (not a shared global).
        private let highlighter = Highlight()

        init(_ parent: DQLCodeEditorRepresentable) {
            self.parent = parent
            lastIsDark = parent.isDark
        }

        isolated deinit {
            highlightTask?.cancel()
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isApplyingHighlight else { return }
            parent.text = textView.text
            scheduleHighlight()
        }

        func scheduleHighlight() {
            guard let textView else { return }
            let source = textView.text ?? ""
            let isDark = parent.isDark
            highlightTask?.cancel()
            // See macOS note: skip empty/whitespace-only and oversized input.
            guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  (source as NSString).length <= dqlMaxHighlightLength else { return }
            highlightTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled else { return }
                await self?.applyHighlight(source: source, isDark: isDark)
            }
        }

        private func applyHighlight(source: String, isDark: Bool) async {
            guard let textView, textView.text == source else { return }
            let colors = dqlHighlightColors(isDark: isDark)
            guard let attributed = try? await highlighter.attributedText(source, language: .sql, colors: colors) else { return }
            guard textView.text == source else { return }

            let result = DQLHighlightApplier.styledString(
                source: source,
                highlighted: NSAttributedString(attributed),
                font: Self.editorFont,
                defaultColor: UIColor.label
            )
            let selected = textView.selectedRange
            isApplyingHighlight = true
            textView.attributedText = result
            textView.selectedRange = selected
            textView.typingAttributes = [.font: Self.editorFont, .foregroundColor: UIColor.label]
            isApplyingHighlight = false
        }
    }
}
#endif

// MARK: - Highlight application

/// Layers the highlighter's foreground colours onto the user's exact text while
/// forcing a uniform monospaced font. HighlightSwift trims leading/trailing
/// whitespace, so colour-run offsets are shifted by the leading-whitespace
/// length and bounds-checked before being applied.
private enum DQLHighlightApplier {
    #if os(macOS)
    typealias PlatformColor = NSColor
    typealias PlatformFont = NSFont
    #elseif os(iOS)
    typealias PlatformColor = UIColor
    typealias PlatformFont = UIFont
    #endif

    @MainActor
    static func styledString(
        source: String,
        highlighted: NSAttributedString,
        font: PlatformFont,
        defaultColor: PlatformColor
    ) -> NSMutableAttributedString {
        let result = NSMutableAttributedString(string: source)
        let fullLength = (source as NSString).length
        let fullRange = NSRange(location: 0, length: fullLength)
        result.addAttribute(.font, value: font, range: fullRange)
        result.addAttribute(.foregroundColor, value: defaultColor, range: fullRange)

        let leadingWhitespace = source.prefix { $0.isWhitespace || $0.isNewline }
        let leadingOffset = (String(leadingWhitespace) as NSString).length

        highlighted.enumerateAttribute(
            .foregroundColor,
            in: NSRange(location: 0, length: highlighted.length)
        ) { value, range, _ in
            guard let color = value else { return }
            let target = NSRange(location: range.location + leadingOffset, length: range.length)
            guard target.location >= 0, target.location + target.length <= fullLength else { return }
            result.addAttribute(.foregroundColor, value: color, range: target)
        }
        return result
    }
}
