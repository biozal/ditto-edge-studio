//
//  LiquidGlassModifiers.swift
//  Edge Debug Helper
//
//  Liquid Glass design system matching Xcode's modern aesthetic
//

import SwiftUI

// MARK: - Spacing System

/// Consistent spacing tokens for Liquid Glass design
enum LiquidSpacing {
    static let tight: CGFloat = 8
    static let comfortable: CGFloat = 16
    static let spacious: CGFloat = 24
    static let generous: CGFloat = 32
}

// MARK: - Glass Effect Modifiers

/// Liquid Glass card effect with frosted background and elevated shadows
struct LiquidGlassCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(.regularMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)
                    )
            )
            .cornerRadius(20)
            .modifier(ElevatedShadow())
    }
}

/// Liquid Glass toolbar effect with ultra-thin material
struct LiquidGlassToolbar: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.secondary.opacity(0.15), lineWidth: 0.5)
                    )
            )
            .cornerRadius(12)
            .modifier(SubtleShadow())
    }
}

/// Subtle glass effect for backgrounds and overlays
struct LiquidGlassSubtle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.thinMaterial)
            )
            .cornerRadius(16)
            .modifier(SubtleShadow())
    }
}

/// Glass effect for pill badges
struct LiquidGlassPill: ViewModifier {
    var color: Color

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial)
            .background(color.opacity(0.15))
            .overlay(
                Capsule()
                    .stroke(color.opacity(0.3), lineWidth: 0.5)
            )
            .modifier(SubtleShadow())
    }
}

// MARK: - Shadow System

/// Three-layer shadow system for elevated elements (cards, prominent UI)
struct ElevatedShadow: ViewModifier {
    func body(content: Content) -> some View {
        content
            .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
            .shadow(color: Color.black.opacity(0.05), radius: 16, x: 0, y: 8)
            .shadow(color: Color.black.opacity(0.03), radius: 24, x: 0, y: 12)
    }
}

/// Two-layer shadow system for subtle depth (pills, small elements)
struct SubtleShadow: ViewModifier {
    func body(content: Content) -> some View {
        content
            .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
            .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 4)
    }
}

// MARK: - View Extensions

extension View {
    /// Apply Liquid Glass card effect with frosted background and elevated shadows
    func liquidGlassCard() -> some View {
        modifier(LiquidGlassCard())
    }

    /// Apply Liquid Glass toolbar effect with ultra-thin material
    func liquidGlassToolbar() -> some View {
        modifier(LiquidGlassToolbar())
    }

    /// Apply subtle glass effect for backgrounds
    func liquidGlassSubtle() -> some View {
        modifier(LiquidGlassSubtle())
    }

    /// Apply glass effect for pill badges
    func liquidGlassPill(color: Color = .gray) -> some View {
        modifier(LiquidGlassPill(color: color))
    }

    /// Apply three-layer elevated shadow for prominent elements
    func elevatedShadow() -> some View {
        modifier(ElevatedShadow())
    }

    /// Apply two-layer subtle shadow for secondary elements
    func subtleShadow() -> some View {
        modifier(SubtleShadow())
    }
}
