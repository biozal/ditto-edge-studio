import Foundation

/// A test-only offline license supplied out of band, never a cloud configuration.
struct UITestWorkspaceFixture: Codable, Sendable {
    let databaseId: String
    let developmentToken: String
    let secretKey: String?
}
