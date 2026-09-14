import DittoSwift
import Foundation
import Testing
@testable import Ditto_Edge_Studio

@Suite("LogConnectionTracker Tests")
struct LogConnectionTrackerTests {
    // MARK: - Helpers

    private func entry(
        _ message: String,
        at seconds: TimeInterval,
        rawLine: String? = nil,
        level: DittoLogLevel = .info
    ) -> LogEntry {
        LogEntry(
            timestamp: Date(timeIntervalSince1970: seconds),
            level: level,
            message: message,
            component: .transport,
            source: .dittoSDK,
            rawLine: rawLine ?? message
        )
    }

    /// The flattened encoding the live `DittoLogger.setCustomLogCallback`
    /// stream delivers.
    private func flatLine(
        _ verb: String,
        remote: String = "pkRemoteA",
        role: String = "Client",
        transport: String = "Awdl",
        connectionId: String = "9"
    ) -> String {
        "physical connection \(verb) remote=\(remote) role=\(role) "
            + "transport_type=\(transport) connection_id=\(connectionId)"
    }

    /// The JSON Lines encoding the SDK writes into `ditto_logs/*.log`, which
    /// `LogFileParser` puts on `LogEntry.rawLine` while `message` keeps only
    /// the bare verb.
    private func jsonEntry(
        _ verb: String,
        at seconds: TimeInterval,
        remote: String = "pkRemoteA",
        role: String = "Client",
        transport: String = "Awdl",
        connectionId: String = "9"
    ) -> LogEntry {
        let message = "physical connection \(verb)"
        let raw = """
        {"timestamp":"2026-09-05T20:44:02.068216Z","level":"INFO","message":"\(message)",\
        "remote":"\(remote)","role":"\(role)","transport_type":"\(transport)",\
        "connection_id":"\(connectionId)","target":"ditto_multiplexer::connection"}
        """
        return entry(message, at: seconds, rawLine: raw)
    }

    // MARK: - Extraction: flattened (live) encoding

    @Test("Extracts fields from the flattened live-callback encoding")
    func extractsFlattenedEncoding() {
        // Arrange
        let logEntry = entry(flatLine("started", transport: "Websocket"), at: 100)

        // Act
        let event = LogConnectionEvent.extract(from: logEntry)

        // Assert
        #expect(event?.kind == .started)
        #expect(event?.remotePeer == "pkRemoteA")
        #expect(event?.role == "Client")
        #expect(event?.transport == "Websocket")
        #expect(event?.connectionId == "9")
    }

    // MARK: - Extraction: JSON Lines (historical) encoding

    @Test("Extracts fields from the JSON Lines file encoding")
    func extractsJSONEncoding() {
        // Arrange — the message body carries no key=value pairs at all here,
        // so a regex-only extractor would report every field as "unknown".
        let logEntry = jsonEntry("started", at: 100, transport: "Tcp", connectionId: "11")

        // Act
        let event = LogConnectionEvent.extract(from: logEntry)

        // Assert
        #expect(event?.kind == .started)
        #expect(event?.remotePeer == "pkRemoteA")
        #expect(event?.transport == "Tcp")
        #expect(event?.connectionId == "11")
    }

    @Test("Non-connection lines produce no event")
    func ignoresUnrelatedLines() {
        #expect(LogConnectionEvent.extract(from: entry("Notifying a database change", at: 1)) == nil)
        #expect(LogConnectionEvent.extract(from: entry("Mesh chooser requesting connection", at: 1)) == nil)
    }

    @Test("The extended-info duplicate is ignored so closes are not double counted")
    func ignoresExtendedInfoDuplicate() {
        // The SDK emits a DEBUG "physical connection ended (extended info)"
        // record alongside the INFO one; counting both would close each session
        // twice and inflate the durations histogram.
        let logEntry = entry("physical connection ended (extended info)", at: 5, level: .debug)
        #expect(LogConnectionEvent.extract(from: logEntry) == nil)
    }

    @Test("'shutting down' is not treated as a lifecycle edge")
    func ignoresShuttingDown() {
        #expect(LogConnectionEvent.extract(from: entry("Physical connection shutting down", at: 5)) == nil)
    }

    // MARK: - Pairing

    @Test("Pairs start and end into a closed session with a duration")
    func pairsStartAndEnd() {
        // Arrange
        var tracker = LogConnectionTracker()

        // Act
        tracker.consume(entry(flatLine("started"), at: 100))
        tracker.consume(entry(flatLine("ended"), at: 130))

        // Assert
        #expect(tracker.closedSessions.count == 1)
        #expect(tracker.closedSessions.first?.duration == 30)
        #expect(tracker.closedSessions.first?.transport == "Awdl")
        #expect(tracker.unmatchedEnds == 0)
    }

    @Test("An end with no matching start is counted, not paired")
    func countsUnmatchedEnd() {
        // Arrange
        var tracker = LogConnectionTracker()

        // Act
        tracker.consume(entry(flatLine("ended"), at: 130))

        // Assert
        #expect(tracker.closedSessions.isEmpty)
        #expect(tracker.unmatchedEnds == 1)
    }

    @Test("A start with no end stays open and has no duration")
    func openSessionHasNoDuration() {
        // Arrange
        var tracker = LogConnectionTracker()

        // Act
        tracker.consume(entry(flatLine("started"), at: 100))

        // Assert
        #expect(tracker.closedSessions.isEmpty)
        #expect(tracker.sessions.count == 1)
        #expect(tracker.sessions.first?.duration == nil)
    }

