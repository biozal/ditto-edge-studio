//
//  QueryEditorView.swift
//  Ditto Edge Studio
//
//  Created by Aaron LaBeau on 5/23/25.
//
import SwiftUI
import CodeEditor

struct QueryEditorView : View {
    @Binding var queryText: String
    var body: some View {
        VStack(alignment: .leading) {
            Text("Query Editor")
                .font(.headline)
                .padding(.horizontal)
            CodeEditor(source: queryText, language: .sql, theme: .atelierSavannaDark)
        }
    }
}
