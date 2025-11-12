//
//  CollapsibleSection.swift
//  Edge Studio
//

import SwiftUI

struct CollapsibleSection<Content: View, ContextMenu: View>: View {
    let title: String
    let count: Int?
    @Binding var isExpanded: Bool
    @ViewBuilder let content: () -> Content
    @ViewBuilder let contextMenu: (() -> ContextMenu)?

    init(
        title: String,
        count: Int? = nil,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder contextMenu: @escaping () -> ContextMenu
    ) {
        self.title = title
        self.count = count
        self._isExpanded = isExpanded
        self.content = content
        self.contextMenu = contextMenu
    }

    init(
        title: String,
        count: Int? = nil,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) where ContextMenu == EmptyView {
        self.title = title
        self.count = count
        self._isExpanded = isExpanded
        self.content = content
        self.contextMenu = nil
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

                    Spacer()

                    if let count = count {
                        Text("\(count)")
                            .font(.system(.caption))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            #if os(macOS)
            .if(contextMenu != nil) { view in
                view.contextMenu {
                    contextMenu?()
                }
            }
            #endif

            // Content
            if isExpanded {
                content()
                    .padding(.bottom, 8)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity.combined(with: .move(edge: .top))
                    ))
            }
        }
    }
}

// Helper extension for conditional modifiers
extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}