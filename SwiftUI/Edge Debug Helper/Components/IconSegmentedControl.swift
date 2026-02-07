import SwiftUI
import AppKit

/// A segmented control that properly displays SF Symbol icons using native NSSegmentedControl
/// This provides the same appearance as Xcode's inspector and sidebar segmented controls
struct IconSegmentedControl<Item: Identifiable & Hashable>: NSViewRepresentable {
    let items: [Item]
    @Binding var selection: Item
    let iconForItem: (Item) -> String
    let nameForItem: (Item) -> String
    
    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        let control = NSSegmentedControl()

        control.segmentStyle = .rounded
        control.trackingMode = .selectOne

        // Configure segments
        control.segmentCount = items.count

        for (index, item) in items.enumerated() {
            // Create SF Symbol image with proper sizing
            let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
            if let image = NSImage(systemSymbolName: iconForItem(item), accessibilityDescription: nameForItem(item))?.withSymbolConfiguration(config) {
                control.setImage(image, forSegment: index)
            }
            control.setToolTip(nameForItem(item), forSegment: index)
        }

        // Set initial selection
        if let selectedIndex = items.firstIndex(of: selection) {
            control.selectedSegment = selectedIndex
        }

        // Connect action
        control.target = context.coordinator
        control.action = #selector(Coordinator.segmentChanged(_:))

        // Use pure frame-based layout - NO Auto Layout to prevent constraint loops
        // This fixes the infinite constraint update loop when resizing the sidebar
        container.addSubview(control)
        control.translatesAutoresizingMaskIntoConstraints = true  // Enable frame-based layout
        control.autoresizingMask = [.width, .height]  // Resize with container

        // Set accessibility identifier for UI testing
        control.setAccessibilityIdentifier("SidebarSegmentedControl")

        // Store control reference for updates
        context.coordinator.control = control

        return container
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        guard let control = context.coordinator.control else { return }

        // Don't update if we're already processing a segment change
        guard !context.coordinator.isUpdating else { return }

        // Manually size the control to fill the container (frame-based layout)
        if control.frame.size != nsView.bounds.size {
            control.frame = nsView.bounds
        }

        // Only update selection if it changed externally
        if let selectedIndex = items.firstIndex(of: selection) {
            if control.selectedSegment != selectedIndex {
                control.selectedSegment = selectedIndex
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(items: items, selection: $selection)
    }
    
    class Coordinator: NSObject {
        let items: [Item]
        @Binding var selection: Item
        weak var control: NSSegmentedControl?
        var isUpdating = false  // Prevent reentrancy

        init(items: [Item], selection: Binding<Item>) {
            self.items = items
            self._selection = selection
            super.init()
        }

        @objc func segmentChanged(_ sender: NSSegmentedControl) {
            // Prevent reentrancy - guard against crashes from recursive updates
            guard !isUpdating else { return }

            let selectedIndex = sender.selectedSegment

            // Safety checks to prevent crash
            guard selectedIndex >= 0, selectedIndex < items.count else {
                return
            }

            let newSelection = items[selectedIndex]

            // Prevent recursive updates during state change
            isUpdating = true

            // Update on main thread to prevent crashes
            if Thread.isMainThread {
                selection = newSelection
                isUpdating = false
            } else {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.selection = newSelection
                    self.isUpdating = false
                }
            }
        }
    }
}
