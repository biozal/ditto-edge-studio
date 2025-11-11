//
//  PaginationControls.swift
//  Edge Studio
//
//  Created by Aaron LaBeau on 6/9/25.
//

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

            // PERFORMANCE: Use Menu instead of Picker to avoid SwiftUI layout recalculation hang
            Menu {
                ForEach(pageSizes, id: \.self) { size in
                    Button("\(size)") {
                        let startTime = CFAbsoluteTimeGetCurrent()
                        let oldValue = pageSize
                        print("🔄 PaginationControls: pageSize changing from \(oldValue) to \(size)")
                        pageSize = size
                        onPageSizeChange(size)
                        let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
                        print("⏱️ PaginationControls onChange took \(String(format: "%.1f", elapsed))ms")
                    }
                }
            } label: {
                HStack {
                    Text("\(pageSize)")
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                }
                .frame(minWidth: 60)
            }
            .frame(minWidth: 100, idealWidth: 150, maxWidth: 200)
            .padding(.horizontal)

            Button(action: {
                onPageChange(currentPage - 1)
            }) {
                Image(systemName: "chevron.left")
            }
            .disabled(currentPage <= 1)

            Text("Page \(currentPage) of \(pageCount)")
                .font(.subheadline)
                .frame(minWidth: 100)

            Button(action: {
                onPageChange(currentPage + 1)
            }) {
                Image(systemName: "chevron.right")
            }
            .disabled(currentPage >= pageCount)
            Spacer()
        }
        .padding(.horizontal)
    }
}
