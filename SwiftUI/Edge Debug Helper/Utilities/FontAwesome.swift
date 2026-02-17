import CoreText
import SwiftUI

// MARK: - Font Awesome Style

/// Defines the available Font Awesome font styles with their font names
enum FontAwesomeStyle {
    case solid // 900 weight
    case regular // 400 weight
    case light // 300 weight
    case thin // 100 weight
    case brands // Brand icons

    /// Font name for SwiftUI .custom() - using PostScript names
    var fontName: String {
        switch self {
        case .solid:
            return "FontAwesome7Pro-Solid"
        case .regular:
            return "FontAwesome7Pro-Regular"
        case .light:
            return "FontAwesome7Pro-Light"
        case .thin:
            return "FontAwesome7Pro-Thin"
        case .brands:
            return "Font Awesome 7 Brands Regular"
        }
    }

    /// PostScript name for font verification
    var postScriptName: String {
        switch self {
        case .solid:
            return "FontAwesome7Pro-Solid"
        case .regular:
            return "FontAwesome7Pro-Regular"
        case .light:
            return "FontAwesome7Pro-Light"
        case .thin:
            return "FontAwesome7Pro-Thin"
        case .brands:
            return "FontAwesome7Brands-Regular"
        }
    }

    /// Font file name in bundle
    var fileName: String {
        switch self {
        case .solid:
            return "Font Awesome 7 Pro-Solid-900.otf"
        case .regular:
            return "Font Awesome 7 Pro-Regular-400.otf"
        case .light:
            return "Font Awesome 7 Pro-Light-300.otf"
        case .thin:
            return "Font Awesome 7 Pro-Thin-100.otf"
        case .brands:
            return "Font Awesome 7 Brands-Regular-400.otf"
        }
    }

    /// Display name with weight
    var displayName: String {
        switch self {
        case .solid:
            return "Solid (900)"
        case .regular:
            return "Regular (400)"
        case .light:
            return "Light (300)"
        case .thin:
            return "Thin (100)"
        case .brands:
            return "Brands"
        }
    }
}

// MARK: - Font Awesome Registration

/// Registers Font Awesome fonts programmatically (more reliable than Info.plist on macOS)
enum FontAwesomeRegistration {
    /// Register all Font Awesome fonts with the system
    /// Call this early in app initialization before any views are rendered
    static func registerFonts() {
        let fontFiles = [
            "Font Awesome 7 Pro-Solid-900.otf",
            "Font Awesome 7 Pro-Regular-400.otf",
            "Font Awesome 7 Pro-Light-300.otf",
            "Font Awesome 7 Pro-Thin-100.otf",
            "Font Awesome 7 Brands-Regular-400.otf"
        ]

        for fileName in fontFiles {
            registerFontFile(fileName)
        }
    }

    private static func registerFontFile(_ fileName: String) {
        let nameWithoutExt = fileName.replacingOccurrences(of: ".otf", with: "")

        if let url = Bundle.main.url(forResource: nameWithoutExt, withExtension: "otf") {
            registerFontURL(url)
        } else if let url = Bundle.main.url(forResource: fileName, withExtension: nil) {
            registerFontURL(url)
        }
    }

    private static func registerFontURL(_ url: URL) {
        var error: Unmanaged<CFError>?
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
    }
}

// MARK: - Font Awesome Icon Protocol

/// Protocol that all Font Awesome icon enums must conform to
protocol FontAwesomeIcon {
    var unicode: String { get }
    var style: FontAwesomeStyle { get }
}

// MARK: - Weighted Font Awesome Icon

/// Struct for creating icons with explicit font weight/style
/// Use this when you need the same unicode value with a different font weight
/// Example: database icon (f1c0) in Regular weight instead of default Solid
struct WeightedFAIcon: FontAwesomeIcon {
    let unicode: String
    let style: FontAwesomeStyle

    /// Create a weighted icon from an existing FAIcon with a different style
    /// - Parameters:
    ///   - icon: The base FAIcon to use (provides unicode)
    ///   - weight: The desired font weight/style
    init(_ icon: FAIcon, weight: FontAwesomeStyle) {
        unicode = icon.unicode
        style = weight
    }

    /// Create a weighted icon directly from unicode and style
    /// - Parameters:
    ///   - unicode: The unicode value (e.g., "\u{f1c0}")
    ///   - weight: The desired font weight/style
    init(unicode: String, weight: FontAwesomeStyle) {
        self.unicode = unicode
        style = weight
    }
}

// MARK: - Platform Icons (Brands Font)

/// Platform icon aliases for convenience
enum PlatformIcon {
    static let linux: FAIcon = .icon_f17c // fa-linux (brands)
    static let apple: FAIcon = .icon_f179 // fa-apple (brands)
    static let android: FAIcon = .icon_f17b // fa-android (brands)
    static let iOS: FAIcon = .icon_e1ee // fa-app-store-ios (solid)
    static let windows: FAIcon = .icon_f17a // fa-windows (brands)
}

