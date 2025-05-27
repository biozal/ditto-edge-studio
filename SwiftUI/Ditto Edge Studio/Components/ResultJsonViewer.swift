//
//  ResultJsonViewer.swift
//  Ditto Edge Studio
//
//  Created by Aaron LaBeau on 5/23/25.
//

import SwiftUI
import CodeEditor

struct ResultJsonViewer: View {
    @Binding var resultText: [String]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ResultsHeader(count: resultText.count)
            ResultsList(items: resultText)
        }
    }
}

// Separate component for the header
struct ResultsHeader: View {
    let count: Int
    
    var body: some View {
        Text("Results: \(count) items")
            .font(.headline)
            .padding(.horizontal)
    }
}

// Separate component for the list
struct ResultsList: View {
    let items: [String]
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(items.enumerated()), id: \.offset) { index, jsonString in
                        ResultItem(jsonString: jsonString)
                            .id(index)
                            .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
        }
    }
}

// Separate component for each result item
struct ResultItem: View {
    let jsonString: String
    
    var body: some View {
        LazyVStack(alignment: .leading, spacing: 4) {
            HighlightedJSONView(jsonString: jsonString)
                .font(.system(.body, design: .monospaced))
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            Divider()
                .padding(.top, 4)
        }
    }
}

struct HighlightedJSONView: View {
    let jsonString: String
    
    var body: some View {
        Text(AttributedString(highlightJSON(jsonString)))
            .font(.system(.body, design: .monospaced))
    }
    
    private func highlightJSON(_ jsonString: String) -> NSAttributedString {
        let attributedString = NSMutableAttributedString(string: jsonString)
        
        #if os(macOS)
        // Regular expressions for different JSON elements
        let patterns: [(pattern: String, color: NSColor)] = [
            // Property keys (with quotes, followed by colon)
            ("(\"[^\"]+\")\\s*:", .green),
            
            // String values (in quotes, not followed by colon)
            //(":\\s*(\"[^\"]+\")", .white),
            
            // Numbers
            (":\\s*(-?\\d+(\\.\\d+)?)", NSColor.orange),
            
            // Boolean and null values
            (":\\s*(true|false|null)", NSColor.red)
        ]
        #else
        // Regular expressions for different JSON elements
        let patterns: [(pattern: String, color: UIColor)] = [
            // Property keys (with quotes, followed by colon)
            ("(\"[^\"]+\")\\s*:", .green),
            
            // String values (in quotes, not followed by colon)
            (":\\s*(\"[^\"]+\")", .blue),
            
            // Numbers
            (":\\s*(-?\\d+(\\.\\d+)?)", UIColor.orange),
            
            // Boolean and null values
            (":\\s*(true|false|null)", UIColor.red)
        ]
        
        #endif
        
        // Apply highlighting
        for (pattern, color) in patterns {
            do {
                let regex = try NSRegularExpression(pattern: pattern, options: [])
                let range = NSRange(jsonString.startIndex..<jsonString.endIndex, in: jsonString)
                
                regex.enumerateMatches(in: jsonString, options: [], range: range) { match, _, _ in
                    if let match = match {
                        let matchRange = match.range(at: 1)
                        attributedString.addAttribute(.foregroundColor, value: color, range: matchRange)
                    }
                }
            } catch {
                print("Regex error: \(error)")
            }
        }
        
        return attributedString
    }
}

#Preview {
    ResultJsonViewer(
        resultText: .constant([
            "{\n  \"id\": 1,\n  \"name\": \"Test\"\n}",
            "{\n  \"id\": 2,\n  \"name\": \"Sample\"\n}"
        ])
    )
    .frame(width: 400, height: 300)
}
