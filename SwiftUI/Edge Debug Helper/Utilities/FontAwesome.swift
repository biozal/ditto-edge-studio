import SwiftUI
import CoreText

// MARK: - Font Awesome Style

/// Defines the available Font Awesome font styles with their font names
enum FontAwesomeStyle {
    case solid
    case brands

    /// Font name for SwiftUI .custom() - using PostScript for Solid, Full name for Brands
    var fontName: String {
        switch self {
        case .solid:
            return "FontAwesome7Pro-Solid"  // PostScript name works
        case .brands:
            return "Font Awesome 7 Brands Regular"   // Full name with style
        }
    }

    /// PostScript name for font verification
    var postScriptName: String {
        switch self {
        case .solid:
            return "FontAwesome7Pro-Solid"
        case .brands:
            return "FontAwesome7Brands-Regular"
        }
    }

    /// Font file name in bundle
    var fileName: String {
        switch self {
        case .solid:
            return "Font Awesome 7 Pro-Solid-900.otf"
        case .brands:
            return "Font Awesome 7 Brands-Regular-400.otf"
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

// MARK: - Platform Icons (Brands Font)

/// Platform icon aliases for convenience
enum PlatformIcon {
    static let linux: FAIcon = .icon_f17c      // fa-linux (brands)
    static let apple: FAIcon = .icon_f179      // fa-apple (brands)
    static let android: FAIcon = .icon_f17b    // fa-android (brands)
    static let iOS: FAIcon = .icon_e1ee        // fa-app-store-ios (solid)
    static let windows: FAIcon = .icon_f17a    // fa-windows (brands)
}

// MARK: - Connectivity Icons (Solid Font)

/// Connectivity icon aliases for convenience
enum ConnectivityIcon {
    static let bluetooth: FAIcon = .icon_f293       // fa-bluetooth
    static let wifi: FAIcon = .icon_f1eb           // fa-wifi
    static let network: FAIcon = .icon_f6a9        // fa-plug (internet/websocket)
    static let ethernet: FAIcon = .icon_f796       // fa-ethernet
    static let broadcastTower: FAIcon = .icon_f519 // fa-broadcast-tower
    static let cloud: FAIcon = .icon_f0c2          // fa-cloud
}

// MARK: - System Icons (Solid Font)

/// System icon aliases for convenience
enum SystemIcon {
    static let sdk: FAIcon = .icon_e2d1            // custom SDK icon
    static let link: FAIcon = .icon_f0c1           // fa-link
    static let circleInfo: FAIcon = .icon_f05a     // fa-circle-info
    static let circleCheck: FAIcon = .icon_f058    // fa-circle-check
    static let clock: FAIcon = .icon_f017          // fa-clock
    static let question: FAIcon = .icon_f059       // fa-question
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

