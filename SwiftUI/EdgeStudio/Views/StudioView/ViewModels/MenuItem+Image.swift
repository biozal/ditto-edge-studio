import SwiftUI

/// SwiftUI rendering helper for `MenuItem`. Kept in a view-layer file so the
/// model itself (`Models/MenuItem.swift`) stays Foundation-pure — the sub-VMs
/// can import only Foundation/DittoSwift without dragging SwiftUI into the
/// view-model layer. Phase 10c extraction.
extension MenuItem {
    /// Picker tag content used by the inspector segmented pickers. The 48pt
    /// size matches the `NavigationSegmentedPicker` convention documented in
    /// CLAUDE.md ("Picker Navigation Consistency").
    var image: some View {
        Image(systemName: systemIcon)
            .font(.system(size: 48))
    }
}