    @Test("A reused connection id pairs with the most recent open session")
    func reusedConnectionIdPairsWithNewest() {
        // Arrange — the SDK reuses connection ids, so first-match pairing would
        // close the older session and report the wrong duration for both.
        var tracker = LogConnectionTracker()

        // Act
        tracker.consume(entry(flatLine("started", connectionId: "8"), at: 100))
        tracker.consume(entry(flatLine("started", connectionId: "8"), at: 200))
        tracker.consume(entry(flatLine("ended", connectionId: "8"), at: 210))

        // Assert
        #expect(tracker.closedSessions.count == 1)
        #expect(tracker.closedSessions.first?.duration == 10)
    }

    @Test("Distinct connection ids do not cross-pair")
    func distinctIdsDoNotCrossPair() {
        // Arrange
        var tracker = LogConnectionTracker()

        // Act
        tracker.consume(entry(flatLine("started", connectionId: "1"), at: 100))
        tracker.consume(entry(flatLine("started", connectionId: "2"), at: 110))
        tracker.consume(entry(flatLine("ended", connectionId: "1"), at: 150))

        // Assert
        #expect(tracker.closedSessions.count == 1)
        #expect(tracker.closedSessions.first?.connectionId == "1")
        #expect(tracker.closedSessions.first?.duration == 50)
        #expect(tracker.sessions.count == 2) // one closed, one still open
    }

    @Test("Both encodings pair with each other")
    func encodingsInteroperate() {
        // Arrange — a panel opened mid-session reads historical JSON lines and
        // then live flattened ones; a session must be able to span the two.
        var tracker = LogConnectionTracker()

        // Act
        tracker.consume(jsonEntry("started", at: 100, connectionId: "7"))
        tracker.consume(entry(flatLine("ended", connectionId: "7"), at: 145))

        // Assert
        #expect(tracker.closedSessions.count == 1)
        #expect(tracker.closedSessions.first?.duration == 45)
    }

    // MARK: - Reinit

    @Test("A reinit closes every open session at that instant")
    func reinitClosesOpenSessions() {
        // Arrange
        var tracker = LogConnectionTracker()
        tracker.consume(entry(flatLine("started", connectionId: "1"), at: 100))
        tracker.consume(entry(flatLine("started", connectionId: "2"), at: 110))

        // Act
        tracker.consume(entry("ditto_init restarting", at: 200))

        // Assert
        #expect(tracker.closedSessions.count == 2)
        #expect(tracker.reinits == [Date(timeIntervalSince1970: 200)])
        #expect(tracker.closedSessions.allSatisfy { $0.end == Date(timeIntervalSince1970: 200) })
    }

    @Test("ditto_init inside a path value is not a reinit")
    func pathMentionOfDittoInitIsNotAReinit() {
        // Arrange — in the JSON encoding `ditto_init` appears inside `path`
        // values of unrelated records (19 such lines in one 3.5k-line capture).
        // Matching the whole raw line would close every open session on each.
        var tracker = LogConnectionTracker()
        tracker.consume(entry(flatLine("started"), at: 100))
        let raw = """
        {"timestamp":"2026-09-05T20:31:14.181952Z","level":"DEBUG",\
        "message":"removing update file","path":"ditto_init/inbound_45814",\
        "target":"ditto_sync_docs::documents_peer"}
        """

        // Act
        tracker.consume(entry("removing update file", at: 150, rawLine: raw, level: .debug))

        // Assert
        #expect(tracker.reinits.isEmpty)
        #expect(tracker.closedSessions.isEmpty)
    }

    // MARK: - Reset

    @Test("reset clears every array so Clear cannot resurrect old sessions")
    func resetClearsEverything() {
        // Arrange
        var tracker = LogConnectionTracker()
        tracker.consume(entry(flatLine("started"), at: 100))
        tracker.consume(entry(flatLine("ended"), at: 130))
        tracker.consume(entry("ditto_init", at: 140))
        tracker.consume(entry(flatLine("ended", connectionId: "99"), at: 150))

        // Act
        tracker.reset()

        // Assert
        #expect(tracker.sessions.isEmpty)
        #expect(tracker.closedSessions.isEmpty)
        #expect(tracker.reinits.isEmpty)
        #expect(tracker.unmatchedEnds == 0)
    }

    // MARK: - Bounds

    @Test("Open sessions are capped so an unterminated start cannot leak")
    func openSessionsAreCapped() {
        // Arrange — a `started` whose `ended` never arrives (killed process,
        // truncated log) would otherwise grow this array without limit.
        var tracker = LogConnectionTracker()
        let overflow = LogConnectionTracker.sessionHistoryCap * 2 + 10

        // Act
        for index in 0 ..< overflow {
            tracker.consume(entry(flatLine("started", connectionId: "\(index)"), at: TimeInterval(index)))
        }

        // Assert
        #expect(tracker.sessions.count <= LogConnectionTracker.sessionHistoryCap * 2)
    }

    // MARK: - Batch

    @Test("track builds a tracker from a whole buffer in order")
    func trackProcessesWholeBuffer() {
        // Arrange
        let entries = [
            entry(flatLine("started", connectionId: "1"), at: 10),
            entry("unrelated chatter", at: 12),
            entry(flatLine("ended", connectionId: "1"), at: 14)
        ]

        // Act
        let tracker = LogConnectionTracker.track(entries)

        // Assert
        #expect(tracker.closedSessions.count == 1)
        #expect(tracker.closedSessions.first?.duration == 4)
    }
}
