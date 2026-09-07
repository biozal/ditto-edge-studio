import DittoSwift
import SpriteKit
import Testing
@testable import Ditto_Edge_Studio

// MARK: - PresencePeerSearch Tests

//
// The pure matching rules behind the Presence Viewer's peer search — the VS Code
// extension's `graphSearchCandidates` / `graphSearchMatches`. Kept Foundation-pure
// precisely so these can be asserted without a scene, a Ditto instance, or a view.

@Suite("PresencePeerSearch Tests")
struct PresencePeerSearchTests {
    private func peer(_ key: String, _ name: String, cloud: Bool = false) -> MockPeer {
        MockPeer(peerKey: key, deviceName: name, connections: [], isConnectedToDittoCloud: cloud)
    }

    // MARK: Candidates

    @Test(.tags(.fast))
    func `Candidates come from the UNFILTERED graph, so multi-hop peers are findable`() {
        // ARRANGE: B is two hops away — it is in the graph but would be absent
        // from the Direct-mode projection. Finding it is the whole point.
        let local = peer("local", "My Mac")
        let remotes = [peer("A", "Alpha"), peer("B", "Bravo")]

        // ACT
        let candidates = PresencePeerSearch.candidates(localPeer: local, remotePeers: remotes)

        // ASSERT
        #expect(candidates.map(\.key) == ["A", "B", "local"])
    }

    @Test(.tags(.fast))
    func `Card order is remote peers, then cloud, then the local device last`() {
        // ARRANGE
        let local = peer("local", "My Mac", cloud: true)
        let remotes = [peer("A", "Alpha")]

        // ACT
        let candidates = PresencePeerSearch.candidates(localPeer: local, remotePeers: remotes)

        // ASSERT
        #expect(candidates.map(\.key) == ["A", PresencePeerSearch.cloudPeerKey, "local"])
        #expect(candidates.last?.isLocal == true)
        // The cloud node is a normal, focusable peer — only the local one is not.
        #expect(candidates[1].isLocal == false)
        #expect(candidates[1].name == PresencePeerSearch.cloudDisplayName)
    }

    @Test(.tags(.fast))
    func `No cloud candidate without a cloud link`() {
        // ARRANGE: the SDK only exposes the LOCAL peer's cloud status
        let local = peer("local", "My Mac", cloud: false)

        // ACT
        let candidates = PresencePeerSearch.candidates(localPeer: local, remotePeers: [])

        // ASSERT
        #expect(candidates.map(\.key) == ["local"])
    }

    @Test(.tags(.fast))
    func `An edgeless orphan peer is not offered as a search result`() {
        // ARRANGE: C participates in no connection at all — the sync stop→start
        // window, or a peer discovered before a session exists. The scene filters
        // it out (`meshVisiblePeerKeys`), so it never becomes a node and can never
        // be focused; offering it as a clickable row flips Direct off and then
        // silently does nothing.
        let local = MockPeer(peerKey: "local", deviceName: "Local", connections: [
            MockConnection(type: .p2pWiFi, id: "l-A", peerKeyString1: "local", peerKeyString2: "A")
        ])
        let remotes: [any PeerProtocol] = [
            MockPeer(peerKey: "A", deviceName: "Alpha", connections: [
                MockConnection(type: .p2pWiFi, id: "l-A", peerKeyString1: "local", peerKeyString2: "A")
            ]),
            MockPeer(peerKey: "C", deviceName: "Orphan", connections: [])
        ]

        // ACT: the candidate set the view model builds — mesh-visible peers only
        let visible = PresenceEdgeAggregator.meshVisiblePeerKeys(localPeer: local, remotePeers: remotes)
        let candidates = PresencePeerSearch.candidates(
            localPeer: local,
            remotePeers: remotes.filter { visible.contains($0.peerKeyString) }
        )

        // ASSERT
        #expect(candidates.map(\.key).contains("A"))
        #expect(candidates.map(\.key).contains("C") == false)
        #expect(PresencePeerSearch.matches(in: candidates, query: "orphan").isEmpty)
    }

    @Test(.tags(.fast))
    func `Duplicate and empty keys are dropped`() {
        // ARRANGE: the same peer reported twice, plus a keyless entry
        let local = peer("local", "My Mac")
        let remotes = [peer("A", "Alpha"), peer("A", "Alpha again"), peer("", "Nameless")]

        // ACT
        let candidates = PresencePeerSearch.candidates(localPeer: local, remotePeers: remotes)

        // ASSERT
        #expect(candidates.map(\.key) == ["A", "local"])
        #expect(candidates.first?.name == "Alpha") // first report wins
    }