// MARK: - Connectivity Icons (Solid Font)

/// Connectivity icon aliases for convenience
enum ConnectivityIcon {
    static let bluetooth: FAIcon = .icon_f293 // fa-bluetooth
    static let wifi: FAIcon = .icon_f1eb // fa-wifi
    static let network: FAIcon = .icon_f6a9 // fa-plug (internet/websocket)
    static let ethernet: FAIcon = .icon_f796 // fa-ethernet
    static let broadcastTower: FAIcon = .icon_f519 // fa-broadcast-tower
    static let cloud: FAIcon = .icon_f0c2 // fa-cloud
}

// MARK: - System Icons (Solid Font)

/// System icon aliases for convenience
enum SystemIcon {
    static let sdk: FAIcon = .icon_e2d1 // custom SDK icon
    static let link: FAIcon = .icon_f0c1 // fa-link
    static let circleInfo: FAIcon = .icon_f05a // fa-circle-info
    static let circleCheck: FAIcon = .icon_f058 // fa-circle-check
    static let clock: FAIcon = .icon_f017 // fa-clock
    static let question: FAIcon = .icon_f059 // fa-question
    static let gear: FAIcon = .icon_f013 // fa-gear
}

// MARK: - Navigation Icons (Solid Font)

/// Navigation icon aliases for convenience
enum NavigationIcon {
    static let chevronLeft: FAIcon = .icon_f053 // fa-chevron-left
    static let chevronRight: FAIcon = .icon_f054 // fa-chevron-right
    static let play: FAIcon = .icon_f04b // fa-play
    static let refresh: FAIcon = .icon_f021 // fa-arrow-rotate-right
    static let sync: FAIcon = .icon_f2f1 // fa-rotate (circular arrows)

    /// Light weight variants
    static let syncLight = WeightedFAIcon(.icon_f2f1, weight: .light) // fa-rotate (Light 300)
}

// MARK: - Action Icons (Solid Font)

/// Action icon aliases for convenience
enum ActionIcon {
    static let plus: FAIcon = .icon_f067 // fa-plus
    static let minus: FAIcon = .icon_f068 // fa-minus
    static let circlePlus: FAIcon = .icon_f055 // fa-circle-plus
    static let circleXmark: FAIcon = .icon_f057 // fa-circle-xmark
    static let download: FAIcon = .icon_f019 // fa-download
    static let copy: FAIcon = .icon_f0c5 // fa-copy

    /// Light weight variants
    static let circleXmarkLight = WeightedFAIcon(.icon_f057, weight: .light) // fa-circle-xmark (Light 300)
}

// MARK: - Data Display Icons (Solid Font)

/// Data display icon aliases for convenience
enum DataIcon {
    static let code: FAIcon = .icon_f121 // fa-code
    static let table: FAIcon = .icon_f0ce // fa-table
    static let database: FAIcon = .icon_f1c0 // fa-database (Solid 900)
    static let layerGroup: FAIcon = .icon_f5fd // fa-layer-group

    // Weight variants
    static let databaseRegular = WeightedFAIcon(.icon_f1c0, weight: .regular) // fa-database (Regular 400)
    static let databaseThin = WeightedFAIcon(.icon_f1c0, weight: .thin) // fa-database (Thin 100)
}

// MARK: - Status Icons (Solid Font)

/// Status icon aliases for convenience
enum StatusIcon {
    static let circleCheck: FAIcon = .icon_f058 // fa-circle-check
    static let circleInfo: FAIcon = .icon_f05a // fa-circle-info
    static let triangleExclamation: FAIcon = .icon_f071 // fa-triangle-exclamation
    static let circleQuestion: FAIcon = .icon_f059 // fa-circle-question
}

// MARK: - UI Icons (Solid Font)

/// UI icon aliases for convenience
enum UIIcon {
    static let star: FAIcon = .icon_f005 // fa-star
    static let eye: FAIcon = .icon_f06e // fa-eye
    static let clock: FAIcon = .icon_f017 // fa-clock
    static let circleNodes: FAIcon = .icon_e4e2 // fa-circle-nodes
}

// MARK: - Font Awesome Text View

/// SwiftUI view that renders a Font Awesome icon
struct FontAwesomeText: View {
    let icon: FontAwesomeIcon
    let size: CGFloat
    let color: Color

    init(icon: FontAwesomeIcon, size: CGFloat, color: Color = .primary) {
        self.icon = icon
        self.size = size
        self.color = color
    }

    var body: some View {
        Text(icon.unicode)
            .font(.custom(icon.style.fontName, size: size))
            .foregroundColor(color)
    }
}
