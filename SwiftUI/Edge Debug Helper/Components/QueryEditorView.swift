import CodeEditor
//
//  QueryEditorView.swift
//  Edge Studio
//
//  Created by Aaron LaBeau on 5/23/25.
//
import SwiftUI

struct QueryEditorView: View {
    @Binding var queryText: String
    @Binding var executeModes: [String]
    @Binding var selectedExecuteMode: String
    @Binding var isLoading: Bool
    var onExecuteQuery: () async -> Void

    @AppStorage("autoFetchAttachments") private var autoFetchAttachments = false

    private var hasAttachments: Bool {
        !AttachmentQueryParser.extractAttachmentFields(from: queryText).isEmpty
    }

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
                //query button
                Button {
                    Task {
                        await onExecuteQuery()
                    }
                } label: {
                    if (isLoading) {
                        Image(systemName: "play.fill")
                            .foregroundColor(.gray)
                            .accessibilityLabel("Execute Query")
                    } else {
                        Image(systemName: "play.fill")
                            .foregroundColor(.green)
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

                // Auto-fetch toggle (only show if query has attachments)
                if hasAttachments {
                    Toggle(isOn: $autoFetchAttachments) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down.circle")
                            Text("Auto-fetch")
                        }
                        .font(.caption)
                    }
                    .toggleStyle(.button)
                    .help("Automatically fetch attachment data when query executes")
                    .padding(.trailing, 8)
                }
            }
            .padding(.top, 8)
            .padding(.horizontal, 16)
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
        onExecuteQuery: { }
    )

}
