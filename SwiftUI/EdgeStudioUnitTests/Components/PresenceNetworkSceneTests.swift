import SpriteKit
import Testing

import DittoSwift

@testable import Ditto_Edge_Studio

// MARK: - PresenceNetworkScene Tests
//
// Headless scene tests via the MockPeer seam. An SKScene node tree works
// without an SKView for logic assertions: `presentScene` fires `didMove(to:)`
// synchronously (opening the scene's readiness gate), and SKActions enqueue
// but never advance without a rendering view — which makes the 0.3 s
// peer-removal fade window deterministic: a departed peer's node stays in the
// tree for the whole test, exactly like mid-fade in production.
//
// Assertions stick to synchronously observable scene state: `focusedPeerKey`,
// `layoutDirty`, and action presence/absence on named nodes
// (`//PeerNode_<key>`).

@Suite("PresenceNetworkScene Tests")
@MainActor
final class PresenceNetworkSceneTests {
    /// Retained so `scene.view` (weak) stays alive for the camera-fit math.
    private var skView: SKView?

    // MARK: Helpers

    private func makeScene(expanded: Bool = true) -> PresenceNetworkScene {
        let scene = PresenceNetworkScene()
        scene.size = CGSize(width: 1000, height: 800)
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 1000, height: 800))
        view.presentScene(scene) // fires didMove(to:) → the readiness gate opens
        skView = view
        scene.showDirectConnectedOnly = !expanded
        return scene
    }

    private func peer(_ key: String, connections: [MockConnection] = []) -> MockPeer {
        MockPeer(peerKey: key, deviceName: key, connections: connections)
    }

    private func link(_ a: String, _ b: String, _ type: DittoConnectionType = .p2pWiFi) -> MockConnection {
        MockConnection(type: type, id: "\(a)-\(b)-\(type)", peerKeyString1: a, peerKeyString2: b)
    }

    private func push(_ scene: PresenceNetworkScene, _ remotes: [MockPeer]) {
        scene.updatePresenceGraph(
            localPeer: MockPeer(peerKey: "local", deviceName: "Local", connections: []),
            remotePeers: remotes
        )
    }

    private func node(_ key: String, in scene: PresenceNetworkScene) throws -> PeerNode {
        try #require(scene.childNode(withName: "//PeerNode_\(key)") as? PeerNode)
    }

    /// Mesh used by the focus-routing tests: local–A and A–B edges (both
    /// advertised by A); C participates in no edge and is pure context.
    private func pushRoutingMesh(_ scene: PresenceNetworkScene) {
        push(scene, [
            peer("A", connections: [link("A", "local"), link("A", "B")]),
            peer("B"),
            peer("C")
        ])
    }

    // MARK: (a) Tap-routing table (focus mode, Expanded view)

    @Test("Tapping a remote peer enters focus mode", .tags(.fast))
    func tapEntersFocus() throws {
        let scene = makeScene()
        pushRoutingMesh(scene)

        scene.handlePeerTap(try node("A", in: scene))

        #expect(scene.focusedPeerKey == "A")
    }

    // Once focused, a tap means "show me this peer" — it reports the peer to the host,
    // which opens a detail card, and leaves the focus session alone. Tap used to mean
    // three different things here (re-tap exits, orbit peer refocuses, dimmed peer
    // exits), which is unlearnable; those meanings moved to the banner ✕, the
    // empty-canvas tap, and the card's own labelled "Focus this peer" action.

    @Test("Re-tapping the focused peer requests its detail card, keeping focus", .tags(.fast))
    func retapRequestsDetail() throws {
        let scene = makeScene()
        pushRoutingMesh(scene)
        scene.handlePeerTap(try node("A", in: scene))
        var requested: [String] = []
        scene.onPeerDetailRequested = { requested.append($0) }

        scene.handlePeerTap(try node("A", in: scene))

        #expect(requested == ["A"])
        #expect(scene.focusedPeerKey == "A", "focus must survive a detail tap")
    }

    @Test("Tapping an orbit peer requests its detail card, keeping focus", .tags(.fast))
    func orbitTapRequestsDetail() throws {
        let scene = makeScene()
        pushRoutingMesh(scene)
        scene.handlePeerTap(try node("A", in: scene))
        var requested: [String] = []
        scene.onPeerDetailRequested = { requested.append($0) }

        // B is in A's orbit (the A–B edge). Refocusing on it is now the card's action.
        scene.handlePeerTap(try node("B", in: scene))

        #expect(requested == ["B"])
        #expect(scene.focusedPeerKey == "A")
    }

    @Test("Tapping the local peer while focused requests its card too", .tags(.fast))
    func localInOrbitTapRequestsDetail() throws {
        // The local device used to be a no-op here. It has a real detail record — it is
        // the peer we know most about — so it gets a card like any other.
        let scene = makeScene()
        pushRoutingMesh(scene)
        scene.handlePeerTap(try node("A", in: scene))
        var requested: [String] = []
        scene.onPeerDetailRequested = { requested.append($0) }

        scene.handlePeerTap(try node("local", in: scene))

        #expect(requested == ["local"])
        #expect(scene.focusedPeerKey == "A")
    }

    @Test("Tapping a dimmed context peer requests its detail card, keeping focus", .tags(.fast))
    func contextTapRequestsDetail() throws {
        let scene = makeScene()
        pushRoutingMesh(scene)
        scene.handlePeerTap(try node("A", in: scene))
        var requested: [String] = []
        scene.onPeerDetailRequested = { requested.append($0) }

        // C is outside A's neighbourhood — it still has facts worth reading.
        scene.handlePeerTap(try node("C", in: scene))

        #expect(requested == ["C"])
        #expect(scene.focusedPeerKey == "A")
    }

    // MARK: (b) Focused-peer departure exits focus (via the model snapshot)

    @Test("Focused peer leaving the mesh exits focus", .tags(.fast))
    func focusedPeerDepartureExitsFocus() throws {
        let scene = makeScene()
        pushRoutingMesh(scene)
        scene.handlePeerTap(try node("A", in: scene))
        #expect(scene.focusedPeerKey == "A")

        // A leaves the mesh; the next push must clear focus in the same pass
        // (liveness from currentModelPeerKeys, not the fading node tree).
        push(scene, [peer("B"), peer("C")])

        #expect(scene.focusedPeerKey == nil)
    }

    // MARK: (c) Ghost focus: tapping a fading (model-dead) peer is ignored

    @Test("Tapping a departed peer mid-fade-out does not enter focus", .tags(.fast))
    func tapOnFadingPeerIsIgnored() throws {
        let scene = makeScene()
        pushRoutingMesh(scene)

        // A departs. Headless, the 0.3 s fade-out action never completes, so
        // A's node lingers in the tree exactly like mid-fade in production.
        push(scene, [peer("B"), peer("C")])
        let ghost = try node("A", in: scene)

        scene.handlePeerTap(ghost)

        #expect(scene.focusedPeerKey == nil)
    }

    // MARK: SF-1 — a rebuild during focus keeps the dim authoritative

    @Test("A peer joining during focus has its appear fade replaced by the dim fade", .tags(.fast))
    func joinDuringFocusStaysDimmed() throws {
        let scene = makeScene()
        pushRoutingMesh(scene)
        scene.handlePeerTap(try node("A", in: scene))
        #expect(scene.focusedPeerKey == "A")

        // D joins (advertising D–local). The topology push rebuilds the scene
        // and re-applies focus; D is context (not in A's neighbourhood).
        push(scene, [
            peer("A", connections: [link("A", "local"), link("A", "B")]),
            peer("B"),
            peer("C"),
            peer("D", connections: [link("D", "local")])
        ])

        // The 0.4 s appear fade must not outlive the 0.3 s context dim: the dim
        // pass kills "appearAnimation" and owns alpha via "focusFade".
        let d = try node("D", in: scene)
        #expect(d.action(forKey: "appearAnimation") == nil)
        #expect(d.action(forKey: "focusFade") != nil)
    }

    // MARK: (d) Mode toggle forces exactly one layout pass (layoutDirty)

    @Test("Mode toggle forces exactly one layout pass", .tags(.fast))
    func modeToggleForcesOneLayoutPass() throws {
        // Spokes only (local–A, local–B): Direct and Expanded aggregate the SAME
        // edges, so nothing but the mode flag can drive a layout pass.
        let scene = makeScene(expanded: false)
        let spokes = [
            peer("A", connections: [link("A", "local")]),
            peer("B", connections: [link("B", "local")])
        ]
        push(scene, spokes)
        push(scene, spokes)
        #expect(scene.layoutDirty == false)

        // The toggle itself only arms the flag — no layout until the next push.
        scene.showDirectConnectedOnly = false
        #expect(scene.layoutDirty == true)

        // The next push runs layout exactly once (consuming the flag)…
        push(scene, spokes)
        #expect(scene.layoutDirty == false)

        // …and a further unchanged push forces nothing more.
        push(scene, spokes)
        #expect(scene.layoutDirty == false)
    }

    // MARK: SF-10 — focus restore after a scene rebuild

    @Test("Focus restore re-enters when the hoisted peer is present in Expanded mode", .tags(.fast))
    func restoreFocusReenters() throws {
        let scene = makeScene()
        pushRoutingMesh(scene)

        scene.restoreFocusAfterRebuild(for: "A")

        #expect(scene.focusedPeerKey == "A")
    }

    @Test("Focus restore clears the hoist when the peer is gone", .tags(.fast))
    func restoreFocusClearsWhenPeerGone() throws {
        let scene = makeScene()
        push(scene, [peer("B")])
        var focusEvents: [(key: String?, name: String?)] = []
        scene.onFocusChanged = { key, name in focusEvents.append((key, name)) }

        scene.restoreFocusAfterRebuild(for: "A")

        #expect(scene.focusedPeerKey == nil)
        #expect(focusEvents.last?.key == nil)
        #expect(focusEvents.last?.name == nil)
    }

    @Test("Focus restore clears the hoist in Direct mode", .tags(.fast))
    func restoreFocusClearsInDirectMode() throws {
        let scene = makeScene(expanded: false)
        push(scene, [peer("A", connections: [link("A", "local")])])
        var focusEvents: [(key: String?, name: String?)] = []
        scene.onFocusChanged = { key, name in focusEvents.append((key, name)) }

        scene.restoreFocusAfterRebuild(for: "A")

        #expect(scene.focusedPeerKey == nil)
        #expect(focusEvents.last?.key == nil)
    }
}
