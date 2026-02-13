# Sprite Update Plan V2 - Match Reference Mocks

## Overview

Update all sprites to closely match the new reference images with:
1. Larger sizes (2-3x bigger)
2. More detailed designs
3. Smooth curves for cloud
4. 10 devices total in ring
5. More zoomed out default view

## Reference Image Analysis

### 1. iPhone (iphone.png)

**Current Issues:**
- Too small (24×48)
- Notch too small (6×2)
- Has bottom indicator (shouldn't have)

**Target Design:**
- **Size:** ~60×120 pixels (2.5x larger)
- **Aspect ratio:** Tall portrait (1:2)
- **Notch:** LARGE - spans ~30-40% of top width (~20-24px wide × 4px tall)
- **Corners:** Stepped pixelated corners (retro look)
- **Interior:** Clean white fill
- **Outline:** Black border
- **NO bottom indicator/home button**

**Drawing Instructions:**
```
Width: 60px, Height: 120px

Stepped corners (4-5 pixel steps):
- Top-left corner: steps inward
- Top-right corner: steps inward
- Bottom-left corner: steps inward
- Bottom-right corner: steps inward

Large notch at top center:
- Width: 22px (roughly 35% of phone width)
- Height: 4px
- Centered at top
- Black fill cutting into white interior

Border: 2px thick black outline
Interior: White fill
```

### 2. Laptop (laptop.png)

**Current Issues:**
- Too simple (just screen + base)
- Too small (48×32)
- No keyboard pattern or trackpad

**Target Design:**
- **Size:** ~100×70 pixels (2x+ larger)
- **Screen:** Large rectangle with thin black border, white interior
- **Keyboard:** Checkerboard pattern representing keys
- **Trackpad:** Visible rectangular area at bottom center
- **Stepped edges:** Pixelated retro corners
- **Base:** Thick section with keyboard details

**Drawing Instructions:**
```
Width: 100px, Height: 70px

Screen section (top 45px):
- Screen border: 100×45 with stepped corners
- Screen interior: White rectangle with 2px margin
- Thin black outline

Keyboard/base section (bottom 25px):
- Full width (100px)
- Checkerboard pattern for keys (alternating small squares)
- Trackpad: 20×8 rectangle at bottom center
- Black outline with stepped edges
```

### 3. Cloud (cloud.png)

**Current Issues:**
- Chunky stepped edges (should be smooth)
- Too small (64×32)
- Wrong shape (stepped rectangles vs smooth curves)

**Target Design:**
- **Size:** ~90×60 pixels (1.5x larger)
- **Shape:** Organic, smooth curved cloud
- **Style:** Smooth pixel art curves (not hard steps)
- **Bumps:** 3-4 smooth rounded bumps forming cloud top
- **Bottom:** Smooth curved base
- **Fill:** White interior, black outline

**Drawing Instructions:**
```
Width: 90px, Height: 60px

Smooth cloud shape using circles and curves:
- Bottom base: Wide oval/ellipse
- Left bump: Smooth circle (~20px radius)
- Center bump: Largest circle (~24px radius)
- Right bump: Medium circle (~18px radius)
- Right small bump: Small circle (~12px radius)

Use anti-aliasing technique:
- Draw overlapping circles to create smooth outline
- Fill entire interior with white
- Black outline follows smooth curve
```

### 4. Server (server.png)

**Current Issues:**
- Only 2 rack units (should be 3)
- Too simple (just LED squares)
- Too small (48×40)
- Missing detail elements (vent lines, status lights)

**Target Design:**
- **Size:** ~90×80 pixels
- **Rack units:** 3 stacked units with horizontal dividers
- **Each unit contains:**
  - **LED indicator** (left): Large square + small square
  - **Vent lines** (center): 3 horizontal lines
  - **Status lights** (right): 4 small squares in a row
- **Stepped edges:** Pixelated corners
- **Dividers:** Black horizontal lines between units

**Drawing Instructions:**
```
Width: 90px, Height: 80px

Outer border: 2px black with stepped corners

3 Rack units (each ~24px tall):
- Top unit: y=2 to y=26
- Middle unit: y=28 to y=52
- Bottom unit: y=54 to y=78

Each unit interior (repeated 3 times):
- White background

Left side (LED indicator):
  - Large square: 6×6 at x=6
  - Small square: 3×3 at x=14 (offset vertically)
  - Black fill

Center (vent lines):
  - 3 horizontal lines
  - Each 20px wide × 1-2px tall
  - Spaced evenly
  - x=30, centered vertically
  - Black fill

Right side (status lights):
  - 4 small squares (3×3 each)
  - Horizontal row
  - x=60, 66, 72, 78
  - Centered vertically in unit
  - Black fill

Horizontal dividers:
- Black lines at y=27 and y=53
- Full width
```

## Size Comparison

| Device | Current Size | Target Size | Scale Factor |
|--------|--------------|-------------|--------------|
| Phone | 24×48 | 60×120 | 2.5x larger |
| Laptop | 48×32 | 100×70 | 2-2.5x larger |
| Cloud | 64×32 | 90×60 | 1.5-2x larger |
| Server | 48×40 | 90×80 | 2x larger |

## Scene Configuration Updates

### Remove Tablets
- Delete PixelTabletTexture.swift
- Delete TabletNode.swift
- Remove tablet references from PresenceVisualizerScene.swift

### Reduce to 10 Devices

**Ring Composition:**
```
Position 0 (12 o'clock): Cloud ☁️
Position 1: Phone 📱
Position 2: Laptop 💻
Position 3: Phone 📱
Position 4: Phone 📱
Position 5: Server 🖥️
Position 6: Phone 📱
Position 7: Laptop 💻
Position 8: Phone 📱
Position 9: Phone 📱
```

**Distribution:**
- 1 Cloud (12 o'clock)
- 2 Laptops (positions 2, 7)
- 1 Server (6 o'clock)
- 6 Phones (remaining positions)
- Total: 10 devices

### Adjust Ring Radius

With larger devices, increase radius:
- Current: 40% of scene size
- Target: 45% of scene size (more spacing for bigger devices)

### Increase Default Zoom

User wants "zoomed out a bit more":
- Current: 1.25
- Target: 1.5 (50% more zoomed out than original 1.0)

## Implementation Plan

### Phase 1: Update Phone Texture (30 min)
**File:** PixelPhoneTexture.swift

- Change size: 24×48 → 60×120
- Add stepped/pixelated corners (4-5 pixel steps)
- Enlarge notch: 6×2 → 22×4 (much more prominent)
- Remove bottom indicator (delete that code)
- Increase border thickness if needed

### Phase 2: Update Laptop Texture (45 min)
**File:** PixelLaptopTexture.swift

- Change size: 48×32 → 100×70
- Add stepped corners
- Enlarge screen section (top 45px)
- Add keyboard section with checkerboard pattern
- Add trackpad rectangle (20×8 at bottom center)
- More detailed than current implementation

### Phase 3: Update Cloud Texture (60 min)
**File:** PixelCloudTexture.swift

**CRITICAL:** This needs smooth curves, not stepped edges!

- Change size: 64×32 → 90×60
- **Replace stepped rectangles with smooth circles/ovals**
- Use CGContext arc drawing for smooth curves
- Draw overlapping circles to create organic cloud shape:
  - Bottom base: Large oval
  - Top bumps: 3-4 overlapping circles of varying sizes
- Fill entire interior white
- Black outline follows curve
- This is the most complex change - smooth pixel art curves

### Phase 4: Update Server Texture (45 min)
**File:** PixelServerTexture.swift

- Change size: 48×40 → 90×80
- Increase to 3 rack units (was 2, originally 3)
- Add stepped corners
- For each rack unit, add detailed elements:
  - LED indicators (2 squares of different sizes)
  - Vent lines (3 horizontal lines in center)
  - Status lights (4 small squares in a row)
- Add horizontal divider lines between units
- Much more detailed than current

### Phase 5: Update Node Sizes (10 min)
**Files:** MobilePhoneNode.swift, LaptopNode.swift, CloudNode.swift, ServerNode.swift

- Update all init() size parameters to match new texture sizes:
  - MobilePhoneNode: 60×120
  - LaptopNode: 100×70
  - CloudNode: 90×60
  - ServerNode: 90×80

### Phase 6: Remove Tablets (5 min)
**Files to delete:**
- PixelTabletTexture.swift
- TabletNode.swift

### Phase 7: Update Scene (15 min)
**File:** PresenceVisualizerScene.swift

- Change totalNodes: 20 → 10
- Update ring composition (remove tablet positions)
- New distribution:
  - Position 0: Cloud
  - Positions 2, 7: Laptops
  - Position 5: Server
  - Positions 1, 3, 4, 6, 8, 9: Phones
- Increase radius: 40% → 45%

### Phase 8: Update Default Zoom (5 min)
**File:** PresenceViewerSK.swift

- Change zoomLevel: 1.25 → 1.5 (more zoomed out)

**Total time:** ~3.5 hours

## Pixel Art Techniques

### Stepped/Pixelated Corners

To create retro pixelated corners:
```swift
// Top-left corner (example)
// Instead of rounded corner, draw stepped rectangles:
context.fill(CGRect(x: 0, y: 10, width: 2, height: phoneHeight-20))  // Left edge
context.fill(CGRect(x: 2, y: 8, width: 2, height: 2))                // Step 1
context.fill(CGRect(x: 4, y: 6, width: 2, height: 2))                // Step 2
context.fill(CGRect(x: 6, y: 4, width: 2, height: 2))                // Step 3
context.fill(CGRect(x: 8, y: 2, width: 2, height: 2))                // Step 4
context.fill(CGRect(x: 10, y: 0, width: phoneWidth-20, height: 2))  // Top edge
```

### Smooth Cloud Curves

Use overlapping circles/arcs:
```swift
// Draw smooth cloud using arcs
let cloudPath = CGMutablePath()

// Bottom base (ellipse)
cloudPath.addEllipse(in: CGRect(x: 10, y: 10, width: 70, height: 30))

// Left bump
cloudPath.addArc(center: CGPoint(x: 25, y: 35),
                 radius: 20,
                 startAngle: 0,
                 endAngle: .pi * 2,
                 clockwise: true)

// Center bump (largest)
cloudPath.addArc(center: CGPoint(x: 45, y: 40),
                 radius: 24,
                 startAngle: 0,
                 endAngle: .pi * 2,
                 clockwise: true)

// Right bump
cloudPath.addArc(center: CGPoint(x: 65, y: 35),
                 radius: 18,
                 startAngle: 0,
                 endAngle: .pi * 2,
                 clockwise: true)

// Fill with white
context.addPath(cloudPath)
context.fillPath()

// Draw black outline
context.addPath(cloudPath)
context.setStrokeColor(blackColor)
context.setLineWidth(2)
context.strokePath()
```

## Files to Modify/Delete

**Modify (7 files):**
1. PixelPhoneTexture.swift - 60×120, large notch, stepped corners, no bottom indicator
2. PixelLaptopTexture.swift - 100×70, keyboard pattern, trackpad, stepped corners
3. PixelCloudTexture.swift - 90×60, smooth curves, organic shape
4. PixelServerTexture.swift - 90×80, 3 units, detailed indicators
5. MobilePhoneNode.swift - Update size to 60×120
6. LaptopNode.swift - Update size to 100×70
7. CloudNode.swift - Update size to 90×60
8. ServerNode.swift - Update size to 90×80
9. PresenceVisualizerScene.swift - 10 devices, 45% radius
10. PresenceViewerSK.swift - Zoom 1.5

**Delete (2 files):**
11. PixelTabletTexture.swift
12. TabletNode.swift

## Testing Checklist

- [ ] Phone: 60×120, large notch (22×4), stepped corners, NO bottom indicator
- [ ] Laptop: 100×70, keyboard checkerboard, trackpad visible, stepped corners
- [ ] Cloud: 90×60, smooth curves, organic fluffy shape
- [ ] Server: 90×80, 3 rack units, LED indicators, vent lines, status lights
- [ ] Ring: 10 devices total (1 cloud, 2 laptops, 1 server, 6 phones)
- [ ] Spacing: Devices don't overlap with larger sizes
- [ ] Default zoom: 1.5 (more zoomed out view)
- [ ] Animations: All devices still animate correctly
- [ ] Performance: 60 FPS maintained with larger textures

## Success Criteria

- ✅ All sprites match reference images closely
- ✅ Devices are 2-3x larger than previous version
- ✅ Cloud has smooth organic curves (not stepped)
- ✅ Laptop has keyboard details and trackpad
- ✅ Server has 3 detailed rack units
- ✅ Phone has large prominent notch
- ✅ 10 devices in ring (no tablets)
- ✅ Default view more zoomed out
- ✅ Professional network diagram appearance
