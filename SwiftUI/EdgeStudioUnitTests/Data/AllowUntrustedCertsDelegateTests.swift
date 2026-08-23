import Foundation
import Testing
@testable import Ditto_Edge_Studio

/// Unit tests for the host-scoped untrusted-certificate bypass. The Bearer
/// `httpApiKey` is sent over connections using this delegate, so the bypass
/// must apply ONLY to the configured database's HTTP API host — accepting any
/// certificate on an arbitrary host would expose the key to a MITM.
@Suite("AllowUntrustedCertsDelegate — host-scoped trust bypass")
struct AllowUntrustedCertsDelegateTests {
    @Test(.tags(.fast))
    func `accepts server trust for the configured host`() {
        // ARRANGE / ACT / ASSERT
        #expect(
            AllowUntrustedCertsDelegate.shouldAcceptServerTrust(
                challengeHost: "db.example.com",
                expectedHost: "db.example.com"
            ) == true
        )
    }

    @Test(.tags(.fast))
    func `rejects server trust for any other host`() {
        // ARRANGE / ACT / ASSERT — a MITM presenting a cert on another host
        // must fall back to default (validating) handling.
        #expect(
            AllowUntrustedCertsDelegate.shouldAcceptServerTrust(
                challengeHost: "evil.example.com",
                expectedHost: "db.example.com"
            ) == false
        )
    }

    @Test(.tags(.fast))
    func `host comparison is case-insensitive`() {
        // ARRANGE / ACT / ASSERT — DNS names are case-insensitive; URLSession
        // and URL parsing may normalize differently.
        #expect(
            AllowUntrustedCertsDelegate.shouldAcceptServerTrust(
                challengeHost: "DB.Example.COM",
                expectedHost: "db.example.com"
            ) == true
        )
    }

    @Test(.tags(.fast))
    func `empty expected host accepts nothing`() {
        // ARRANGE / ACT / ASSERT — an unscoped delegate must never bypass.
        #expect(
            AllowUntrustedCertsDelegate.shouldAcceptServerTrust(
                challengeHost: "db.example.com",
                expectedHost: ""
            ) == false
        )
    }

    @Test(.tags(.fast))
    func `init normalizes the expected host to lowercase`() {
        // ARRANGE / ACT
        let delegate = AllowUntrustedCertsDelegate(expectedHost: "DB.Example.COM")

        // ASSERT
        #expect(delegate.expectedHost == "db.example.com")
    }
}

/// Unit tests for `DittoManager.expectedHost(fromHttpApiUrl:)` — the pure
/// decision that scopes the bypass to the selected database's HTTP API host.
@Suite("DittoManager.expectedHost — HTTP API URL parsing")
struct DittoManagerExpectedHostTests {
    @Test(.tags(.fast))
    func `bare host parses`() {
        #expect(DittoManager.expectedHost(fromHttpApiUrl: "db.example.com") == "db.example.com")
    }

    @Test(.tags(.fast))
    func `host with port drops the port`() {
        // URLAuthenticationChallenge.protectionSpace.host carries no port, so
        // the expected value must not either.
        #expect(DittoManager.expectedHost(fromHttpApiUrl: "db.example.com:8443") == "db.example.com")
    }

    @Test(.tags(.fast))
    func `full URL is tolerated and lowercased`() {
        #expect(
            DittoManager.expectedHost(fromHttpApiUrl: "https://DB.Example.COM:8443/api") == "db.example.com"
        )
    }

    @Test(.tags(.fast))
    func `empty or unparseable input yields nil`() {
        // nil → getCachedUntrustedSession falls back to the validating shared
        // session rather than an unscoped bypass.
        #expect(DittoManager.expectedHost(fromHttpApiUrl: "") == nil)
    }
}
