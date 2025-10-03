//
//  ResultTableView.swift
//  Edge Studio
//
//  Created by Claude Code on 10/2/25.
//

import SwiftUI

struct ResultTableView: View {
    let items: [String]
    let attachmentFields: [String]
    var onDelete: ((String, String) -> Void)?
    var hasExecutedQuery: Bool = false

    @State private var selectedRecord: String?
    @State private var selectedIndex: Int?
    @State private var showModal = false

    // Extract all unique keys from all JSON objects
    private var allKeys: [String] {
        var keys = Set<String>()

        for jsonString in items {
            guard let data = jsonString.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            keys.formUnion(json.keys)
        }

        return Array(keys).sorted()
    }

    // Parse JSON items into dictionaries
    private var parsedItems: [[String: Any]] {
        items.compactMap { jsonString in
            guard let data = jsonString.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            return json
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if parsedItems.isEmpty {
                Text(hasExecutedQuery ? "No data to display" : "Run a query for data")
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                // Header row
                HStack(spacing: 0) {
                    // Row number column
                    Text("#")
                        .font(.system(.caption, design: .monospaced))
                        .fontWeight(.bold)
                        .frame(width: 50)
                        .padding(8)
                        .background(Color.primary.opacity(0.1))

                    ForEach(allKeys, id: \.self) { key in
                        TableHeaderCell(title: key)
                    }
                }

                Divider()

                // Data rows
                ForEach(parsedItems.indices, id: \.self) { index in
                    let documentId = parsedItems[index]["_id"] as? String
                    HStack(spacing: 0) {
                        // Row number
                        Text("\(index + 1)")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(width: 50)
                            .padding(8)
                            .background(
                                index % 2 == 0
                                    ? Color.clear
                                    : Color.primary.opacity(0.03)
                            )

                        ForEach(allKeys, id: \.self) { key in
                            TableCell(
                                value: parsedItems[index][key],
                                isEvenRow: index % 2 == 0
                            )
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedRecord = items[index]
                        selectedIndex = index
                        showModal = true
                    }
                    .help("Click to view full record")
                    .contextMenu {
                        Button {
                            copyRowToClipboard(index: index)
                        } label: {
                            Label("Copy JSON", systemImage: "doc.on.doc")
                        }

                        if let docId = documentId, let deleteHandler = onDelete {
                            Divider()
                            Button(role: .destructive) {
                                print("[ResultTableView] Delete requested for document ID: \(docId)")
                                deleteHandler(docId, "")  // Collection name will be filled in by the handler
                            } label: {
                                Label("Delete Document", systemImage: "trash")
                            }
                        }
                    }

                    if index < parsedItems.count - 1 {
                        Divider()
                    }
                }
            }
        }
        .sheet(isPresented: $showModal) {
            if let record = selectedRecord {
                RecordDetailModal(
                    jsonString: record,
                    index: selectedIndex,
                    attachmentFields: attachmentFields,
                    isPresented: $showModal
                )
            }
        }
    }

    private func copyRowToClipboard(index: Int) {
        guard index < items.count else { return }
        let jsonString = items[index]

        #if os(macOS)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(jsonString, forType: .string)
        #else
            UIPasteboard.general.string = jsonString
        #endif
    }
}

struct TableHeaderCell: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(.caption, design: .monospaced))
            .fontWeight(.bold)
            .lineLimit(1)
            .frame(minWidth: 120, maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(Color.primary.opacity(0.1))
            .help(title)
    }
}

struct TableCell: View {
    let value: Any?
    let isEvenRow: Bool

    private var displayValue: String {
        guard let value = value else {
            return ""
        }

        if let string = value as? String {
            return string
        } else if let number = value as? NSNumber {
            return number.stringValue
        } else if let bool = value as? Bool {
            return bool ? "true" : "false"
        } else if value is NSNull {
            return "null"
        } else if let array = value as? [Any] {
            if let jsonData = try? JSONSerialization.data(withJSONObject: array),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                return jsonString
            }
            return "[\(array.count)]"
        } else if let dict = value as? [String: Any] {
            if let jsonData = try? JSONSerialization.data(withJSONObject: dict),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                return jsonString
            }
            return "{\(dict.count)}"
        }
        return "\(value)"
    }

    var body: some View {
        Text(displayValue)
            .font(.system(.body, design: .monospaced))
            .lineLimit(3)
            .frame(minWidth: 120, maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
            .padding(8)
            .background(
                isEvenRow
                    ? Color.clear
                    : Color.primary.opacity(0.03)
            )
    }
}

#Preview {
    ResultTableView(
        items: [
            """
            {
              "_id": "123abc",
              "name": "John Doe",
              "email": "john@example.com",
              "age": 30,
              "active": true
            }
            """,
            """
            {
              "_id": "456def",
              "name": "Jane Smith",
              "email": "jane@example.com",
              "age": 28,
              "active": false,
              "city": "New York"
            }
            """,
            """
            {
              "_id": "789ghi",
              "name": "Bob Johnson",
              "age": 35,
              "active": true
            }
            """
        ],
        attachmentFields: []
    )
    .frame(width: 800, height: 400)
}
