//
//  RecordDetailModal.swift
//  Edge Studio
//
//  Created by Claude Code on 10/2/25.
//

import SwiftUI
import CodeEditor

struct RecordDetailModal: View {
    let jsonString: String
    let index: Int?
    let attachmentFields: [String]
    @Binding var isPresented: Bool

    @State private var isCopied = false

    init(jsonString: String, index: Int?, attachmentFields: [String] = [], isPresented: Binding<Bool>) {
        print("[RecordDetailModal] init called")
        print("[RecordDetailModal] jsonString length: \(jsonString.count)")
        print("[RecordDetailModal] jsonString first 200 chars: \(jsonString.prefix(200))")
        print("[RecordDetailModal] index: \(String(describing: index))")
        print("[RecordDetailModal] attachmentFields count: \(attachmentFields.count)")
        self.jsonString = jsonString
        self.index = index
        self.attachmentFields = attachmentFields
        self._isPresented = isPresented
    }

    private var formattedJSON: String {
        print("[RecordDetailModal] formattedJSON computed property called")
        print("[RecordDetailModal] jsonString length in formattedJSON: \(jsonString.count)")

        guard !jsonString.isEmpty else {
            print("[RecordDetailModal] ERROR formattedJSON: jsonString is EMPTY!")
            return "No data"
        }

        guard let data = jsonString.data(using: .utf8) else {
            print("[RecordDetailModal] ERROR formattedJSON: Failed to convert jsonString to data")
            return jsonString
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) else {
            print("[RecordDetailModal] ERROR formattedJSON: Failed to parse JSON from data")
            return jsonString
        }
        guard let prettyData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) else {
            print("[RecordDetailModal] ERROR formattedJSON: Failed to create pretty-printed data")
            return jsonString
        }
        guard let prettyString = String(data: prettyData, encoding: .utf8) else {
            print("[RecordDetailModal] ERROR formattedJSON: Failed to convert pretty data to string")
            return jsonString
        }
        print("[RecordDetailModal] formattedJSON: Successfully formatted JSON (\(prettyString.count) chars)")
        return prettyString
    }

    private var parsedFields: [(key: String, value: Any)] {
        print("[RecordDetailModal] parsedFields computed property called")
        print("[RecordDetailModal] jsonString length in parsedFields: \(jsonString.count)")
        print("[RecordDetailModal] jsonString content (first 500 chars): \(jsonString.prefix(500))")

        guard !jsonString.isEmpty else {
            print("[RecordDetailModal] ERROR parsedFields: jsonString is EMPTY!")
            return []
        }

        guard let data = jsonString.data(using: .utf8) else {
            print("[RecordDetailModal] ERROR parsedFields: Failed to convert jsonString to data")
            print("[RecordDetailModal] ERROR parsedFields: jsonString was: \(jsonString)")
            return []
        }

        print("[RecordDetailModal] parsedFields: Successfully converted to data, size: \(data.count) bytes")

        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                print("[RecordDetailModal] ERROR parsedFields: JSON is not a dictionary")
                if let jsonObj = try? JSONSerialization.jsonObject(with: data) {
                    print("[RecordDetailModal] ERROR parsedFields: JSON type is: \(type(of: jsonObj))")
                }
                return []
            }
            let sorted = json.sorted { $0.key < $1.key }
            print("[RecordDetailModal] parsedFields: Successfully parsed \(sorted.count) fields")
            print("[RecordDetailModal] parsedFields keys: \(sorted.map { $0.key })")
            return sorted
        } catch {
            print("[RecordDetailModal] ERROR parsedFields: JSON parsing threw error: \(error)")
            return []
        }
    }

    private func isAttachmentField(_ fieldName: String) -> Bool {
        attachmentFields.contains(fieldName)
    }

    private func getAttachmentInfo(for fieldName: String, value: Any) -> AttachmentFieldInfo {
        let metadata = AttachmentQueryParser.parseAttachmentMetadata(from: value)
        return AttachmentFieldInfo(fieldName: fieldName, metadata: metadata)
    }

    @State private var selectedTab = 0

    var body: some View {
        let _ = print("[RecordDetailModal] ===== BODY RENDERING =====")
        let _ = print("[RecordDetailModal] jsonString length: \(jsonString.count)")
        let _ = print("[RecordDetailModal] jsonString content: \(jsonString)")
        let _ = print("[RecordDetailModal] parsedFields.count: \(parsedFields.count)")
        let _ = print("[RecordDetailModal] parsedFields: \(parsedFields.map { $0.key })")
        let _ = print("[RecordDetailModal] index: \(String(describing: index))")
        let _ = print("[RecordDetailModal] selectedTab: \(selectedTab)")

        return VStack(spacing: 0) {
            // Header
            HStack {
                if let index = index {
                    Text("Document \(index + 1)")
                        .font(.headline)
                } else {
                    Text("Record Details")
                        .font(.headline)
                }

                Spacer()

                Button {
                    copyToClipboard()
                } label: {
                    HStack(spacing: 4) {
                        if isCopied {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Copied")
                                .foregroundColor(.green)
                        } else {
                            Image(systemName: "doc.on.doc")
                            Text("Copy")
                        }
                    }
                }
                .buttonStyle(.borderless)

                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
            }
            .padding()
            .background(Color.primary.opacity(0.05))

            Divider()

            // Tab picker
            Picker("View", selection: $selectedTab) {
                Text("Formatted").tag(0)
                Text("Raw JSON").tag(1)
            }
            .pickerStyle(.segmented)
            .padding()

            Divider()

            // Content based on selected tab
            if selectedTab == 0 {
                // Formatted view
                let _ = print("[RecordDetailModal] Rendering Formatted view, parsedFields count: \(parsedFields.count)")
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if parsedFields.isEmpty {
                            let _ = print("[RecordDetailModal] ERROR - Showing 'Invalid JSON' - parsedFields is empty")
                            let _ = print("[RecordDetailModal] ERROR - jsonString was: \(jsonString)")
                            Text("Invalid JSON")
                                .foregroundColor(.secondary)
                                .padding()
                        } else {
                            let _ = print("[RecordDetailModal] SUCCESS - Rendering \(parsedFields.count) fields")
                            ForEach(parsedFields.indices, id: \.self) { fieldIndex in
                                let field = parsedFields[fieldIndex]
                                let _ = print("[RecordDetailModal] Rendering field[\(fieldIndex)]: \(field.key) = \(field.value)")
                                if isAttachmentField(field.key) {
                                    let attachmentInfo = getAttachmentInfo(for: field.key, value: field.value)
                                    let token = field.value as? [String: Any]
                                    AttachmentFieldView(
                                        fieldName: field.key,
                                        token: token,
                                        metadata: attachmentInfo.metadata
                                    )
                                } else {
                                    FieldRow(
                                        key: field.key,
                                        value: field.value
                                    )
                                }
                            }
                        }
                    }
                    .padding()
                }
            } else {
                // Raw JSON view
                let _ = print("[RecordDetailModal] Rendering Raw JSON view")
                let _ = print("[RecordDetailModal] formattedJSON length: \(formattedJSON.count)")
                GeometryReader { geometry in
                    ScrollView([.horizontal, .vertical]) {
                        Text(formattedJSON)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .padding()
                            .frame(minWidth: geometry.size.width, minHeight: geometry.size.height, alignment: .topLeading)
                            .background(Color.primary.opacity(0.08))
                    }
                }
            }
        }
        .frame(minWidth: 600, idealWidth: 900, maxWidth: .infinity, minHeight: 400, idealHeight: 700, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            print("[RecordDetailModal] onAppear called")
            print("[RecordDetailModal] jsonString length: \(jsonString.count)")
            print("[RecordDetailModal] jsonString first 200 chars: \(jsonString.prefix(200))")
            print("[RecordDetailModal] Parsed fields count: \(parsedFields.count)")
            print("[RecordDetailModal] Selected tab: \(selectedTab)")
        }
    }

    private func copyToClipboard() {
        #if os(macOS)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(formattedJSON, forType: .string)
        #else
            UIPasteboard.general.string = formattedJSON
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

struct FieldRow: View {
    let key: String
    let value: Any

    @State private var isExpanded = false
    @State private var isCopied = false

    private var displayValue: String {
        if let string = value as? String {
            return string
        } else if let number = value as? NSNumber {
            return number.stringValue
        } else if let bool = value as? Bool {
            return bool ? "true" : "false"
        } else if value is NSNull {
            return "null"
        } else if let array = value as? [Any],
                  let jsonData = try? JSONSerialization.data(withJSONObject: array, options: [.prettyPrinted]),
                  let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        } else if let dict = value as? [String: Any],
                  let jsonData = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted]),
                  let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }
        return "\(value)"
    }

    private var valueType: String {
        if value is String {
            return "String"
        } else if value is NSNumber {
            return "Number"
        } else if value is Bool {
            return "Boolean"
        } else if value is NSNull {
            return "Null"
        } else if value is [Any] {
            return "Array"
        } else if value is [String: Any] {
            return "Object"
        }
        return "Unknown"
    }

    private var isComplexType: Bool {
        value is [Any] || value is [String: Any]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                // Key column
                Text(key)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .frame(width: 150, alignment: .leading)

                // Type column
                Text(valueType)
                    .font(.system(.caption2, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.2))
                    .cornerRadius(4)
                    .frame(width: 80, alignment: .leading)

                // Value column
                if isComplexType && !isExpanded {
                    Text(displayValue.components(separatedBy: "\n").first ?? displayValue)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(displayValue)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Action buttons column
                HStack(spacing: 8) {
                    if isComplexType {
                        Button {
                            withAnimation {
                                isExpanded.toggle()
                            }
                        } label: {
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.borderless)
                        .help(isExpanded ? "Collapse" : "Expand")
                    }

                    Button {
                        copyValueToClipboard()
                    } label: {
                        if isCopied {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.system(size: 12))
                        } else {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 12))
                        }
                    }
                    .buttonStyle(.borderless)
                    .help("Copy value")
                }
                .frame(width: 60, alignment: .trailing)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)

            Divider()
        }
        .contentShape(Rectangle())
    }

    private func copyValueToClipboard() {
        #if os(macOS)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(displayValue, forType: .string)
        #else
            UIPasteboard.general.string = displayValue
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
    RecordDetailModal(
        jsonString: """
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
        index: 0,
        isPresented: .constant(true)
    )
}
