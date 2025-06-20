//
//  Pill.swift
//  Edge Studio
//
//  Created by Aaron LaBeau on 6/5/25.
//

import SwiftUI

struct Pill: View {
    var text: String
    
    var color: Color = .gray
    var body: some View {
        Text(text)
            .font(.footnote)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(color.opacity(0.2))
            .foregroundColor(color)
            .clipShape(Capsule())
    }
}

#Preview {
    Pill(text: "Active", color: .green)
    Pill(text: "Inactive", color: .gray)
}
