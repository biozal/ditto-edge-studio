import Foundation
import Testing
@testable import Ditto_Edge_Studio

@Suite("UI test launch isolation")
struct UITestConfigurationTests {
    @Test func `production ignores test options without launch signal`() throws {
        let config = try UITestConfiguration(environment: [
            "UI_TEST_NAMESPACE": "../production", "UI_TEST_FIXTURE": "workspace"
        ])
        #expect(!config.isEnabled)
        #expect(config.storageDirectoryName == "ditto_edge_studio")
        #expect(config.preferencesSuiteName == nil)
    }

    @Test func `legacy desktop launch keeps its existing sandbox`() throws {
        let config = try UITestConfiguration(environment: [:], arguments: ["UI-TESTING"])
        #expect(config.isEnabled)
        #expect(config.fixture == .legacy)
        #expect(config.storageDirectoryName == "ditto_edge_studio_test")
        #expect(config.preferencesSuiteName == nil)
    }

    @Test func `separate cases have separate storage and preferences`() throws {
        let first = try configuration(namespace: UUID())
        let second = try configuration(namespace: UUID())
        #expect(first.storageDirectoryName != second.storageDirectoryName)
        #expect(first.preferencesSuiteName != second.preferencesSuiteName)
        #expect(first.storageDirectoryName.hasPrefix("ditto_edge_studio_test/"))
        #expect(first.fixture == .empty)
    }

    @Test func `relaunch retains the same namespace`() throws {
        let namespace = UUID()
        let first = try configuration(namespace: namespace)
        let relaunched = try configuration(namespace: namespace)
        #expect(first.storageDirectoryName == relaunched.storageDirectoryName)
        #expect(first.preferencesSuiteName == relaunched.preferencesSuiteName)
    }

    @Test(arguments: ["", "../ditto_edge_studio", "/tmp/test", "a/b", "not-a-uuid"])
    func `invalid namespace is rejected`(value: String) {
        #expect(throws: UITestConfiguration.ConfigurationError.self) {
            try UITestConfiguration(environment: ["UI_TESTING": "1", "UI_TEST_NAMESPACE": value])
        }
    }

    @Test func `explicit fixture requires namespace`() {
        #expect(throws: UITestConfiguration.ConfigurationError.self) {
            try UITestConfiguration(environment: ["UI_TESTING": "1", "UI_TEST_FIXTURE": "workspace"])
        }
    }

    @Test(arguments: ["legacy", "typo"])
    func `scoped runs reject legacy or unknown fixtures`(fixture: String) {
        #expect(throws: UITestConfiguration.ConfigurationError.self) {
            try configuration(namespace: UUID(), fixture: fixture)
        }
    }

    @Test func `workspace uses real offline configuration without network transports`() throws {
        let namespace = UUID()
        let testing = try configuration(namespace: namespace, fixture: "workspace")
        let data = try PropertyListEncoder().encode(UITestWorkspaceFixture(
            databaseId: "test-database", developmentToken: "test-license", secretKey: ""
        ))
        let config = try testing.workspaceConfiguration(encodedFixture: data.base64EncodedString())
        #expect(config._id == namespace.uuidString)
        #expect(config.databaseId == "test-database")
        #expect(config.mode == .smallPeerOnly)
        #expect(config.url.isEmpty)
        #expect(!config.isCloudSyncEnabled)
        #expect(!config.isBluetoothLeEnabled && !config.isLanEnabled && !config.isAwdlEnabled && !config.isMulticastEnabled)
        #expect(config.collectionSyncScopes.isEmpty && config.startupSettings.isEmpty)
    }

    @Test(arguments: [nil, "not-base64", Data("invalid plist".utf8).base64EncodedString()])
    func `missing or invalid workspace fixture fails`(encoded: String?) throws {
        let testing = try configuration(namespace: UUID(), fixture: "workspace")
        #expect(throws: UITestConfiguration.ConfigurationError.self) {
            try testing.workspaceConfiguration(encodedFixture: encoded)
        }
    }

    @Test func `empty smoke cannot load workspace credentials`() throws {
        let testing = try configuration(namespace: UUID())
        let data = try PropertyListEncoder().encode(UITestWorkspaceFixture(
            databaseId: "test-database", developmentToken: "test-license", secretKey: nil
        ))
        #expect(throws: UITestConfiguration.ConfigurationError.self) {
            try testing.workspaceConfiguration(encodedFixture: data.base64EncodedString())
        }
    }

    private func configuration(namespace: UUID, fixture: String = "empty") throws -> UITestConfiguration {
        try UITestConfiguration(environment: [
            "UI_TESTING": "1", "UI_TEST_NAMESPACE": namespace.uuidString, "UI_TEST_FIXTURE": fixture
        ])
    }

    @Test func `preferences persist only within their owned namespace`() throws {
        let first = try configuration(namespace: UUID())
        let second = try configuration(namespace: UUID())
        let firstDomain = try #require(first.preferencesSuiteName)
        let secondDomain = try #require(second.preferencesSuiteName)
        let firstStore = StudioPreferences.store(for: first)
        let secondStore = StudioPreferences.store(for: second)
        defer {
            firstStore.removePersistentDomain(forName: firstDomain)
            secondStore.removePersistentDomain(forName: secondDomain)
        }
        let key = "isolation-test-\(UUID().uuidString)"
        firstStore.set("first", forKey: key)
        #expect(secondStore.string(forKey: key) == nil)
        secondStore.set("second", forKey: key)
        #expect(StudioPreferences.store(for: first).string(forKey: key) == "first")
        #expect(StudioPreferences.store(for: second).string(forKey: key) == "second")
        #expect(UserDefaults.standard.string(forKey: key) == nil)
    }

    @Test func `ordinary preferences retain standard domain`() throws {
        let production = try UITestConfiguration(environment: [:])
        #expect(StudioPreferences.store(for: production) === UserDefaults.standard)
    }
}
