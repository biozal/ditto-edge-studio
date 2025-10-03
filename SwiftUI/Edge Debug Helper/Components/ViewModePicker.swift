//
//  ViewModePicker.swift
//  Edge Studio
//
//  Created by Claude Code on 10/2/25.
//

import SwiftUI

struct ViewModePicker: View {
    @Binding var selectedMode: QueryResultViewMode

    var body: some View {
        HStack(spacing: 0) {
            ForEach(QueryResultViewMode.allCases) { mode in
                Button {
                    selectedMode = mode
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: mode.iconName)
                            .font(.system(size: 12))
                        Text(mode.rawValue)
                            .font(.system(size: 12))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        selectedMode == mode
                            ? Color.gray.opacity(0.3)
                            : Color.clear
                    )
                    .foregroundColor(.primary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color.primary.opacity(0.1))
        .cornerRadius(8)
    }
}

#Preview {
    ViewModePicker(selectedMode: .constant(.table))
        .padding()
}
