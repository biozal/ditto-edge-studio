import SwiftUI

// MARK: - Ditto RAL Palette

extension Color {
    /// Direct access to the Ditto RAL palette raw values.
    enum Ditto {
        /// RAL 9005 — Jet Black `#0A0A0A`. Dark-mode window background.
        static let jetBlack = Color(red: 0.039, green: 0.039, blue: 0.039)
        /// RAL 9017 — Traffic Black `#2A292A`. Dark-mode card gradient start.
        static let trafficBlack = Color(red: 0.165, green: 0.161, blue: 0.165)
        /// RAL 9022 — Pearl Light Grey `#9D9D9F`. Dividers, secondary surfaces.
        static let pearlGrey = Color(red: 0.616, green: 0.616, blue: 0.624)
        /// RAL 9018 — Papyrus White `#D0CFC8`. Light-mode window background.
        static let papyrusWhite = Color(red: 0.816, green: 0.812, blue: 0.784)
        /// RAL 9016 — Traffic White `#F1F0EA`. Light-mode card gradient start.
        static let trafficWhite = Color(red: 0.945, green: 0.941, blue: 0.918)
        /// RAL 1016 — Sulfur Yellow `#F0D830`. Accent / brand highlight.
        static let sulfurYellow = Color(red: 0.941, green: 0.847, blue: 0.188)
    }
}

// MARK: - Ditto Semantic Tokens

extension Color {
    /// Root window / NavigationStack background.
    /// Light: RAL 9018 Papyrus White — Dark: RAL 9005 Jet Black.
    static let dittoAppBackground: Color = adaptive(
        light: .Ditto.papyrusWhite,
        dark: .Ditto.jetBlack
    )

    /// Flat card surfaces.
    /// Light: RAL 9016 Traffic White — Dark: RAL 9017 Traffic Black.
    static let dittoCardSurface: Color = adaptive(
        light: .Ditto.trafficWhite,
        dark: .Ditto.trafficBlack
    )

    /// Secondary text and dividers. RAL 9022 Pearl Light Grey in both modes.
    static let dittoSecondary = Color.Ditto.pearlGrey

    /// Primary accent — toggles, focused buttons, links.
    /// RAL 1016 Sulfur Yellow in both modes.
    static let dittoAccent = Color.Ditto.sulfurYellow

    /// Convenience alias for `dittoAccent`.
    static let dittoYellow = Color.Ditto.sulfurYellow
}

// MARK: - Adaptive Color Helper

private func adaptive(light: Color, dark: Color) -> Color {
    #if os(macOS)
    Color(NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return NSColor(isDark ? dark : light)
    })
    #else
    Color(UIColor { traits in
        UIColor(traits.userInterfaceStyle == .dark ? dark : light)
    })
    #endif
}