    // MARK: Matching

    @Test(.tags(.fast))
    func `Matching is case-insensitive over BOTH device name and peer key`() {
        // ARRANGE
        let candidates = PresencePeerSearch.candidates(
            localPeer: peer("local", "My Mac"),
            remotePeers: [peer("aBcDeF123", "Pixel Tablet"), peer("zzz", "Galaxy Fold")]
        )

        // ACT / ASSERT: name match, either case
        #expect(PresencePeerSearch.matches(in: candidates, query: "pixel").map(\.key) == ["aBcDeF123"])
        #expect(PresencePeerSearch.matches(in: candidates, query: "PIXEL").map(\.key) == ["aBcDeF123"])
        // key match, either case
        #expect(PresencePeerSearch.matches(in: candidates, query: "ABCDEF").map(\.key) == ["aBcDeF123"])
        // substring, not prefix
        #expect(PresencePeerSearch.matches(in: candidates, query: "fold").map(\.key) == ["zzz"])
    }

    @Test(.tags(.fast))
    func `The query is trimmed before matching`() {
        // ARRANGE
        let candidates = PresencePeerSearch.candidates(
            localPeer: peer("local", "My Mac"),
            remotePeers: [peer("A", "Alpha")]
        )

        // ACT / ASSERT
        #expect(PresencePeerSearch.matches(in: candidates, query: "  alpha \n").map(\.key) == ["A"])
    }

    @Test(.tags(.fast))
    func `Whitespace alone is not an active search and matches nothing`() {
        // ARRANGE
        let candidates = PresencePeerSearch.candidates(
            localPeer: peer("local", "My Mac"),
            remotePeers: [peer("A", "Alpha")]
        )

        // ACT / ASSERT
        #expect(PresencePeerSearch.isActive(query: "   ") == false)
        #expect(PresencePeerSearch.isActive(query: "") == false)
        #expect(PresencePeerSearch.isActive(query: " a ") == true)
        #expect(PresencePeerSearch.matches(in: candidates, query: "   ").isEmpty)
    }

    @Test(.tags(.fast))
    func `A zero-hit query returns an empty match list, not every candidate`() {
        // ARRANGE
        let candidates = PresencePeerSearch.candidates(
            localPeer: peer("local", "My Mac"),
            remotePeers: [peer("A", "Alpha")]
        )

        // ACT
        let matches = PresencePeerSearch.matches(in: candidates, query: "nothing-like-this")

        // ASSERT: the caller turns this into an EMPTY match set (dim everything),
        // which is a different state from "not searching" (dim nothing).
        #expect(matches.isEmpty)
    }

    @Test(.tags(.fast))
    func `The local device is matchable, and flagged so the card can refuse to focus it`() {
        // ARRANGE
        let candidates = PresencePeerSearch.candidates(
            localPeer: peer("local", "My Mac"),
            remotePeers: [peer("A", "My Alpha")]
        )

        // ACT
        let matches = PresencePeerSearch.matches(in: candidates, query: "my")

        // ASSERT
        #expect(matches.map(\.key) == ["A", "local"])
        #expect(matches.first(where: { $0.isLocal })?.key == "local")
    }

    // MARK: Display helpers

    @Test(.tags(.fast))
    func `Long peer keys are truncated for the key column; short ones are not`() {
        // ARRANGE
        let long = String(repeating: "a", count: 40)

        // ACT / ASSERT
        #expect(PresencePeerSearch.truncatedKey("short") == "short")
        #expect(PresencePeerSearch.truncatedKey(long) == "\(String(repeating: "a", count: 24))…")
    }

    @Test(.tags(.fast))
    func `An unnamed peer still renders a clickable label`() {
        // ARRANGE / ACT
        let match = PresencePeerSearchMatch(key: "A", name: "", isLocal: false)

        // ASSERT
        #expect(match.displayName == "(unnamed)")
    }
}

// MARK: - Search dimming in the scene

//
// Same headless-scene seam as PresenceNetworkSceneTests: `presentScene` opens the
// readiness gate synchronously, and SKActions enqueue without advancing, so the
// assertions here are on `restingAlpha` (the authoritative dim state) and on
// action presence — never on a mid-animation `alpha`.

@Suite("Presence search dimming")
@MainActor
final class PresenceSearchDimmingTests {
    private var skView: SKView?

