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
    var autoFetchAttachments: Bool = false

    @State private var modalRecord: ModalRecord?
    @State private var columnWidths: [String: CGFloat] = [:]

    struct ModalRecord: Identifiable {
        let id = UUID()
        let jsonString: String
        let index: Int?
    }

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

    private func getColumnWidth(_ key: String) -> CGFloat {
        columnWidths[key] ?? 200
    }

    private func setColumnWidth(_ key: String, width: CGFloat) {
        columnWidths[key] = max(50, min(width, 800))
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
                HStack(alignment: .top, spacing: 0) {
                    // Row number column
                    Text("#")
                        .font(.system(.caption, design: .monospaced))
                        .fontWeight(.bold)
                        .frame(width: 50, alignment: .leading)
                        .padding(8)
                        .background(Color.primary.opacity(0.1))

                    ForEach(allKeys, id: \.self) { key in
                        ResizableTableHeaderCell(
                            title: key,
                            width: getColumnWidth(key),
                            onWidthChange: { newWidth in
                                setColumnWidth(key, width: newWidth)
                            }
                        )
                    }
                }

                Divider()

                // Data rows
                ForEach(parsedItems.indices, id: \.self) { index in
                    let documentId = parsedItems[index]["_id"] as? String
                    TableRow(
                        index: index,
                        allKeys: allKeys,
                        parsedItems: parsedItems,
                        items: items,
                        documentId: documentId,
                        columnWidths: allKeys.reduce(into: [:]) { result, key in
                            result[key] = getColumnWidth(key)
                        },
                        onDelete: onDelete,
                        onRowTap: { rowIndex in
                            print("[ResultTableView] Row tapped, index: \(rowIndex)")
                            print("[ResultTableView] Total items: \(items.count)")
                            if rowIndex < items.count {
                                let record = items[rowIndex]
                                print("[ResultTableView] Record at index \(rowIndex): \(record.prefix(200))")
                                modalRecord = ModalRecord(jsonString: record, index: rowIndex)
                                print("[ResultTableView] modalRecord set with data")
                            } else {
                                print("[ResultTableView] ERROR: Index out of bounds!")
                            }
                        },
                        onCopyRow: copyRowToClipboard
                    )

                    if index < parsedItems.count - 1 {
                        Divider()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(item: $modalRecord) { record in
            let _ = print("[ResultTableView] ===== SHEET PRESENTING =====")
            let _ = print("[ResultTableView] Presenting modal with record at index \(String(describing: record.index))")
            let _ = print("[ResultTableView] Record length: \(record.jsonString.count) chars")
            let _ = print("[ResultTableView] Record preview: \(record.jsonString.prefix(100))")
            let _ = print("[ResultTableView] attachmentFields: \(attachmentFields)")

            RecordDetailModal(
                jsonString: record.jsonString,
                index: record.index,
                attachmentFields: attachmentFields,
                autoFetchAttachments: autoFetchAttachments,
                isPresented: Binding(
                    get: { modalRecord != nil },
                    set: { if !$0 { modalRecord = nil } }
                )
            )
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

struct TableRow: View {
    let index: Int
    let allKeys: [String]
    let parsedItems: [[String: Any]]
    let items: [String]
    let documentId: String?
    let columnWidths: [String: CGFloat]
    let onDelete: ((String, String) -> Void)?
    let onRowTap: (Int) -> Void
    let onCopyRow: (Int) -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Row number
            Text("\(index + 1)")
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 50, alignment: .leading)
                .padding(8)

            ForEach(allKeys, id: \.self) { key in
                TableCell(
                    value: parsedItems[index][key],
                    isEvenRow: index % 2 == 0,
                    isHovered: false,  // Pass false since background is on row now
                    width: columnWidths[key] ?? 200
                )
            }
        }
        .background(rowBackground)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture {
            onRowTap(index)
        }
        .help("Click to view full record")
        .contextMenu {
            Button {
                onCopyRow(index)
            } label: {
                Label("Copy JSON", systemImage: "doc.on.doc")
            }

            if let docId = documentId, let deleteHandler = onDelete {
                Divider()
                Button(role: .destructive) {
                    print("[ResultTableView] Delete requested for document ID: \(docId)")
                    deleteHandler(docId, "")
                } label: {
                    Label("Delete Document", systemImage: "trash")
                }
            }
        }
    }

    private var rowBackground: Color {
        if isHovered {
            return Color.accentColor.opacity(0.15)
        } else if index % 2 == 0 {
            return Color.clear
        } else {
            return Color.primary.opacity(0.03)
        }
    }
}

struct TableHeaderCell: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(.caption, design: .monospaced))
            .fontWeight(.bold)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .frame(maxWidth: 200, alignment: .leading)
            .padding(8)
            .background(Color.primary.opacity(0.1))
            .help(title)
    }
}

struct TableCell: View {
    let value: Any?
    let isEvenRow: Bool
    var isHovered: Bool = false
    var width: CGFloat = 200

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

    private var truncatedValue: String {
        let maxLength = 80
        if displayValue.count > maxLength {
            return String(displayValue.prefix(maxLength)) + "..."
        }
        return displayValue
    }

    var body: some View {
        Text(truncatedValue)
            .font(.system(.body, design: .monospaced))
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(width: width, alignment: .topLeading)
            .textSelection(.enabled)
            .padding(8)
            .help(displayValue)  // Show full value on hover
    }
}

struct ResizableTableHeaderCell: View {
    let title: String
    let width: CGFloat
    let onWidthChange: (CGFloat) -> Void

    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Header cell content
            Text(title)
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.bold)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: width + dragOffset, alignment: .topLeading)
                .padding(8)
                .background(Color.primary.opacity(0.1))
                .help(title)

            // Resize handle
            VStack(spacing: 2) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle()
                        .fill(isDragging ? Color.accentColor : Color.secondary.opacity(0.5))
                        .frame(width: 3, height: 3)
                }
            }
            .frame(width: 8)
            .padding(.vertical, 8)
            .contentShape(Rectangle().inset(by: -4))
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        isDragging = true
                        dragOffset = value.translation.width
                    }
                    .onEnded { value in
                        isDragging = false
                        let newWidth = width + value.translation.width
                        onWidthChange(newWidth)
                        dragOffset = 0
                    }
            )
        }
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
