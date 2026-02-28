@testable import Ditto_Edge_Studio
import Testing

/// Tests for LogComponent classification via heuristic(from:) and from(target:).
@Suite("LogComponent Classification")
struct LogComponentTests {
    // MARK: - heuristic(from:) — transport prefix wins over late "query" substring

    @Test("add_ble_transport prefix → transport")
    func addBleTransportPrefix() {
        let msg = "add_ble_transport local_peer_id=abc123 remote_query_id=xyz"
        #expect(LogComponent.heuristic(from: msg) == .transport)
    }

    @Test("start_tcp_server prefix → transport even with 'select=all'")
    func startTcpServerPrefix() {
        let msg = "start_tcp_server port=4040 select=all"
        #expect(LogComponent.heuristic(from: msg) == .transport)
    }

    @Test("add_awdl_transport prefix → transport")
    func addAwdlTransportPrefix() {
        let msg = "add_awdl_transport interface=awdl0"
        #expect(LogComponent.heuristic(from: msg) == .transport)
    }

    @Test("tcp keyword → transport")
    func tcpKeyword() {
        let msg = "open tcp connection to peer"
        #expect(LogComponent.heuristic(from: msg) == .transport)
    }

    @Test("awdl keyword → transport")
    func awdlKeyword() {
        let msg = "awdl interface became active"
        #expect(LogComponent.heuristic(from: msg) == .transport)
    }

    @Test("transport prefix wins when 'query_executor' appears later")
    func transportPrefixWinsOverLateQuerySubstring() {
        let msg = "add_ble_transport session=s1 query_executor=qe2 status=connected"
        #expect(LogComponent.heuristic(from: msg) == .transport)
    }

    @Test("pure query message stays .query")
    func pureQueryMessage() {
        let msg = "parsing sql query SELECT * FROM users"
        #expect(LogComponent.heuristic(from: msg) == .query)
    }

    // MARK: - from(target:) — tcp and awdl patterns in target field

    @Test("from(target:) with tcp → transport")
    func fromTargetTcp() {
        let target = "transport::tcp_server"
        #expect(LogComponent.from(target: target) == .transport)
    }

    @Test("from(target:) with awdl → transport")
    func fromTargetAwdl() {
        let target = "transport::awdl"
        #expect(LogComponent.from(target: target) == .transport)
    }
}
