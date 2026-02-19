import SwiftUI

struct DatabaseListRow: View {
    let dittoApp: DittoConfigForDatabase
    @State private var isIdRevealed = false

    var body: some View {
        HStack(spacing: 12) {
            FontAwesomeText(icon: DataIcon.databaseThin, size: 26, color: .secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(dittoApp.name)
                    .font(.headline)
                    .foregroundColor(.primary)

                HStack(spacing: 4) {
                    Text(isIdRevealed
                        ? dittoApp.databaseId
                        : String(repeating: "•", count: min(dittoApp.databaseId.count, 24)))
                        .font(.caption.monospaced())
                        .foregroundColor(.secondary)
                        .lineLimit(1)

                    Button {
                        isIdRevealed.toggle()
                    } label: {
                        Image(systemName: isIdRevealed ? "eye.slash" : "eye")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .contentShape(Rectangle())
    }
}
