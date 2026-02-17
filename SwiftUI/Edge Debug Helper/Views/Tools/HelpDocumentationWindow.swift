import SwiftUI

/// Help documentation window with Markdown content loading and error handling
struct HelpDocumentationWindow: View {
    @Environment(\.dismiss) private var dismiss
    @State private var markdownContent = ""
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header with title and close button
            headerView

            Divider()

            // Content area with loading/error states
            if isLoading {
                ProgressView("Loading help documentation...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                errorView(error)
            } else {
                HelpContentView(markdownContent: markdownContent)
            }
        }
        .frame(minWidth: 800, maxWidth: .infinity, minHeight: 600, maxHeight: .infinity)
        .onAppear {
            loadHelpContent()
        }
    }

    private var headerView: some View {
        HStack {
            Text("Edge Debug Helper - User Guide")
                .font(.headline)
                .fontWeight(.semibold)

            Spacer()

            Button {
                NSApplication.shared.keyWindow?.close()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .background(Color.clear)
            .help("Close Help Window")
            .accessibilityIdentifier("CloseHelpButton")
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.orange)

            Text("Error Loading Help")
                .font(.headline)

            Text(message)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadHelpContent() {
        // Load from app bundle (file is in root of Resources folder)
        guard let helpURL = Bundle.main.url(
            forResource: "UserGuide",
            withExtension: "md"
        ) else {
            errorMessage = "Could not find UserGuide.md in app bundle.\nEnsure UserGuide.md is added to Copy Bundle Resources build phase."
            isLoading = false
            return
        }

        do {
            markdownContent = try String(contentsOf: helpURL, encoding: .utf8)
            isLoading = false
        } catch {
            errorMessage = "Failed to load help content: \(error.localizedDescription)"
            isLoading = false
        }
    }
}

#Preview {
    HelpDocumentationWindow()
}
