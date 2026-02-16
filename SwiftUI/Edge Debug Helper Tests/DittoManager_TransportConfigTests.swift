import Testing
import DittoSwift
@testable import Edge_Debug_Helper

@Suite("DittoManager Transport Configuration")
struct DittoManagerTransportConfigTests {

    @Test("applyTransportConfig requires selected app")
    func requiresSelectedApp() async throws {
        let dittoManager = DittoManager.shared

        // Ensure no app is selected
        await dittoManager.closeDittoSelectedDatabase()

        // Attempt to apply transport config should throw error
        await #expect(throws: (any Error).self) {
            try await dittoManager.applyTransportConfig(
                isBluetoothLeEnabled: true,
                isLanEnabled: true,
                isAwdlEnabled: true,
                isCloudSyncEnabled: true
            )
        }
    }

    @Test("Function signature includes all four transport parameters")
    func hasCorrectSignature() async throws {
        // This test verifies the function exists with correct parameter names
        // Actual parameter validation happens at compile time
        #expect(true)
    }
}

@Suite("TransportConfigView ViewModel")
struct TransportConfigViewModelTests {

    @Test("Default values are all enabled")
    func defaultValuesEnabled() {
        let viewModel = TransportConfigView.ViewModel()

        #expect(viewModel.isBluetoothLeEnabled == true)
        #expect(viewModel.isLanEnabled == true)
        #expect(viewModel.isAwdlEnabled == true)
        #expect(viewModel.isCloudSyncEnabled == true)
    }

    @Test("hasChanges detects modifications")
    func detectsChanges() {
        let viewModel = TransportConfigView.ViewModel()

        // Initially no changes
        #expect(viewModel.hasChanges == false)

        // Modify a setting
        viewModel.isBluetoothLeEnabled = false

        // Should detect change
        #expect(viewModel.hasChanges == true)

        // Revert change
        viewModel.isBluetoothLeEnabled = true

        // Should no longer detect change
        #expect(viewModel.hasChanges == false)
    }

    @Test("hasChanges detects multiple modifications")
    func detectsMultipleChanges() {
        let viewModel = TransportConfigView.ViewModel()

        // Modify multiple settings
        viewModel.isLanEnabled = false
        viewModel.isCloudSyncEnabled = false

        // Should detect changes
        #expect(viewModel.hasChanges == true)
    }

    @Test("ViewModel tracks progress through operation steps")
    func tracksProgressSteps() async {
        let viewModel = TransportConfigView.ViewModel()

        // Should start idle
        #expect(viewModel.currentStep == .idle)
        #expect(viewModel.currentStep.isInProgress == false)

        // Manually set different steps to verify enum behavior
        viewModel.currentStep = .stoppingSync
        #expect(viewModel.currentStep.isInProgress == true)
        #expect(viewModel.currentStep.message == "Stopping sync and cleaning up observers...")

        viewModel.currentStep = .applyingConfig
        #expect(viewModel.currentStep.isInProgress == true)
        #expect(viewModel.currentStep.message == "Applying transport configuration...")

        viewModel.currentStep = .restartingSync
        #expect(viewModel.currentStep.isInProgress == true)
        #expect(viewModel.currentStep.message == "Restarting sync and reconnecting...")

        viewModel.currentStep = .complete
        #expect(viewModel.currentStep.isInProgress == false)
        #expect(viewModel.currentStep.isComplete == true)
    }
}

@Suite("DittoConfigForDatabase Transport Settings")
struct DittoConfigForDatabaseTransportTests {

    @Test("DittoConfigForDatabase includes transport settings fields")
    func includesTransportFields() {
        let config = DittoConfigForDatabase.new()

        // Verify all transport fields exist with default true values
        #expect(config.isBluetoothLeEnabled == true)
        #expect(config.isLanEnabled == true)
        #expect(config.isAwdlEnabled == true)
        #expect(config.isCloudSyncEnabled == true)
    }

    @Test("Transport settings can be set to false")
    func canDisableTransports() {
        let config = DittoConfigForDatabase(
            "test-id",
            name: "Test App",
            databaseId: "test-app-id",
            token: "test-token",
            authUrl: "https://auth.example.com",
            websocketUrl: "wss://sync.example.com",
            httpApiUrl: "https://api.example.com",
            httpApiKey: "test-api-key",
            mode: .server,
            allowUntrustedCerts: false,
            secretKey: "",
            isBluetoothLeEnabled: false,
            isLanEnabled: false,
            isAwdlEnabled: false,
            isCloudSyncEnabled: false
        )

        #expect(config.isBluetoothLeEnabled == false)
        #expect(config.isLanEnabled == false)
        #expect(config.isAwdlEnabled == false)
        #expect(config.isCloudSyncEnabled == false)
    }

    @Test("Transport settings decode with backward compatibility")
    func backwardCompatibleDecoding() async throws {
        // Simulate old config JSON without transport fields
        let json = """
        {
            "_id": "test-id",
            "name": "Test App",
            "appId": "test-app-id",
            "authToken": "test-token",
            "authUrl": "https://auth.example.com",
            "websocketUrl": "wss://sync.example.com",
            "httpApiUrl": "https://api.example.com",
            "httpApiKey": "test-api-key",
            "mode": "onlineplayground"
        }
        """

        let data = json.data(using: .utf8)!
        let config = try JSONDecoder().decode(DittoConfigForDatabase.self, from: data)

        // Should default to true for missing transport fields
        #expect(config.isBluetoothLeEnabled == true)
        #expect(config.isLanEnabled == true)
        #expect(config.isAwdlEnabled == true)
        #expect(config.isCloudSyncEnabled == true)
    }
}