    private func makeScene() -> PresenceNetworkScene {
        let scene = PresenceNetworkScene()
        scene.size = CGSize(width: 1000, height: 800)
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 1000, height: 800))
        view.presentScene(scene)
        skView = view
        scene.showDirectConnectedOnly = false
        return scene
    }

    private func link(_ a: String, _ b: String) -> MockConnection {
        MockConnection(type: .p2pWiFi, id: "\(a)-\(b)", peerKeyString1: a, peerKeyString2: b)
    }

    /// local–A and A–B, so B is a multi-hop peer.
    private func pushMesh(_ scene: PresenceNetworkScene) {
        scene.updatePresenceGraph(
            localPeer: MockPeer(peerKey: "local", deviceName: "Local", connections: [link("local", "A")]),
            remotePeers: [
                MockPeer(peerKey: "A", deviceName: "Alpha", connections: [link("local", "A"), link("A", "B")]),
                MockPeer(peerKey: "B", deviceName: "Bravo", connections: [link("A", "B")])
            ]
        )
    }

    private func line(_ from: String, _ to: String) -> ConnectionLine {
        ConnectionLine(from: from, to: to, type: .p2pWiFi, fromPos: .zero, toPos: CGPoint(x: 100, y: 0))
    }

    @Test(.tags(.fast))
    func `An empty box means no search dimming at all`() {
        // ARRANGE
        let scene = makeScene()
        pushMesh(scene)

        // ACT
        scene.setSearchMatches(nil)

        // ASSERT
        #expect(scene.searchMatchKeys == nil)
        #expect(scene.restingAlpha(forPeerKey: "A") == 1.0)
        #expect(scene.restingAlpha(forPeerKey: "B") == 1.0)
        #expect(scene.restingAlpha(for: line("A", "B")) == 1.0)
    }

    @Test(.tags(.fast))
    func `Matches stay lit; everything else takes the selection dim`() {
        // ARRANGE
        let scene = makeScene()
        pushMesh(scene)

        // ACT
        scene.setSearchMatches(["B"])

        // ASSERT
        #expect(scene.restingAlpha(forPeerKey: "B") == 1.0)
        #expect(scene.restingAlpha(forPeerKey: "A") < 1.0)
        #expect(scene.restingAlpha(forPeerKey: "local") < 1.0)
    }

    @Test(.tags(.fast))
    func `A connection touching a match stays lit; one touching none dims`() {
        // ARRANGE
        let scene = makeScene()
        pushMesh(scene)

        // ACT
        scene.setSearchMatches(["B"])

        // ASSERT
        #expect(scene.restingAlpha(for: line("A", "B")) == 1.0)
        #expect(scene.restingAlpha(for: line("B", "A")) == 1.0) // either endpoint
        #expect(scene.restingAlpha(for: line("local", "A")) < 1.0)
    }

    @Test(.tags(.fast))
    func `A zero-hit query is an EMPTY set, and dims the whole graph`() {
        // ARRANGE
        let scene = makeScene()
        pushMesh(scene)

        // ACT: active search, no matches — NOT the same as clearing the box
        scene.setSearchMatches([])

        // ASSERT
        #expect(scene.searchMatchKeys == [])
        #expect(scene.restingAlpha(forPeerKey: "A") < 1.0)
        #expect(scene.restingAlpha(forPeerKey: "B") < 1.0)
        #expect(scene.restingAlpha(forPeerKey: "local") < 1.0)
        #expect(scene.restingAlpha(for: line("local", "A")) < 1.0)
    }

    @Test(.tags(.fast))
    func `Clearing the query restores full opacity everywhere`() throws {
        // ARRANGE
        let scene = makeScene()
        pushMesh(scene)
        scene.setSearchMatches(["B"])

        // ACT
        scene.setSearchMatches(nil)

        // ASSERT
        #expect(scene.restingAlpha(forPeerKey: "A") == 1.0)
        #expect(scene.restingAlpha(for: line("local", "A")) == 1.0)
        // ...and the repaint was actually scheduled, not just the state changed.
        let node = try #require(scene.childNode(withName: "//PeerNode_A") as? PeerNode)
        #expect(node.action(forKey: "focusFade") != nil)
    }

    @Test(.tags(.fast))
    func `Focus mode outranks an active search`() {
        // ARRANGE: search matches B only...
        let scene = makeScene()
        pushMesh(scene)
        scene.setSearchMatches(["B"])

        // ACT: ...then focus A, whose neighbourhood is local + A + B
        scene.focusPeer("A")

        // ASSERT: the focus neighbourhood is lit even though only B matched
        #expect(scene.focusedPeerKey == "A")
        #expect(scene.restingAlpha(forPeerKey: "local") == 1.0)
        #expect(scene.restingAlpha(forPeerKey: "A") == 1.0)
    }

    @Test(.tags(.fast))
    func `Leaving focus falls back to the search dim, not to full opacity`() {
        // ARRANGE: this is the defect a hard-coded `restoreAllAlpha` to 1.0 caused
        let scene = makeScene()
        pushMesh(scene)
        scene.setSearchMatches(["B"])
        scene.focusPeer("A")

        // ACT
        scene.exitFocusMode()

        // ASSERT
        #expect(scene.focusedPeerKey == nil)
        #expect(scene.restingAlpha(forPeerKey: "B") == 1.0)
        #expect(scene.restingAlpha(forPeerKey: "A") < 1.0)
        #expect(scene.restingAlpha(forPeerKey: "local") < 1.0)
    }

    @Test(.tags(.fast))
    func `a search push does not cancel the scale-up of a peer that just joined`() throws {
        // ARRANGE: the production order — the presence push creates the node (and
        // starts its 0.4 s appear animation), and the SAME push then hands the
        // scene the recomputed match set.
        let scene = makeScene()
        pushMesh(scene)
        let node = try #require(scene.childNode(withName: "//PeerNode_B") as? PeerNode)
        #expect(node.action(forKey: "appearScale") != nil)

        // ACT
        scene.setSearchMatches(["B"])

        // ASSERT: the dim pass owns the alpha and replaces it...
        #expect(node.action(forKey: "appearFade") == nil)
        #expect(node.action(forKey: "focusFade") != nil)
        // ...but must NOT take the scale-up with it. Grouped under one action key,
        // removing the fade also killed the scale and left the node frozen at
        // `setScale(0.5)` — a permanent half-size pill, for the very peer the user
        // was searching for.
        #expect(node.action(forKey: "appearScale") != nil)
    }

    @Test(.tags(.fast))
    func `focusPeer re-picking the focused peer toggles focus off`() {
        // ARRANGE
        let scene = makeScene()
        pushMesh(scene)
        scene.focusPeer("A")
        #expect(scene.focusedPeerKey == "A")

        // ACT
        scene.focusPeer("A")

        // ASSERT
        #expect(scene.focusedPeerKey == nil)
    }

    @Test(.tags(.fast))
    func `focusPeer switches focus between peers without exiting first`() {
        // ARRANGE: `restoreFocusAfterRebuild` refuses to act while focused; the
        // search must still be able to hop from one result to the next.
        let scene = makeScene()
        pushMesh(scene)
        scene.focusPeer("A")

        // ACT
        scene.focusPeer("B")

        // ASSERT
        #expect(scene.focusedPeerKey == "B")
    }

    @Test(.tags(.fast))
    func `focusPeer on an unfocusable target keeps the focus the user already had`() {
        // ARRANGE: focused on A
        let scene = makeScene()
        pushMesh(scene)
        scene.focusPeer("A")
        #expect(scene.focusedPeerKey == "A")

        // ACT: pick a peer that is not in the scene (it left the mesh between the
        // presence push and the click, so its results row was stale)
        scene.focusPeer("ghost-peer")

        // ASSERT: a failed switch must not destroy the session the user had.
        // Optimistically clearing first left focus gone with nothing replacing it.
        #expect(scene.focusedPeerKey == "A")
        #expect(scene.canFocusPeer("ghost-peer") == false)
    }

    @Test(.tags(.fast))
    func `a failed focus switch does not strand the pre-focus camera`() {
        // ARRANGE: the follow-on damage — `focusPeer` re-armed preFocusCamera* before
        // a failed enterFocusMode, and enterFocusMode only captures when it is nil,
        // so the NEXT session exited to a stale camera.
        let scene = makeScene()
        pushMesh(scene)
        scene.focusPeer("A")
        scene.focusPeer("ghost-peer") // fails
        scene.exitFocusMode()

        // ACT: a fresh, unrelated focus session
        scene.focusPeer("B")

        // ASSERT: it is a real session, entered from a clean state
        #expect(scene.focusedPeerKey == "B")
        scene.exitFocusMode()
        #expect(scene.focusedPeerKey == nil)
    }

    @Test(.tags(.fast))
    func `The local peer is never focusable from search`() {
        // ARRANGE
        let scene = makeScene()
        pushMesh(scene)

        // ACT
        scene.focusPeer("local")

        // ASSERT
        #expect(scene.focusedPeerKey == nil)
    }
}

