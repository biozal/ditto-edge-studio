//
//  ResultCardView.swift
//  Edge Studio
//
//  Created by Claude Code on 10/2/25.
//

import SwiftUI

struct ResultCardView: View {
    let items: [String]
    let attachmentFields: [String]
    var onDelete: ((String, String) -> Void)?
    var autoFetchAttachments: Bool = false

    @State private var selectedRecord: String?
    @State private var selectedIndex: Int?
    @State private var showModal = false

    private let columns = [
        GridItem(.adaptive(minimum: 300, maximum: 500), spacing: 16)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(items.indices, id: \.self) { index in
                    ResultCard(
                        jsonString: items[index],
                        index: index,
                        onTap: {
                            selectedRecord = items[index]
                            selectedIndex = index
                            showModal = true
                        },
                        onDelete: onDelete
                    )
                }
            }
            .padding()
        }
        .sheet(isPresented: $showModal) {
            if let record = selectedRecord {
                RecordDetailModal(
                    jsonString: record,
                    index: selectedIndex,
                    attachmentFields: attachmentFields,
                    autoFetchAttachments: autoFetchAttachments,
                    isPresented: $showModal
                )
            }
        }
    }
}

struct ResultCard: View {
    let jsonString: String
    let index: Int
    let onTap: () -> Void
    var onDelete: ((String, String) -> Void)?

    @State private var isCopied = false
    @State private var isExpanded = false
    @State private var isHovered = false

    private var documentId: String? {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = json["_id"] as? String else {
            return nil
        }
        return id
    }

    private var collectionName: String? {
        // Try to extract collection name from the query or document structure
        // For now, we'll return nil and handle it when we have the query context
        return nil
    }

    private var parsedFields: [(key: String, value: String)] {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }

        return json.map { (key: $0.key, value: formatValue($0.value)) }
            .sorted { $0.key < $1.key }
    }

    private func formatValue(_ value: Any) -> String {
        if let string = value as? String {
            return string
        } else if let number = value as? NSNumber {
            return number.stringValue
        } else if let bool = value as? Bool {
            return bool ? "true" : "false"
        } else if value is NSNull {
            return "null"
        } else if let array = value as? [Any] {
            return "[\(array.count) items]"
        } else if let dict = value as? [String: Any] {
            return "{\(dict.count) fields}"
        }
        return "\(value)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Card header
            HStack {
                Text("Document \(index + 1)")
                    .font(.headline)
                    .foregroundColor(.primary)

                Spacer()

                HStack(spacing: 8) {
                    Button {
                        withAnimation {
                            isExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(isExpanded ? "Collapse" : "Expand")

                    Button {
                        copyToClipboard()
                    } label: {
                        if isCopied {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        } else {
                            Image(systemName: "doc.on.doc")
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Copy to clipboard")
                }
            }
            .padding(12)
            .background(Color.primary.opacity(0.05))

            Divider()

            // Card content
            VStack(alignment: .leading, spacing: 8) {
                if isExpanded {
                    // Show full JSON
                    Text(jsonString)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                } else {
                    // Show key-value pairs
                    if parsedFields.isEmpty {
                        Text("Invalid JSON")
                            .foregroundColor(.secondary)
                            .padding(12)
                    } else {
                        ForEach(parsedFields.prefix(5), id: \.key) { field in
                            HStack(alignment: .top, spacing: 8) {
                                Text(field.key)
                                    .font(.system(.caption, design: .monospaced))
                                    .fontWeight(.semibold)
                                    .foregroundColor(.secondary)
                                    .frame(width: 100, alignment: .leading)
                                    .lineLimit(1)

                                Text(field.value)
                                    .font(.system(.body, design: .monospaced))
                                    .lineLimit(2)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.horizontal, 12)
                        }
                        .padding(.vertical, 4)

                        if parsedFields.count > 5 {
                            Text("+\(parsedFields.count - 5) more fields")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 12)
                                .padding(.bottom, 8)
                        }
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                onTap()
            }
        }
        .background(isHovered ? Color.primary.opacity(0.08) : Color.primary.opacity(0.03))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isHovered ? Color.accentColor.opacity(0.5) : Color.primary.opacity(0.1), lineWidth: isHovered ? 2 : 1)
        )
        .animation(.easeInOut(duration: 0.2), value: isExpanded)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
        .help("Click to view full record")
        .contextMenu {
            Button {
                copyToClipboard()
            } label: {
                Label("Copy JSON", systemImage: "doc.on.doc")
            }

            if let docId = documentId, let deleteHandler = onDelete {
                Divider()
                Button(role: .destructive) {
                    deleteHandler(docId, "")  // Collection name will be filled in by the handler
                } label: {
                    Label("Delete Document", systemImage: "trash")
                }
            }
        }
    }

    private func copyToClipboard() {
        #if os(macOS)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(jsonString, forType: .string)
        #else
            UIPasteboard.general.string = jsonString
        #endif

        withAnimation {
            isCopied = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                isCopied = false
            }
        }
    }
}

#Preview {
    ResultCardView(
        items: [
            """
            {
              "_id": "123abc",
              "name": "John Doe",
              "email": "john@example.com",
              "age": 30,
              "active": true,
              "tags": ["developer", "designer"],
              "metadata": {
                "created": "2025-01-01",
                "updated": "2025-10-02"
              }
            }
            """,
            """
            {
              "_id": "456def",
              "name": "Jane Smith",
              "email": "jane@example.com",
              "age": 28,
              "active": false,
              "tags": ["manager"]
            }
            """
        ],
        attachmentFields: []
    )
    .frame(width: 800, height: 600)
}
