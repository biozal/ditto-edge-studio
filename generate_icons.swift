#!/usr/bin/env swift

import CoreText
import Foundation

// Font paths
let solidFont = "/Users/labeaaa/Developer/ditto-edge-studio/SwiftUI/Edge Debug Helper/Resources/Fonts/Font Awesome 7 Pro-Solid-900.otf"
let brandsFont = "/Users/labeaaa/Developer/ditto-edge-studio/SwiftUI/Edge Debug Helper/Resources/Fonts/Font Awesome 7 Brands-Regular-400.otf"

struct IconInfo {
    let unicode: String
    let glyphName: String
    let style: String
}

func extractIcons(from fontPath: String, style: String) -> [IconInfo] {
    let fontURL = URL(fileURLWithPath: fontPath)
    guard let fontDataProvider = CGDataProvider(url: fontURL as CFURL),
          let cgFont = CGFont(fontDataProvider),
          let ctFont = CTFontCreateWithGraphicsFont(cgFont, 12.0, nil, nil) as CTFont? else
    {
        print("Failed to load font: \(fontPath)")
        return []
    }

    var icons: [IconInfo] = []

    // Get character set
    guard let charset = CTFontCopyCharacterSet(ctFont) as? CharacterSet else {
        return []
    }

    // Iterate through common unicode ranges for Font Awesome
    let ranges: [ClosedRange<UInt32>] = [
        0xE000 ... 0xF8FF, // Private Use Area
        0xF0000 ... 0xFFFFF // Supplementary Private Use Area
    ]

    for range in ranges {
        for unicodeValue in range {
            guard let scalar = Unicode.Scalar(unicodeValue),
                  charset.contains(scalar) else
            {
                continue
            }

            let unicodeHex = String(format: "%04x", unicodeValue)

            // Get glyph name
            var characters: [UniChar] = [UniChar(unicodeValue)]
            var glyphs: [CGGlyph] = [0]

            if CTFontGetGlyphsForCharacters(ctFont, &characters, &glyphs, 1), glyphs[0] != 0 {
                let glyphName = "icon_\(unicodeHex)"
                icons.append(IconInfo(unicode: unicodeHex, glyphName: glyphName, style: style))
            }
        }
    }

    return icons
}

func generateSwiftCode(solidIcons: [IconInfo], brandsIcons: [IconInfo]) -> String {
    var code = """
    //
    //  FontAwesomeIcons.swift
    //  Auto-generated from Font Awesome 7 Pro font files
    //
    //  DO NOT EDIT MANUALLY - regenerate with generate_icons.swift
    //

    import SwiftUI

    // MARK: - Font Awesome Icon Enum

    enum FAIcon: String, CaseIterable {

    """

    // Combine all icons
    var allIcons: [String: IconInfo] = [:]

    for icon in solidIcons {
        allIcons[icon.unicode] = icon
    }

    for icon in brandsIcons {
        if allIcons[icon.unicode] == nil {
            allIcons[icon.unicode] = icon
        } else {
            // Prefer brands if exists in both
            allIcons[icon.unicode] = IconInfo(unicode: icon.unicode, glyphName: icon.glyphName, style: "brands")
        }
    }

    // Sort and generate cases
    for (unicode, icon) in allIcons.sorted(by: { $0.key < $1.key }) {
        let caseName = icon.glyphName
        code += "    case \(caseName) = \"\\u{\(unicode)}\"  // \(icon.style)\n"
    }

    code += """

        var unicode: String { rawValue }

        var style: FontAwesomeStyle {
            switch self {

    """

    // Generate solid cases
    let solidCases = allIcons.values.filter { $0.style == "solid" }.sorted { $0.unicode < $1.unicode }
    if !solidCases.isEmpty {
        code += "        // Solid font icons\n        case "
        for (index, icon) in solidCases.enumerated() {
            code += ".\(icon.glyphName)"
            if index < solidCases.count - 1 {
                code += ",\n             "
            } else {
                code += ":\n            return .solid\n\n"
            }
        }
    }

    code += """
            // All other icons are in Brands font
            default:
                return .brands
            }
        }
    }

    // MARK: - FontAwesomeIcon Protocol Conformance

    extension FAIcon: FontAwesomeIcon {}

    """

    return code
}

print("🔍 Extracting icons from Solid font...")
let solidIcons = extractIcons(from: solidFont, style: "solid")
print("   Found \(solidIcons.count) icons")

print("🔍 Extracting icons from Brands font...")
let brandsIcons = extractIcons(from: brandsFont, style: "brands")
print("   Found \(brandsIcons.count) icons")

print("\n📝 Generating Swift code...")
let swiftCode = generateSwiftCode(solidIcons: solidIcons, brandsIcons: brandsIcons)

let outputPath = "/Users/labeaaa/Developer/ditto-edge-studio/SwiftUI/Edge Debug Helper/Utilities/FontAwesomeIcons.swift"
try swiftCode.write(toFile: outputPath, atomically: true, encoding: .utf8)

print("✅ Generated \(outputPath)")
print("   Total unique icons: \(Set(solidIcons.map(\.unicode) + brandsIcons.map(\.unicode)).count)")
