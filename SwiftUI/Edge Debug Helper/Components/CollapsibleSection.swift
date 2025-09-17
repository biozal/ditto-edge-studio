//
//  CollapsibleSection.swift
//  Edge Studio
//

import SwiftUI

struct CollapsibleSection<Content: View>: View {
    let title: String
    let count: Int?
    @Binding var isExpanded: Bool
    @ViewBuilder let content: () -> Content

    init(
        title: String,
        count: Int? = nil,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.count = count
        self._isExpanded = isExpanded
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Button(action: {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isExpanded.toggle()
                }
            }) {
                HStack {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .medium))
                        .frame(width: 16)
                        .foregroundColor(.secondary)

                    Text(title)
                        .font(.system(.headline, weight: .semibold))
                        .foregroundColor(.primary)

                    if let count = count {
                        Text("(\(count))")
                            .font(.system(.caption))
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Content
            if isExpanded {
                content()
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity.combined(with: .move(edge: .top))
                    ))
            }
        }
    }
}