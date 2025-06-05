//
//  AddObserverView.swift
//  Ditto Edge Studio
//
//  Created by Aaron LaBeau on 6/2/25.
//

import CodeEditor
import SwiftUI

struct ObserverEditorView: View {
    @EnvironmentObject private var appState: DittoApp
    @StateObject private var viewModel: ViewModel
    
#if os(macOS)
    @AppStorage("fontsize") var fontSize = Int(NSFont.systemFontSize)
#endif
    
    init(isPresented: Binding<Bool>, selectedObservable: DittoObservable) {
        self._viewModel = StateObject(
            wrappedValue: ViewModel(
                isPresented: isPresented,
                selectedObservable: selectedObservable
            )
        )
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Basic Information") {
                    TextField("Name", text: $viewModel.name)
                }
                Section("Query") {
#if os(macOS)
                    CodeEditor(
                        source: $viewModel.query,
                        language: .sql,
                        theme: .atelierSavannaDark,
                        fontSize: .init(get: { CGFloat(fontSize)  },
                                               set: { fontSize = Int($0) }))
                    .frame(minWidth: 640, minHeight: 150)
#else
                    CodeEditor(source: $viewModel.query,
                               language: .sql,
                               theme: .atelierSavannaDark)
#endif
                }
                Section("Arguments (Optional)") {
#if os(macOS)
                    CodeEditor(
                        source: $viewModel.arguments,
                        language: .sql,
                        theme: .atelierSavannaDark,
                        fontSize: .init(get: { CGFloat(fontSize)  },
                                        set: { fontSize = Int($0) }))
                    .frame(minWidth: 640, minHeight: 150)
#else
                    CodeEditor(
                        source: $viewModel.arguments,
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
                viewModel.name == "" ? "Add Observer" : "Edit Observer"
            )
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        viewModel.isPresented = false
                    } label: {
                        Label("Cancel", systemImage: "xmark")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            do {
                                try await viewModel.saveObserver(appState: appState)
                            } catch {
                                appState.setError(error)
                            }
                            viewModel.isPresented = false
                        }
                    }
                    .disabled(
                        (viewModel.name.isEmpty || viewModel.query.isEmpty)
                    )
                }
            }
        }
    }
}

#Preview {
    ObserverEditorView(
        isPresented: .constant(true),
        selectedObservable: DittoObservable.new()
    )
}

extension ObserverEditorView {
    class ViewModel : ObservableObject {
        @Binding var presentationBinding: Bool
        var selectedObservable: DittoObservable
        
        let _id: String
        @Published var name: String
        @Published var query: String
        @Published var arguments: String
        
        let isNewItem: Bool
        
        var isPresented: Bool {
            get { presentationBinding }
            set { presentationBinding = newValue }
        }
        
        init(isPresented: Binding<Bool>, selectedObservable: DittoObservable) {
            self._presentationBinding = isPresented
            self.selectedObservable = selectedObservable
            
            if selectedObservable.name == "" && selectedObservable.query == "" {
                self.isNewItem = true
            } else {
                self.isNewItem = false
            }
            
            self._id = selectedObservable.id
            self.name = selectedObservable.name
            self.query = selectedObservable.query
            self.arguments = selectedObservable.args ?? ""
        }
        
        func saveObserver(appState: DittoApp) async throws {
            selectedObservable.name = name
            selectedObservable.query = query

            if !arguments.isEmpty {
                selectedObservable.args = arguments
            } else {
                selectedObservable.args = nil
            }
            Task {
                try await DittoManager.shared.saveDittoObservable(selectedObservable)
            }
        }
    }
}
