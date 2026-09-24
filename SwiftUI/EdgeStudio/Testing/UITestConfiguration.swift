import Foundation

/// Immutable launch configuration, resolved before any singleton opens storage.
/// Legacy desktop tests keep their existing sandbox; scoped runs never use it.
struct UITestConfiguration: Sendable {
    enum Fixture: String, Sendable {
        case legacy, empty, workspace
    }

    enum ConfigurationError: Error {
        case invalidNamespace, invalidFixture, missingWorkspaceFixture
    }

    static let current: UITestConfiguration = {
        do {
            return try UITestConfiguration(
                environment: ProcessInfo.processInfo.environment,
                arguments: ProcessInfo.processInfo.arguments
            )
        } catch {
            // Never include the launch environment: it may contain a test license.
            preconditionFailure("Invalid UI test configuration; check namespace and fixture selection")
        }
    }()

    let isEnabled: Bool
    let namespace: UUID?
    let fixture: Fixture

    init(environment: [String: String], arguments: [String] = []) throws {
        isEnabled = environment["UI_TESTING"] == "1" || arguments.contains("UI-TESTING")
        guard isEnabled else {
            namespace = nil
            fixture = .legacy
            return
        }
        if let value = environment["UI_TEST_NAMESPACE"] {
            guard let identifier = UUID(uuidString: value) else {
                throw ConfigurationError.invalidNamespace
            }
            namespace = identifier
            guard let selected = Fixture(rawValue: environment["UI_TEST_FIXTURE"] ?? "empty"), selected != .legacy else {
                throw ConfigurationError.invalidFixture
            }
            fixture = selected
        } else {
            guard environment["UI_TEST_FIXTURE"] == nil else {
                throw ConfigurationError.invalidNamespace
            }
            namespace = nil
            fixture = .legacy
        }
    }

    var storageDirectoryName: String {
        guard isEnabled else { return "ditto_edge_studio" }
        guard let namespace else { return "ditto_edge_studio_test" }
        return "ditto_edge_studio_test/\(namespace.uuidString)"
    }

    var preferencesSuiteName: String? {
        namespace.map { "com.costoda.dittoedgestudio.uitests.\($0.uuidString)" }
    }

    func workspaceConfiguration(encodedFixture: String?) throws -> DittoConfigForDatabase {
        guard fixture == .workspace, let namespace,
              let encodedFixture, let data = Data(base64Encoded: encodedFixture),
              let payload = try? PropertyListDecoder().decode(UITestWorkspaceFixture.self, from: data),
              !payload.databaseId.isEmpty, !payload.developmentToken.isEmpty else
        {
            throw ConfigurationError.missingWorkspaceFixture
        }
        return DittoConfigForDatabase(
            namespace.uuidString,
            name: "Mobile UI Test Database",
            databaseId: payload.databaseId,
            developmentToken: payload.developmentToken,
            url: "", httpApiUrl: "", httpApiKey: "",
            mode: .smallPeerOnly,
            secretKey: payload.secretKey ?? "",
            isBluetoothLeEnabled: false, isLanEnabled: false,
            isAwdlEnabled: false, isCloudSyncEnabled: false,
            collectionSyncScopes: [], startupSettings: []
        )
    }
}
