import CodeEditor
import SwiftUI

struct QueryEditorView: View {
    @Binding var queryText: String
    @Binding var executeModes: [String]
    @Binding var selectedExecuteMode: String
    @Binding var isLoading: Bool
    var onExecuteQuery: () async -> Void

    var body: some View {
        VStack(alignment: .leading) {
            HStack(alignment: .center) {
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
                // query button
                Button {
                    Task {
                        await onExecuteQuery()
                    }
                } label: {
                    if isLoading {
                        FontAwesomeText(icon: NavigationIcon.play, size: 14, color: .gray)
                            .accessibilityLabel("Execute Query")
                    } else {
                        FontAwesomeText(icon: NavigationIcon.play, size: 14, color: .green)
                            .accessibilityLabel("Execute Query")
                    }
                }.disabled(isLoading)

                if isLoading {
                    #if os(macOS)
                    HStack {
                        ProgressView()
                            .scaleEffect(1.5)
                            .controlSize(.mini)
                    }
                    .padding(1)
                    .background(Color(NSColor.windowBackgroundColor).opacity(0.9))
                    .cornerRadius(10)
                    #else
                    HStack {
                        ProgressView()
                            .scaleEffect(1.5)
                    }
                    .padding(1)
                    .background(Color(UIColor.systemBackground).opacity(0.9))
                    .cornerRadius(10)
                    .shadow(radius: 5)
                    #endif
                }
                Spacer()
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
        executeModes: .constant(["Local", "HTTP"]),
        selectedExecuteMode: .constant("Local"),
        isLoading: .constant(false),
        onExecuteQuery: {}
    )
}
