//
//  JsonSyntaxView.swift
//  Edge Debug Helper
//
//  Created by Claude Code on 2026-02-09.
//  Reusable JSON syntax highlighting view using HighlightSwift
//

import HighlightSwift
import SwiftUI

/// A view that displays JSON with syntax highlighting and copy functionality
struct JsonSyntaxView: View {
    let jsonString: String

    @State private var showCopiedFeedback = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Toolbar with copy button
            HStack {
                Spacer()

                Button(action: {
                    copyToClipboard()
                }, label: {
                    HStack(spacing: 4) {
                        if showCopiedFeedback {
                            Image(systemName: "checkmark")
                                .foregroundColor(.green)
                        } else {
                            Image(systemName: "doc.on.doc")
                        }
                        Text(showCopiedFeedback ? "Copied!" : "Copy")
                            .font(.caption)
                    }
                })
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            .padding(.bottom, 4)

            Divider()

            // Syntax-highlighted JSON
            CodeText(jsonString)
                .highlightLanguage(.json)
                .codeTextColors(.theme(.github))
                .font(.system(.body, design: .monospaced))
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.05))
        }
        .frame(maxWidth: .infinity)
    }

    private func copyToClipboard() {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(jsonString, forType: .string)
        #elseif os(iOS)
        UIPasteboard.general.string = jsonString
        #endif

        // Show feedback
        withAnimation {
            showCopiedFeedback = true
        }

        // Reset after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                showCopiedFeedback = false
            }
        }
    }
}

#Preview("Valid JSON") {
    JsonSyntaxView(jsonString: """
    {
        "id": 1,
        "name": "John Doe",
        "age": 30,
        "active": true,
        "email": "john@example.com",
        "tags": ["developer", "swift", "ios"],
        "address": {
            "street": "123 Main St",
            "city": "San Francisco",
            "state": "CA"
        }
    }
    """)
    .frame(width: 400, height: 500)
}

#Preview("Empty JSON Object") {
    JsonSyntaxView(jsonString: "{}")
        .frame(width: 400, height: 300)
}

#Preview("Empty JSON Array") {
    JsonSyntaxView(jsonString: "[]")
        .frame(width: 400, height: 300)
}

#Preview("Malformed JSON") {
    JsonSyntaxView(jsonString: "{invalid json")
        .frame(width: 400, height: 300)
}

#Preview("Large JSON") {
    // Simplified large JSON for preview
    var largeJson = "{\n    \"users\": [\n"
    for i in 1 ... 50 {
        largeJson += """
        {
            "id": \(i),
            "name": "User \(i)",
            "email": "user\(i)@example.com",
            "active": true
        }\(i < 50 ? "," : "")

        """
    }
    largeJson += "\n    ]\n}"

    return JsonSyntaxView(jsonString: largeJson)
        .frame(width: 400, height: 500)
}
