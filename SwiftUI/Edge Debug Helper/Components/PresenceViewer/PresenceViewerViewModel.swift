import Foundation
import SwiftUI
@preconcurrency import DittoSwift
import SpriteKit

/// ViewModel for PresenceViewerSK
/// Manages presence graph observation, test mode, and scene state
/// Accesses DittoManager.shared singleton directly (no Ditto parameter needed)
@MainActor
@Observable
class PresenceViewerViewModel {
    // MARK: - Published State
    
    /// Test mode flag - when true, uses mock data instead of real Ditto presence
    var isTestMode: Bool = false {
        didSet {
            if isTestMode {
                startTestMode()
            } else {
                Task {
                    await stopTestModeAndResume()
                }
            }
        }
    }
    
    /// Current zoom level (0.5 = 50%, 1.0 = 100%, 2.0 = 200%)
    var zoomLevel: CGFloat = 1.0
    
    /// Local peer data (supports both real DittoPeer and mock test data)
    var localPeer: PeerProtocol?
    
    /// Remote peers data (supports both real DittoPeer and mock test data)
    var remotePeers: [PeerProtocol] = []

    /// Local peer key string for quick lookup
    var localPeerKey: String?
    
    // MARK: - Scene Reference
    
    /// Reference to the SpriteKit scene for updates
    weak var scene: PresenceNetworkScene?
    
    // MARK: - Private State

    /// Presence observer for real-time updates
    private var presenceObserver: DittoObserver?

    /// Timer for test mode updates
    private var testModeTimer: Timer?
    
    /// Mock data generator for test mode
    private var mockDataGenerator: MockPresenceDataGenerator?
    
    // MARK: - Initialization
    
    init() {
        // Start production mode - accesses DittoManager.shared directly
        Task {
            await startProductionMode()
        }
    }
    
    // MARK: - Production Mode (Real Ditto Presence)
    
    /// Start observing real Ditto presence graph
    /// Accesses DittoManager.shared.dittoSelectedApp (actor-isolated)
    func startProductionMode() async {
        // Access actor-isolated property
        guard let ditto = await DittoManager.shared.dittoSelectedApp else { 
            print("⚠️ PresenceViewerViewModel: No Ditto instance available")
            return 
        }
        
        presenceObserver = ditto.presence.observe { [weak self] presenceGraph in
            guard let self = self else { return }

            // Already on MainActor, no need for DispatchQueue.main.async
            self.localPeer = presenceGraph.localPeer
            self.remotePeers = Array(presenceGraph.remotePeers)
            self.localPeerKey = presenceGraph.localPeer.peerKeyString

            // Update scene if available
            if let scene = self.scene {
                scene.updatePresenceGraph(
                    localPeer: presenceGraph.localPeer,
                    remotePeers: Array(presenceGraph.remotePeers)
                )
            }
        }
    }
    
    /// Stop observing Ditto presence graph
    func stopProductionMode() {
        presenceObserver?.stop()
        presenceObserver = nil
    }
    
    // MARK: - Test Mode (Mock Data)
    
    /// Start test mode with mock data generation
    func startTestMode() {
        stopProductionMode()
        
        mockDataGenerator = MockPresenceDataGenerator()
        
        // Generate initial data
        updateTestData()
        
        // Update every 7 seconds
        testModeTimer = Timer.scheduledTimer(withTimeInterval: 7.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateTestData()
            }
        }
    }
    
    /// Stop test mode and return to production mode
    func stopTestModeAndResume() async {
        testModeTimer?.invalidate()
        testModeTimer = nil
        mockDataGenerator = nil
        
        await startProductionMode()
    }
    
    /// Update scene with new mock data
    private func updateTestData() {
        guard let generator = mockDataGenerator else { return }

        let mockData = generator.generateUpdate()

        localPeer = mockData.localPeer
        remotePeers = mockData.remotePeers
        localPeerKey = mockData.localPeer.peerKeyString

        // Update scene if available
        if let scene = scene {
            scene.updatePresenceGraph(
                localPeer: mockData.localPeer,
                remotePeers: mockData.remotePeers
            )
        }
    }
    
    // MARK: - Zoom Control
    
    /// Zoom in (decrease scale value)
    func zoomIn() {
        let newZoom = max(0.5, zoomLevel - 0.1)
        updateZoomLevel(newZoom)
    }
    
    /// Zoom out (increase scale value)
    func zoomOut() {
        let newZoom = min(2.0, zoomLevel + 0.1)
        updateZoomLevel(newZoom)
    }
    
    /// Update zoom level and apply to scene camera
    /// - Parameter level: New zoom level (0.5 to 2.0)
    func updateZoomLevel(_ level: CGFloat) {
        zoomLevel = level
        scene?.camera?.setScale(level)
    }
    
    // MARK: - Cleanup
    // Note: Cleanup happens automatically when ViewModel is deallocated
    // - DittoObserver cleans up when released
    // - Timer is invalidated in stopTestModeAndResume() when needed
}

// MockPresenceDataGenerator is now in its own file: MockPresenceDataGenerator.swift
// PresenceNetworkScene is now in its own file: PresenceNetworkScene.swift
