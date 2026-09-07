import SwiftUI

/// SwiftUI rendering helper for `MenuItem`. Kept in a view-layer file so the
/// model itself (`Models/MenuItem.swift`) stays Foundation-pure — the sub-VMs
/// can import only Foundation/DittoSwift without dragging SwiftUI into the
/// view-model layer. Phase 10c extraction.
extension MenuItem {
    /// Picker tag content used by the inspector segmented pickers.
    ///
    /// Deliberately carries **no** font, so the symbol inherits whatever the
    /// call site sets — the way a `Text` segment would.
    ///
    /// It used to hardcode `.font(.system(size: 48))`. That was invisible while
    /// these pickers were native `.segmented` ones, because `NSSegmentedControl`
    /// rasterises its image to the segment's own metrics and simply ignored the
    /// oversized font. When they became the custom `DittoSegmentedPicker` — a
    /// plain `HStack` of `Button`s — nothing was clamping it any more and the
    /// icons rendered at literal 48pt.
    ///
    /// The size a caller passes has to live at the call site for a second
    /// reason: a font set here sits *closer to the leaf*, and the innermost
    /// font wins, so `image.font(…)` applied outside was silently inert.
    var image: some View {
        Image(systemName: systemIcon)
    }
}
