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
            HStack(alignment: .center){
                Spacer()
                Button{
                    Task {
                        
                    }
                } label: {
                    Image(systemName: "play.fill")
                        .foregroundColor(.green)
                }
            }.padding(.top, 8)
             .padding(.trailing, 16)
            CodeEditor(source: $queryText, language: .sql, theme: .atelierSavannaDark)
        }
    }
}

#Preview {
    QueryEditorView(queryText: .constant("SELECT * FROM users"))
}
