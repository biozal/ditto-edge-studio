import Foundation
import SwiftUI

struct PaginationControls: View {
    let totalCount: Int
    @Binding var currentPage: Int
    let pageCount: Int
    @Binding var pageSize: Int
    let pageSizes: [Int]
    let onPageChange: (Int) -> Void
    let onPageSizeChange: (Int) -> Void
    var onExport: (() -> Void)?

    /// Picker selection MUST have a matching tag in the rendered options or
    /// SwiftUI logs `Picker: the selection ... is invalid and does not have an
    /// associated tag`. When a result-set shrinks, `pageSizes` updates a render
    /// before the parent's `.onChange` clamps `pageSize`, so we transiently
    /// include the current `pageSize` here as a self-healing safeguard.
    private var displayedPageSizes: [Int] {
        guard !pageSizes.contains(pageSize) else { return pageSizes }
        return (pageSizes + [pageSize]).sorted()
    }

    var body: some View {
        HStack(alignment: .center) {
            // Total — document icon replaces "Total:" text
            HStack(spacing: 4) {
                Image(systemName: "document.on.document")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Text("\(totalCount)")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Picker("Page Size", selection: $pageSize) {
                ForEach(displayedPageSizes, id: \.self) { size in Text("\(size)").tag(size) }
            }
            .frame(minWidth: 100, idealWidth: 150, maxWidth: 200)
            .pickerStyle(DefaultPickerStyle())
            .padding(.horizontal)
            .onChange(of: pageSize) { _, newValue in onPageSizeChange(newValue) }

            Button { onPageChange(currentPage - 1) } label: {
                FontAwesomeText(icon: NavigationIcon.chevronLeft, size: 15)
            }
            .disabled(currentPage <= 1)
            .accessibilityIdentifier("PaginationPrevButton")

            // "X of Y" — removed "Page " prefix
            Text("\(currentPage) of \(pageCount)")
                .font(.subheadline)
                .frame(minWidth: 80)
                .accessibilityIdentifier("PaginationPageIndicator")
                .accessibilityValue("\(currentPage) of \(pageCount)")

            Button { onPageChange(currentPage + 1) } label: {
                FontAwesomeText(icon: NavigationIcon.chevronRight, size: 15)
            }
            .disabled(currentPage >= pageCount)
            .accessibilityIdentifier("PaginationNextButton")

            // Overflow menu — only rendered when export handler is provided
            if let onExport {
                Spacer()
                Menu {
                    Button("Export JSON") { onExport() }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal)
    }
}
