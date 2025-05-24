import CodeEditor
//
//  QueryEditorView.swift
//  Ditto Edge Studio
//
//  Created by Aaron LaBeau on 5/23/25.
//
import SwiftUI

struct QueryEditorView: View {
    @Binding var queryText: String
    @Binding var executeModes: [String]
    @State private var selectedExecuteMode: String = ""

    var body: some View {
        VStack(alignment: .leading) {
            HStack(alignment: .center) {
                Spacer()
                // Dropdown for execute modes
                Picker("", selection: $selectedExecuteMode) {
                    ForEach(executeModes, id: \.self) { mode in
                        Text(mode).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 120)
                .onAppear {
                    if !executeModes.isEmpty && selectedExecuteMode.isEmpty {
                        selectedExecuteMode = executeModes[0]
                    }
                }
                //query button
                Button {
                    Task {

                    }
                } label: {
                    Image(systemName: "play.fill")
                        .foregroundColor(.green)
                }
            }.padding(.top, 8)
                .padding(.trailing, 16)
            CodeEditor(
                source: $queryText,
                language: .sql,
                theme: .atelierSavannaDark
            )
        }
    }
}

#Preview {
    QueryEditorView(
        queryText: .constant("SELECT * FROM users"),
        executeModes: .constant(["Local", "HTTP"])
    )

}
