# Plan: Ditto Brand Colors for Window Backgrounds

## Brand Palette (Canonical RAL Values)

All six RAL brand colors and their sRGB approximations (RAL is a physical standard; these
are the standard digital reference conversions):

| RAL   | Name              | Hex       | RGB (normalized)              | Role in app                    |
|-------|-------------------|-----------|-------------------------------|-------------------------------|
| 9005  | Jet Black         | `#0A0A0A` | (0.039, 0.039, 0.039)        | Dark-mode app background       |
| 9017  | Traffic Black     | `#2A292A` | (0.165, 0.161, 0.165)        | Dark-mode card surface         |
| 9022  | Pearl Light Grey  | `#9D9D9F` | (0.616, 0.616, 0.624)        | Secondary surface, dividers    |
| 9018  | Papyrus White     | `#D0CFC8` | (0.816, 0.812, 0.784)        | Light-mode app background      |
| 9016  | Traffic White     | `#F1F0EA` | (0.945, 0.941, 0.918)        | Light-mode card surface        |
| 1016  | Sulfur Yellow     | `#F0D830` | (0.941, 0.847, 0.188)        | Accent / brand highlight       |

---

## Semantic Color Architecture

The brand colors map to semantic roles that adapt automatically between light and dark mode:

```
Token                  Light Mode           Dark Mode
─────────────────────────────────────────────────────────
dittoAppBackground     RAL 9018 Papyrus     RAL 9005 Jet Black
dittoCardSurface       RAL 9016 Traffic Wh  RAL 9017 Traffic Black
dittoSecondary         RAL 9022 Lt Grey     RAL 9022 Pearl Lt Grey (darker)
dittoAccent            RAL 1016 Sulfur Yel  RAL 1016 Sulfur Yellow
```

**Key insight — materials + brand background = free theming:**
The existing `.ultraThinMaterial` and `.regularMaterial` modifiers on toolbars, sidebars,
and cards are *translucent*. They tint based on whatever color is behind them. By setting
`Color.dittoAppBackground` on the root `ContentView` body:

- **Dark mode:** RAL 9005 (near-black) shines through all materials → toolbar, sidebar, and
  overlays automatically pick up the brand dark treatment.
- **Light mode:** RAL 9018 (warm off-white) shines through → everything gets a subtle warm
  papyrus tone instead of plain Apple grey.

This means one root-level background color change propagates the brand palette through the
entire window with minimal code changes.

---

## Visual Hierarchy (Before → After)

**Dark Mode**
```
Before: Apple system black (NSColor.windowBackgroundColor ≈ #1E1E1E)
After:  RAL 9005 Jet Black (#0A0A0A) — deeper, truer brand black

Cards:
Before: .regularMaterial → system tinted
After:  RAL 9017 Traffic Black (#2A292A) card surface — explicit brand color
```

**Light Mode**
```
Before: Apple system white (NSColor.windowBackgroundColor ≈ #ECECEC)
After:  RAL 9018 Papyrus White (#D0CFC8) — warm off-white brand background

Cards:
Before: .regularMaterial → system tinted
After:  RAL 9016 Traffic White (#F1F0EA) card surface — lighter warm surface
```

---

## Files to Create

### 1. `SwiftUI/Edge Debug Helper/Utilities/BrandColors.swift` *(new — via Xcode MCP)*

Defines the complete brand palette and semantic adaptive colors using macOS's
`NSColor(name:dynamicProvider:)` API for proper light/dark appearance switching.

```swift
import AppKit
import SwiftUI

// MARK: - RAL Brand Color Constants (physical paint → sRGB approximations)

extension Color {
    enum Ditto {
        // RAL 9005 Jet Black
        static let jetBlack       = Color(red: 0.039, green: 0.039, blue: 0.039)
        // RAL 9017 Traffic Black
        static let trafficBlack   = Color(red: 0.165, green: 0.161, blue: 0.165)
        // RAL 9022 Pearl Light Grey
        static let pearlGrey      = Color(red: 0.616, green: 0.616, blue: 0.624)
        // RAL 9018 Papyrus White
        static let papyrusWhite   = Color(red: 0.816, green: 0.812, blue: 0.784)
        // RAL 9016 Traffic White
        static let trafficWhite   = Color(red: 0.945, green: 0.941, blue: 0.918)
        // RAL 1016 Sulfur Yellow
        static let sulfurYellow   = Color(red: 0.941, green: 0.847, blue: 0.188)
    }

    // MARK: - Semantic Adaptive Colors (automatically switch light ↔ dark)

    /// Primary window background — RAL 9018 in light, RAL 9005 in dark
    static let dittoAppBackground = Color(adaptiveLight: Ditto.papyrusWhite,
                                          dark: Ditto.jetBlack)

    /// Elevated card / surface — RAL 9016 in light, RAL 9017 in dark
    static let dittoCardSurface   = Color(adaptiveLight: Ditto.trafficWhite,
                                          dark: Ditto.trafficBlack)

    /// Secondary surface — RAL 9022 in both modes
    static let dittoSecondary     = Color(Ditto.pearlGrey)

    /// Brand accent — RAL 1016 Sulfur Yellow in both modes
    static let dittoAccent        = Color(Ditto.sulfurYellow)

    // MARK: - NSColor appearance-based initializer

    init(adaptiveLight light: Color, dark: Color) {
        self = Color(NSColor(name: nil) { appearance in
            switch appearance.bestMatch(from: [.darkAqua, .aqua]) {
            case .darkAqua: return NSColor(dark)
            default:        return NSColor(light)
            }
        })
    }
}
```

