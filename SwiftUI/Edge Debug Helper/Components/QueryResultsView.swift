import SwiftUI

struct QueryResultsView: View {
    @Binding var jsonResults: [String]
    @State private var isExporting = false
    @State private var resultsCount: Int = 0
   
    init(jsonResults: Binding<[String]>) {
        _jsonResults = jsonResults
        resultsCount = _jsonResults.wrappedValue.count
    }

    var body: some View {
        VStack {
            ResultJsonViewer(resultText: $jsonResults)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func flattenJsonResults() -> String {
        // If it's a single JSON object, just return it as is
        if jsonResults.count == 1 {
            return jsonResults.first ?? "[]"
        }
        // If it's multiple objects, wrap them in an array
        return "[\n" + jsonResults.joined(separator: ",\n") + "\n]"
    }
}

#Preview {
    QueryResultsView(jsonResults: .constant(["{\"key\": \"value\"}"]))
}