// MARK: - View-model search routing

@Suite("PresenceViewerSK.ViewModel search")
@MainActor
final class PresenceViewerSearchViewModelTests {
    private var skView: SKView?

    private func makeScene() -> PresenceNetworkScene {
        let scene = PresenceNetworkScene()
        scene.size = CGSize(width: 1000, height: 800)
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 1000, height: 800))
        view.presentScene(scene)
        skView = view
        scene.showDirectConnectedOnly = false
        scene.updatePresenceGraph(
            localPeer: MockPeer(peerKey: "local", deviceName: "Local", connections: [
                MockConnection(type: .p2pWiFi, id: "l-A", peerKeyString1: "local", peerKeyString2: "A")
            ]),
            remotePeers: [
                MockPeer(peerKey: "A", deviceName: "Alpha", connections: [
                    MockConnection(type: .p2pWiFi, id: "l-A", peerKeyString1: "local", peerKeyString2: "A")
                ])
            ]
        )
        return scene
    }

    @Test(.tags(.fast))
    func `Whitespace does not make the search active`() {
        // ARRANGE
        let viewModel = PresenceViewerSK.ViewModel()

        // ACT / ASSERT
        viewModel.searchQuery = "   "
        #expect(viewModel.searchIsActive == false)
        viewModel.searchQuery = "alpha"
        #expect(viewModel.searchIsActive == true)
    }

    @Test(.tags(.fast))
    func `Escape unwinds the card first, then the query — focus survives both`() {
        // ARRANGE
        let viewModel = PresenceViewerSK.ViewModel()
        viewModel.searchQuery = "alpha"
        viewModel.detailPeerKey = "A"
        viewModel.focusedPeerKey = "A"

        // ACT: first Escape
        let firstHandled = viewModel.handleEscape()

        // ASSERT: card closed, query untouched
        #expect(firstHandled)
        #expect(viewModel.detailPeerKey == nil)
        #expect(viewModel.searchQuery == "alpha")

        // ACT: second Escape
        let secondHandled = viewModel.handleEscape()

        // ASSERT: query cleared, focus never touched by either step
        #expect(secondHandled)
        #expect(viewModel.searchQuery.isEmpty)
        #expect(viewModel.focusedPeerKey == "A")

        // ACT: nothing left to unwind
        #expect(viewModel.handleEscape() == false)
    }

    @Test(.tags(.fast))
    func `Picking a result while Direct is ON flips Direct off`() {
        // ARRANGE
        let viewModel = PresenceViewerSK.ViewModel()
        viewModel.scene = makeScene()
        viewModel.showDirectConnectedOnly = true

        // ACT: the peer may not even be in the scene yet — that is the point
        viewModel.focusSearchResult("A")

        // ASSERT: the focus itself is deferred to the rebuilt full-mesh push
        #expect(viewModel.showDirectConnectedOnly == false)
    }

    @Test(.tags(.fast))
    func `Picking a result in the full mesh focuses it and closes any open card`() {
        // ARRANGE
        let viewModel = PresenceViewerSK.ViewModel()
        let scene = makeScene()
        viewModel.scene = scene
        // Focus only exists in the full mesh; the VM defaults to Direct ON.
        viewModel.showDirectConnectedOnly = false
        viewModel.detailPeerKey = "local"
        scene.hasOpenDetailCard = true

        // ACT
        viewModel.focusSearchResult("A")

        // ASSERT
        #expect(scene.focusedPeerKey == "A")
        #expect(viewModel.detailPeerKey == nil)
        #expect(scene.hasOpenDetailCard == false)
    }

    @Test(.tags(.fast))
    func `Picking the local device does nothing`() {
        // ARRANGE
        let viewModel = PresenceViewerSK.ViewModel()
        let scene = makeScene()
        viewModel.scene = scene
        viewModel.showDirectConnectedOnly = false

        // ACT
        viewModel.focusSearchResult("local")

        // ASSERT
        #expect(scene.focusedPeerKey == nil)
    }

    @Test(.tags(.fast))
    func `clearSearch empties the box`() {
        // ARRANGE
        let viewModel = PresenceViewerSK.ViewModel()
        viewModel.searchQuery = "alpha"

        // ACT
        viewModel.clearSearch()

        // ASSERT
        #expect(viewModel.searchQuery.isEmpty)
        #expect(viewModel.searchIsActive == false)
    }
}
