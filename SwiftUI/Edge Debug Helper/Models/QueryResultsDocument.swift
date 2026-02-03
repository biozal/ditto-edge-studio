
import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct QueryResultsDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    
    var jsonData: String
    
    init(jsonData: String) {
        self.jsonData = jsonData
    }
    
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let string = String(data: data, encoding: .utf8)
        else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.jsonData = string
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = Data(jsonData.utf8)
        return FileWrapper(regularFileWithContents: data)
    }
}
