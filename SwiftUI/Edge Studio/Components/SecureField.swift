//
//  SecureFieldView.swift
//  Ditto Edge Studio
//
//  Created by Aaron LaBeau on 5/18/25.
//

import SwiftUI

struct SecureField: View {
    let label: String
    let value: String
    @Binding var isRevealed: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Button(action: { isRevealed.toggle() }) {
                Text(isRevealed ? value : String(repeating: "•", count: max(value.count, 6)))
                    .font(.body.monospaced())
                    .foregroundColor(.primary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                // Remove extra background, match card
#if os(iOS)
                    .background(Color(.secondarySystemBackground))
#else
                    .background(Color(NSColor.windowBackgroundColor))
#endif
                    .cornerRadius(8)
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
}
