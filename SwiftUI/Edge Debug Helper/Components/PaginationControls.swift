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
            Picker("Page Size", selection: $pageSize) {
                ForEach(pageSizes, id: \.self) { size in
                    Text("\(size)").tag(size)
                }
            }
            .frame(minWidth: 100, idealWidth: 150, maxWidth: 200)
            .pickerStyle(DefaultPickerStyle())
            .padding(.horizontal)
            .onChange(of: pageSize) { oldValue, newValue in
                let startTime = CFAbsoluteTimeGetCurrent()
                print("🔄 PaginationControls: pageSize changed from \(oldValue) to \(newValue)")
                onPageSizeChange(newValue)
                let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
                print("⏱️ PaginationControls onChange took \(String(format: "%.1f", elapsed))ms")
            }

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
