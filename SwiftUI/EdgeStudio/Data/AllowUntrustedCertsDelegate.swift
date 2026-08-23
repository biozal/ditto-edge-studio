import Foundation

/// URLSession delegate that bypasses server-trust validation **for one
/// configured host only**. Databases opt in individually via
/// `allowUntrustedCerts`, and the bypass must never extend past that
/// database's HTTP API host: the Bearer `httpApiKey` rides on these
/// connections, so accepting any presented certificate on an arbitrary host
/// would hand the key to a MITM.
final class AllowUntrustedCertsDelegate: NSObject, URLSessionDelegate {
    /// The host the trust bypass is scoped to (normalized to lowercase).
    let expectedHost: String

    init(expectedHost: String) {
        self.expectedHost = expectedHost.lowercased()
    }

    /// Pure accept/reject decision, extracted for unit tests. Only a
    /// server-trust challenge for exactly the configured host is accepted;
    /// everything else falls back to default (validating) handling. An empty
    /// `expectedHost` accepts nothing.
    static func shouldAcceptServerTrust(
        challengeHost: String,
        expectedHost: String
    ) -> Bool {
        !expectedHost.isEmpty && challengeHost.lowercased() == expectedHost.lowercased()
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let serverTrust = challenge.protectionSpace.serverTrust,
           Self.shouldAcceptServerTrust(
               challengeHost: challenge.protectionSpace.host,
               expectedHost: expectedHost
           )
        {
            // Accept the server trust without validation — scoped to the configured host
            let credential = URLCredential(trust: serverTrust)
            completionHandler(.useCredential, credential)
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}
