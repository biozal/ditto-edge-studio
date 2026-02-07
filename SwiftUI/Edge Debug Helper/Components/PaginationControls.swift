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

    var body: some View {
        HStack (alignment: .center) {
            Text("Total: \(totalCount)")
            Spacer()
            Picker("Page Size", selection: $pageSize) {
                ForEach(pageSizes, id: \.self) { size in
                    Text("\(size)").tag(size)
                }
            }
            .frame(minWidth: 100, idealWidth: 150, maxWidth: 200)
            .pickerStyle(DefaultPickerStyle())
            .padding(.horizontal)
            .onChange(of: pageSize) { _, newValue in
                onPageSizeChange(newValue)
            }

            Button(action: {
                onPageChange(currentPage - 1)
            }) {
                FontAwesomeText(icon: NavigationIcon.chevronLeft, size: 12)
            }
            .disabled(currentPage <= 1)

            Text("Page \(currentPage) of \(pageCount)")
                .font(.subheadline)
                .frame(minWidth: 100)

            Button(action: {
                onPageChange(currentPage + 1)
            }) {
                FontAwesomeText(icon: NavigationIcon.chevronRight, size: 12)
            }
            .disabled(currentPage >= pageCount)
            Spacer()
        }
        .padding(.horizontal)
    }
}