---

## Files to Modify

### 2. `SwiftUI/Edge Debug Helper/Views/ContentView.swift`

Add `.background(Color.dittoAppBackground)` to the root `Group`. This single modifier
sets the base window color that all materials in the hierarchy tint from.

**Change — add to the root `Group`:**
```swift
var body: some View {
    Group {
        // ... existing if/else for MainStudioView vs database list
    }
    .background(Color.dittoAppBackground)   // ← ADD THIS
    .onAppear { ... }
}
```

Because `ContentView` fills the entire window, this ensures the brand background is the
"ground" color that all translucent materials (sidebar, toolbars, cards) blend with.

---

### 3. `SwiftUI/Edge Debug Helper/Components/LiquidGlassModifiers.swift`

Update `LiquidGlassCard` to use `Color.dittoCardSurface` as the fill instead of
`.regularMaterial`. The card surface uses an explicit brand color rather than relying on
the system material, giving more precise control over the card appearance in both modes.

Keep `.liquidGlassToolbar()` and `.liquidGlassSubtle()` using their current system
materials — they will automatically pick up the brand background color through translucency.

**`LiquidGlassCard` before:**
```swift
content
    .background(RoundedRectangle(cornerRadius: 20)
        .fill(.regularMaterial)
        .overlay(RoundedRectangle(cornerRadius: 20)
            .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)))
    .cornerRadius(20)
    .modifier(ElevatedShadow())
```

**`LiquidGlassCard` after:**
```swift
content
    .background(RoundedRectangle(cornerRadius: 20)
        .fill(Color.dittoCardSurface)
        .overlay(RoundedRectangle(cornerRadius: 20)
            .stroke(Color.dittoSecondary.opacity(0.25), lineWidth: 0.5)))
    .cornerRadius(20)
    .modifier(ElevatedShadow())
```

This replaces the semi-opaque system material with the explicit brand surface color, which
adapts cleanly between light and dark mode via the adaptive `NSColor` initializer.

---

### 4. `SwiftUI/Edge Debug Helper/Assets.xcassets/AccentColor.colorset/Contents.json`

Update the accent color to use **RAL 1016 Sulfur Yellow** in both light and dark modes.
This is Ditto's most distinctive brand color and works well as an accent in both modes:
- Light: yellow against RAL 9018 warm white background → vibrant brand accent
- Dark: yellow against RAL 9005 jet black → high contrast, premium brand feel

```json
{
  "colors": [
    {
      "color": {
        "color-space": "srgb",
        "components": { "alpha": "1.000", "red": "0.941", "green": "0.847", "blue": "0.188" }
      },
      "idiom": "universal"
    },
    {
      "appearances": [{ "appearance": "luminosity", "value": "dark" }],
      "color": {
        "color-space": "srgb",
        "components": { "alpha": "1.000", "red": "0.941", "green": "0.847", "blue": "0.188" }
      },
      "idiom": "universal"
    }
  ],
  "info": { "author": "xcode", "version": 1 }
}
```

**Note on AccentColor impact:** The accent color affects SwiftUI tint on Buttons, Toggles,
Links, and focused states. Using yellow will make these elements visually branded.
If yellow feels too bold for interactive controls, we can revert this single file — the
rest of the plan is unaffected by AccentColor.

---

## Files NOT Modified

| File | Reason |
|------|--------|
| `ConnectedPeersView.swift` | Transport-colored peer cards are intentional (Bluetooth=blue, WebSocket=orange, etc.) |
| `LocalPeerInfoCard.swift` | Already using RAL 9017 brand color — perfectly on-brand |
| `ConnectionLine.swift` | Presence viewer connection lines are semantic (transport type) |
| `PresenceViewerSK.swift` | SpriteKit scene has its own background |
| `MainStudioView.swift` | No explicit backgrounds — inherits from ContentView root |
| `ConnectionStatusBar.swift` | `.ultraThinMaterial` will tint from the new brand background automatically |

---

## Build & Verification

```bash
xcodebuild -project "SwiftUI/Edge Debug Helper.xcodeproj" \
           -scheme "Edge Studio" \
           -destination "platform=macOS,arch=arm64" build
```

**Visual checks:**
- [ ] Light mode: window background has warm papyrus white tone (not pure white/grey)
- [ ] Light mode: database list cards appear slightly whiter than the background (RAL 9016)
- [ ] Dark mode: window background is very deep black (RAL 9005, deeper than default macOS)
- [ ] Dark mode: cards appear slightly lighter dark grey (RAL 9017)
- [ ] All materials (sidebar, toolbar, status bar) tint from the new background color
- [ ] Yellow accent on toggle / button / link states (if AccentColor change is kept)
- [ ] Peer transport cards (blue/orange/red/green/purple/grey) still render correctly
- [ ] LocalPeerInfoCard RAL 9017 gradient still renders correctly
