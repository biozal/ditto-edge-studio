import SwiftUI

struct QueryEditorView: View {
    @Binding var queryText: String

    var body: some View {
        DQLCodeEditor(text: $queryText)
    }
}

#Preview {
    QueryEditorView(queryText: .constant("SELECT * FROM users"))
}
