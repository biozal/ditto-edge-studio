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

// Separate component for each result item
struct ResultItem: View {
    let jsonString: String

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 4) {
            Text(jsonString)
                .font(.system(.body, design: .monospaced))
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)

            Divider()
                .padding(.top, 4)
        }
    }
}

#Preview {
    ResultJsonViewer(
        resultText: .constant([
            "{\n  \"id\": 1,\n  \"name\": \"Test\"\n}",
            "{\n  \"id\": 2,\n  \"name\": \"Sample\"\n}",
        ])
    )
    .frame(width: 400, height: 300)
}
