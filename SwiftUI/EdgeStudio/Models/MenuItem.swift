import Foundation

/// Identifiable / Hashable picker item used by the studio's inspector and
/// metrics picker controls. Foundation-pure: the SwiftUI rendering helper
/// (`MenuItem.image`) lives in `Views/StudioView/ViewModels/MenuItem+Image.swift`
/// so this type stays SwiftUI-free and can be referenced from the sub-VMs
/// without dragging SwiftUI into model files.
struct MenuItem: Identifiable, Equatable, Hashable {
    var id: Int
    var name: String
    /// SF Symbol name (e.g. `"clock"`, `"bookmark"`).
    var systemIcon: String
}
