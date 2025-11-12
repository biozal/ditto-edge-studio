//
//  CollapsibleSidebarHeader.swift
//  Edge Debug Helper
//
//  Unified collapsible header for sidebar sections
//

import SwiftUI

struct CollapsibleSidebarHeader: View {
    let title: String
    let count: Int
    @Binding var isExpanded: Bool

    var body: some View {
        Button(action: {
            withAnimation {
                isExpanded.toggle()
            }
        }) {
            HStack {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 12)

                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)

                Spacer()

                Text("\(count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

#Preview {
    VStack(spacing: 0) {
        CollapsibleSidebarHeader(title: "Favorites", count: 42, isExpanded: .constant(true))
        CollapsibleSidebarHeader(title: "History", count: 128, isExpanded: .constant(false))
        CollapsibleSidebarHeader(title: "Subscriptions", count: 5, isExpanded: .constant(true))
    }
}
