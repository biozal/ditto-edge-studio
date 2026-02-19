# Ditto Brand Colors

Reference guide for the Edge Debug Helper brand color system.

---

## RAL Palette

| RAL  | Name             | Hex       | RGB (normalized)            | Semantic Role                     |
|------|------------------|-----------|-----------------------------|-----------------------------------|
| 9005 | Jet Black        | `#0A0A0A` | (0.039, 0.039, 0.039)       | Dark-mode window background       |
| 9017 | Traffic Black    | `#2A292A` | (0.165, 0.161, 0.165)       | Dark-mode card gradient start     |
| 9022 | Pearl Light Grey | `#9D9D9F` | (0.616, 0.616, 0.624)       | Dividers, secondary surfaces      |
| 9018 | Papyrus White    | `#D0CFC8` | (0.816, 0.812, 0.784)       | Light-mode window background      |
| 9016 | Traffic White    | `#F1F0EA` | (0.945, 0.941, 0.918)       | Light-mode card gradient start    |
| 1016 | Sulfur Yellow    | `#F0D830` | (0.941, 0.847, 0.188)       | Accent / brand highlight          |

---

## Semantic Tokens

All tokens are defined in `SwiftUI/Edge Debug Helper/Utilities/BrandColors.swift`.

| Token                     | Light Mode          | Dark Mode           | Usage                                  |
|---------------------------|---------------------|---------------------|----------------------------------------|
| `Color.dittoAppBackground` | RAL 9018 Papyrus White | RAL 9005 Jet Black | Root window / NavigationStack background |
| `Color.dittoCardSurface`  | RAL 9016 Traffic White | RAL 9017 Traffic Black | Flat card surfaces (no gradient needed) |
| `Color.dittoSecondary`    | RAL 9022 Pearl Grey  | RAL 9022 Pearl Grey  | Secondary text, dividers               |
| `Color.dittoAccent`       | RAL 1016 Sulfur Yellow | RAL 1016 Sulfur Yellow | Toggles, focused buttons, links        |
| `Color.Ditto.jetBlack`    | —                   | #0A0A0A             | Direct access to raw RAL value         |
| `Color.Ditto.trafficBlack`| —                   | #2A292A             | Direct access to raw RAL value         |
| `Color.Ditto.papyrusWhite`| #D0CFC8             | —                   | Direct access to raw RAL value         |
| `Color.Ditto.trafficWhite`| #F1F0EA             | —                   | Direct access to raw RAL value         |
| `Color.Ditto.sulfurYellow`| #F0D830             | #F0D830             | Direct access to raw RAL value         |

---

## Gradient Patterns

### Card Gradient (`.dittoGradientCard()` modifier)

The `DittoGradientCard` view modifier applies the brand gradient to any card container. It reads `colorScheme` automatically.

```swift
// Usage
MyCardContent()
    .dittoGradientCard()
```

**Dark mode:** RAL 9017 Traffic Black → RAL 9005 Jet Black (top-leading → bottom-trailing)
**Light mode:** RAL 9016 Traffic White → RAL 9018 Papyrus White (top-leading → bottom-trailing)

**Shadow:** dark=0.40 opacity, light=0.15 opacity, radius 6, y+3

### Reference Implementation (LocalPeerInfoCard)

`LocalPeerInfoCard.swift` was the original reference for the brand gradient pattern and is already correct — do not modify it.

---

## Accent Color

The Xcode `AccentColor` asset is set to **RAL 1016 Sulfur Yellow** (`#F0D830`, RGB 0.941/0.847/0.188).

This applies to:
- Toggle switches
- Focused text fields / buttons
- Links and interactive controls
- Progress indicators

The accent is consistent in both light and dark mode.

---

## Database Icon Contrast Rule

`DatabaseCard.swift` uses a conditional icon color for the large database icon:
- **Dark mode**: `Color.dittoAccent` (Sulfur Yellow) — high contrast on dark gradient
- **Light mode**: `Color.Ditto.trafficBlack` — high contrast on light gradient

Sulfur Yellow on light backgrounds has insufficient WCAG contrast (~1.2:1), hence the conditional.

---

## Window Background

`ContentView.swift` applies `.background(Color.dittoAppBackground)` to the root `Group`. This single anchor propagates through all translucent system materials (`.ultraThinMaterial`, `.regularMaterial`) used by toolbars, sidebars, and status bars — giving the entire window a warm Ditto-branded tint without needing per-view changes.

---

## Rules

1. **Always use semantic tokens** — import from `BrandColors.swift`, never hardcode RAL hex values in view files.
2. **Use `.dittoGradientCard()`** for `DatabaseCard`, `SubscriptionCard`, and any new card components.
3. **Do NOT modify transport rainbow colors** in `ConnectedPeersView.swift` — Bluetooth blue, WiFi orange, etc. are intentionally semantic (transport type identification).
4. **Do NOT modify `LocalPeerInfoCard.swift`** — it already uses the correct RAL 9017→9005 gradient.
5. **Do NOT modify presence viewer** (`PresenceViewerSK.swift`, `ConnectionLine.swift`) — SpriteKit scene uses transport-semantic line colors.

---

## Files Summary

| File | Role |
|------|------|
| `Utilities/BrandColors.swift` | All color definitions and semantic tokens |
| `Components/LiquidGlassModifiers.swift` | `DittoGradientCard` modifier + `.dittoGradientCard()` extension |
| `Components/DatabaseCard.swift` | Uses `.dittoGradientCard()`, conditional icon color |
| `Components/SubscriptionCard.swift` | Uses `.dittoGradientCard()` |
| `Views/ContentView.swift` | Root `.background(Color.dittoAppBackground)` |
| `Assets.xcassets/AccentColor.colorset` | Sulfur Yellow accent |
