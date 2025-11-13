//
//  HoverableCardModifier.swift
//  Edge Studio
//
//  Reusable modifier for adding hover effects to card components
//

import SwiftUI

struct HoverableCardModifier: ViewModifier {
    let isSelected: Bool
    let spacing: CGFloat
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .background(
                isSelected ? Color.accentColor.opacity(0.15) :
                isHovered ? Color.primary.opacity(0.08) : Color.clear
            )
            .cornerRadius(4)
            .contentShape(Rectangle())
            .onHover { hovering in
                withAnimation(.linear(duration: 0)) {
                    isHovered = hovering
                }
            }
            .padding(.bottom, spacing)
    }
}

extension View {
    func hoverableCard(isSelected: Bool, spacing: CGFloat = 2) -> some View {
        self.modifier(HoverableCardModifier(isSelected: isSelected, spacing: spacing))
    }
}
