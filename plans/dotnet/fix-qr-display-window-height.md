# Plan: Fix QrCodeDisplayWindow Height and Button Spacing

## Problem

`QrCodeDisplayWindow` (450×520) clips the bottom buttons and leaves insufficient breathing room at the bottom of the window. The content stacks to approximately 532px, which overflows the 520px window height causing buttons to be cut off or pushed to the very bottom edge.

**File affected:** `dotnet/src/EdgeStudio/Views/QrCodeDisplayWindow.axaml`

**Screenshot:** `screens/dotnet/qrcode.png`

---

## Root Cause Analysis

Current layout math (with `Border Padding="24"` = 48px top+bottom and `StackPanel Spacing="16"`):

| Element | Height |
|---------|--------|
| Border padding top | 24px |
| Database name TextBlock | ~28px |
| Spacing | 16px |
| White border around QR (8px padding each side) | 316px (300 + 16) |
| Spacing | 16px |
| Instruction TextBlock (~2 lines at 12pt) | ~36px |
| Spacing | 16px |
| Buttons row | ~40px |
| Border padding bottom | 24px |
| **Total** | **~516px** |

At exactly 520px this is technically within bounds, but SukiUI's title bar chrome (~32-40px) sits *above* this content area, meaning the actual usable inner height is closer to 480-488px — causing visible cutoff.

---

## Fix

### Change 1: Increase window height

`Width="450" Height="520"` → `Width="450" Height="580"`

Also update the design-time dimensions:
`d:DesignWidth="450" d:DesignHeight="520"` → `d:DesignWidth="450" d:DesignHeight="580"`

This gives ~60px additional room, which accounts for the SukiUI chrome and adds comfortable bottom breathing room.

### Change 2: Add bottom margin to the buttons row

Add `Margin="0,0,0,8"` to the buttons `StackPanel` so there is an explicit gap between the buttons and the bottom of the `Border`:

```xml
<!-- Before -->
<StackPanel Orientation="Horizontal"
            HorizontalAlignment="Center"
            Spacing="10">

<!-- After -->
<StackPanel Orientation="Horizontal"
            HorizontalAlignment="Center"
            Spacing="10"
            Margin="0,0,0,8">
```

---

## Implementation

**Only one file changes:** `dotnet/src/EdgeStudio/Views/QrCodeDisplayWindow.axaml`

Specific line changes:

1. Line 8: `d:DesignHeight="520"` → `d:DesignHeight="580"`
2. Line 13: `Height="520"` → `Height="580"`
3. Line 49: Add `Margin="0,0,0,8"` to the buttons `StackPanel`

No C# code-behind changes required. No test changes required.

---

## Verification

1. Build: `dotnet build dotnet/src/EdgeStudio.sln --verbosity minimal`
2. Run tests: `dotnet test dotnet/src/EdgeStudioTests/EdgeStudioTests.csproj`
3. Launch the app, right-click a database card → "Show QR Code"
4. Confirm:
   - Window is visibly taller
   - QR code fully visible
   - "Copy Payload" and "Close" buttons have clear breathing room from the bottom edge
   - Both buttons fully rendered without clipping
