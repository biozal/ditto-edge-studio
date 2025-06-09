//
//  ResultJsonViewer.swift
//  Ditto Edge Studio
//
//  Created by Aaron LaBeau on 5/23/25.
//

import CodeEditor
import SwiftUI

struct ResultJsonViewer: View {
    @Binding var resultText: [String]
    @Binding var resultCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ResultsHeader(count: resultCount)
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
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(items.indices, id: \.self) { index in
                    ResultItem(jsonString: items[index])
                        .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
    }
}

struct ResultItem: View {
    let jsonString: String
    @State private var isCopied = false
    
    var body: some View {
        LazyVStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(jsonString)
                    .font(.system(.body, design: .monospaced))
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                if isCopied {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .transition(.opacity)
                }
            }
            Divider()
                .padding(.top, 4)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            copyToClipboard()
        }
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.primary.opacity(0.05))
                .opacity(isCopied ? 1.0 : 0.0)
        )
        .animation(.easeInOut(duration: 0.3), value: isCopied)
    }
    
    private func copyToClipboard() {
#if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(jsonString, forType: .string)
#else
        UIPasteboard.general.string = jsonString
#endif
        
        // Show feedback
        withAnimation {
            isCopied = true
        }
        
        // Reset after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                isCopied = false
            }
        }
    }
}

#Preview {
    ResultJsonViewer(
        resultText: .constant([
            "{\n  \"id\": 1,\n  \"name\": \"Test\"\n}",
            "{\n  \"id\": 2,\n  \"name\": \"Sample\"\n}",
        ]),
        resultCount: .constant(2)
    )
    .frame(width: 400, height: 300)
}
