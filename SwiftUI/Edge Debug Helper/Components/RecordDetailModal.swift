//
//  RecordDetailModal.swift
//  Edge Studio
//
//  Created by Claude Code on 10/2/25.
//

import CodeEditor
import SwiftUI

struct RecordDetailModal: View {
  let jsonString: String
  let index: Int?
  let attachmentFields: [String]
  let autoFetchAttachments: Bool
  @Binding var isPresented: Bool

  @State private var isCopied = false

  init(
    jsonString: String, index: Int?, attachmentFields: [String] = [],
    autoFetchAttachments: Bool = false, isPresented: Binding<Bool>
  ) {
    self.jsonString = jsonString
    self.index = index
    self.attachmentFields = attachmentFields
    self.autoFetchAttachments = autoFetchAttachments
    self._isPresented = isPresented
  }

  private var formattedJSON: String {
    guard !jsonString.isEmpty else {
      return "No data"
    }

    guard let data = jsonString.data(using: .utf8) else {
      return jsonString
    }
    guard let json = try? JSONSerialization.jsonObject(with: data) else {
      return jsonString
    }
    guard
      let prettyData = try? JSONSerialization.data(
        withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
    else {
      return jsonString
    }
    guard let prettyString = String(data: prettyData, encoding: .utf8) else {
      return jsonString
    }
    return prettyString
  }

  private var parsedFields: [(key: String, value: Any)] {
    guard !jsonString.isEmpty else {
      return []
    }

    guard let data = jsonString.data(using: .utf8) else {
      return []
    }

    do {
      guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return []
      }
      return json.sorted { $0.key < $1.key }
    } catch {
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
    VStack(spacing: 0) {
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
        ScrollView {
          VStack(alignment: .leading, spacing: 12) {
            if parsedFields.isEmpty {
              Text("Invalid JSON")
                .foregroundColor(.secondary)
                .padding()
            } else {
              ForEach(parsedFields.indices, id: \.self) { fieldIndex in
                let field = parsedFields[fieldIndex]
                if isAttachmentField(field.key) {
                  let attachmentInfo = getAttachmentInfo(for: field.key, value: field.value)
                  let token = field.value as? [String: Any]
                  AttachmentFieldView(
                    fieldName: field.key,
                    token: token,
                    metadata: attachmentInfo.metadata,
                    autoFetch: autoFetchAttachments
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
        GeometryReader { geometry in
          ScrollView([.horizontal, .vertical]) {
            Text(formattedJSON)
              .font(.system(.body, design: .monospaced))
              .textSelection(.enabled)
              .padding()
              .frame(
                minWidth: geometry.size.width, minHeight: geometry.size.height,
                alignment: .topLeading
              )
              .background(Color.primary.opacity(0.08))
          }
        }
      }
    }
    .frame(
      minWidth: 600, idealWidth: 900, maxWidth: .infinity, minHeight: 400, idealHeight: 700,
      maxHeight: .infinity
    )
    .background(Color(NSColor.windowBackgroundColor))
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
      let jsonString = String(data: jsonData, encoding: .utf8)
    {
      return jsonString
    } else if let dict = value as? [String: Any],
      let jsonData = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted]),
      let jsonString = String(data: jsonData, encoding: .utf8)
    {
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
