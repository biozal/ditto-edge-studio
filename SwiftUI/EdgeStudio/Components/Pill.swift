import SwiftUI

struct Pill: View {
    var text: String

    var color: Color = .gray
    var body: some View {
        Text(text)
            .font(.footnote)
            .fontWeight(.medium)
            .padding(.horizontal, 16) // Increased from 12
            .padding(.vertical, 8) // Increased from 6
            .background(.ultraThinMaterial)
            .background(color.opacity(0.15)) // Subtle tint
            .foregroundColor(color)
            .clipShape(Capsule())
            .overlay(Capsule()
                .stroke(color.opacity(0.3), lineWidth: 0.5))
            .subtleShadow()
    }
}

#Preview {
    Pill(text: "Active", color: .green)
    Pill(text: "Inactive", color: .gray)
}
