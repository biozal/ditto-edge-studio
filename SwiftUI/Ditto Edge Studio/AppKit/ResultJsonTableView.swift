import SwiftUI
import AppKit

struct ResultJsonTableView: NSViewRepresentable {
    @Binding var items: [String]
    
    func makeNSView(context: Context) -> NSScrollView {
        let tableContainer = NSScrollView(frame: .zero)
        
        // Create table view
        let tableView = NSTableView()
        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        
        // Create column
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("jsonColumn"))
        column.title = "JSON"
        column.minWidth = 500
        tableView.addTableColumn(column)
        
        tableContainer.documentView = tableView
        tableContainer.hasVerticalScroller = true
        
        return tableContainer
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let tableView = nsView.documentView as? NSTableView else { return }
        // Update the coordinator's items without maintaining a parent reference
        context.coordinator.items = items
        tableView.reloadData()
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(items: items)
    }
    
    class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var items: [String]
        private var cachedHeights: [Int: CGFloat] = [:]
        
        // Reuse a single text field for height calculations
        private let heightCalculator = NSTextField()
        
        private var cachedTableWidth: CGFloat?
        
        init(items: [String]) {
            self.items = items
            super.init()
            // Configure the height calculator
            heightCalculator.isEditable = false
            heightCalculator.isBordered = false
            heightCalculator.cell?.wraps = true
            heightCalculator.cell?.truncatesLastVisibleLine = false
            heightCalculator.cell?.lineBreakMode = .byWordWrapping
            heightCalculator.font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        }
        
        func numberOfRows(in tableView: NSTableView) -> Int {
            return items.count
        }
        
        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard row < items.count else { return nil }
            
            let identifier = NSUserInterfaceItemIdentifier("JsonCell")
            var cellView = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView
            
            if cellView == nil {
                cellView = NSTableCellView()
                cellView?.identifier = identifier
                
                let textField = NSTextField()
                textField.isEditable = false
                textField.isSelectable = true
                textField.isBordered = false
                textField.drawsBackground = false
                textField.font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
                textField.cell?.wraps = true
                textField.cell?.truncatesLastVisibleLine = false
                textField.cell?.lineBreakMode = .byWordWrapping
                
                cellView?.addSubview(textField)
                cellView?.textField = textField
                
                textField.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    textField.leadingAnchor.constraint(equalTo: cellView!.leadingAnchor, constant: 5),
                    textField.trailingAnchor.constraint(equalTo: cellView!.trailingAnchor, constant: -5),
                    textField.topAnchor.constraint(equalTo: cellView!.topAnchor, constant: 5),
                    textField.bottomAnchor.constraint(equalTo: cellView!.bottomAnchor, constant: -5)
                ])
            }
            
            if let textField = cellView?.textField {
                textField.stringValue = items[row]
                
                // Ensure the cell sizes correctly
                textField.preferredMaxLayoutWidth = tableView.frame.width - 20
            }
            
            return cellView
        }
        
        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            // Return cached height if available
            if let cachedHeight = cachedHeights[row] {
                return cachedHeight
            }
            
            guard row < items.count else { return 44 }
            
            // Calculate height using a more efficient approach
            let text = items[row]
            let maxWidth = tableView.frame.width - 20
            
            // Reuse the height calculator
            heightCalculator.frame = NSRect(x: 0, y: 0, width: maxWidth, height: 0)
            heightCalculator.preferredMaxLayoutWidth = maxWidth
            heightCalculator.stringValue = text
            
            // Get a more accurate height
            let height = heightCalculator.cell?.cellSize(forBounds: NSRect(
                x: 0, y: 0,
                width: maxWidth,
                height: CGFloat.greatestFiniteMagnitude
            )).height ?? 0
            
            // Add padding and ensure minimum height
            let finalHeight = max(height + 10, 30)
            
            // Cache the result
            cachedHeights[row] = finalHeight
            
            return finalHeight
        }
        
        
        // Cache invalidation
        func tableViewColumnDidResize(_ notification: Notification) {
            // Only invalidate cache when column width changes significantly
            if let tableView = notification.object as? NSTableView,
               let oldWidth = cachedTableWidth,
               abs(oldWidth - tableView.frame.width) > 50 {
                cachedHeights.removeAll()
                cachedTableWidth = tableView.frame.width
            }
        }
    }
}
