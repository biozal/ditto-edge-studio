import CodeEditor
import SwiftUI

struct QueryEditorView: View {
    @Binding var queryText: String
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        CodeEditor(
            source: $queryText,
            language: .sql,
            theme: colorScheme == .dark ? .atelierSavannaDark : .atelierSavannaLight
        )
    }
}

#Preview {
    QueryEditorView(queryText: .constant("SELECT * FROM users"))
}
