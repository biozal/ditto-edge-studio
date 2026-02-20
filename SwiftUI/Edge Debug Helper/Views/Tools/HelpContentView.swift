import SwiftUI
import Textual

/// Renders Markdown content using Textual with clickable links and text selection
struct HelpContentView: View {
    let markdownContent: String

    var body: some View {
        ScrollView {
            StructuredText(markdown: markdownContent)
                .textSelection(.enabled) // Allow copying text
                .environment(\.openURL, OpenURLAction { url in
                    // Open all links in system browser
                    NSWorkspace.shared.open(url)
                    return .handled
                })
                .padding()
                .padding(.bottom, 48) // Extra clearance for ConnectionStatusBar overlay
        }
    }
}

#Preview {
    HelpContentView(markdownContent: """
    # Sample Help

    This is **bold** and *italic* text.

    Visit [Ditto](https://ditto.live) for more info.
    """)
}
