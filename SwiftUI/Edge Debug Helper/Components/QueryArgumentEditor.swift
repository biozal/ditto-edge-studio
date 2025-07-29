//
//  QueryArgumentEditor.swift
//  Edge Studio
//
//  Created by Aaron LaBeau on 6/2/25.
//

import CodeEditor
import SwiftUI

struct QueryArgumentEditor: View {
    @EnvironmentObject private var appState: AppState

    @State var title: String
    @State var name: String
    @State var query: String
    @State var arguments: String
    
    let onSave: (String, String, String?, AppState) -> Void
    let onCancel: () -> Void
    
#if os(macOS)
    @AppStorage("fontsize") var fontSize = Int(NSFont.systemFontSize)
#endif
    
    init(title: String = "",
         name: String = "",
         query: String = "",
         arguments: String = "",
         onSave: @escaping (String, String, String?, AppState) -> Void,
         onCancel: @escaping () -> Void) {
        
        self._title = State(initialValue: title)
        self._name = State(initialValue: name)
        self._query = State(initialValue: query)
        self._arguments = State(initialValue: arguments)
        
        self.onSave = onSave
        self.onCancel = onCancel
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Basic Information") {
                    TextField("Name", text: $name)
                        .padding(.bottom, 20)
                }
                Section("Query") {
#if os(macOS)
                    CodeEditor(
                        source: $query,
                        language: .sql,
                        theme: .atelierSavannaDark,
                        fontSize: .init(get: { CGFloat(fontSize)  },
                                               set: { fontSize = Int($0) }))
                    .frame(minWidth: 640, minHeight: 150)
#else
                    CodeEditor(source: $query,
                               language: .sql,
                               theme: .atelierSavannaDark)
#endif
                    Text("Ex: SELECT * FROM collectionName")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 20)
                }
                Section("Arguments (Optional)") {
#if os(macOS)
                    CodeEditor(
                        source: $arguments,
                        language: .sql,
                        theme: .atelierSavannaDark,
                        fontSize: .init(get: { CGFloat(fontSize)  },
                                        set: { fontSize = Int($0) }))
                    .frame(minWidth: 640, minHeight: 150)
#else
                    CodeEditor(
                        source: $arguments,
                        language: .sql,
                        theme: .atelierSavannaDark
                    )
                  
#endif
                    Text("JSON String Format - Ex: [{\"key\": \"value\"}]")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 10)
                }
            }
#if os(macOS)
            .padding()
#endif
            .navigationTitle(
                title
            )
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        onCancel()
                    } label: {
                        Label("Cancel", systemImage: "xmark")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                                onSave(name, query, arguments.isEmpty ? nil : arguments, appState)
                        }
                    }
                    .disabled(
                        (name.isEmpty || query.isEmpty)
                    )
                }
            }
        }
    }
}

#Preview {
    let onSave: (String, String, String?, AppState) -> Void = { _, _, _, _ in }
    let onCancel: () -> Void = { }
    
    QueryArgumentEditor(
        title: "Test Title",
        name: "test Query",
        query: "SELECT * FROM test",
        arguments: "[{\"key\": \"value\"}]",
        onSave: onSave,
        onCancel: onCancel
    )
    .environmentObject(AppState())
}
