import DittoSwift
import Foundation

/// Bundle returned by `executeSelectedAppQueryWithProfile`. The Query
/// editor uses this when it needs both the user-facing rows AND the
/// execution-plan profile that Ditto attached via the `PROFILE` keyword.
///
/// Callers that don't care about profiling keep using
/// `executeSelectedAppQuery(query:) -> [String]` unchanged.
struct QueryExecutionResult {
    /// JSON-encoded result rows, matching what the legacy `[String]`
    /// return delivered.
    let items: [String]
    /// Parsed profile, or `nil` when:
    ///   - Collect Metrics is disabled, or
    ///   - the statement isn't a SELECT (PROFILE only supports SELECT), or
    ///   - the user typed `PROFILE` manually and we left the query alone, or
    ///   - the SDK returned something we couldn't parse as a profile envelope.
    let profile: QueryProfile?
}

actor QueryService {
    static let shared = QueryService()

    private let dittoManager = DittoManager.shared
    private let queryCounter = AppMetricsCounter(label: "edge_studio.queries.total")
    private let queryTimer = AppMetricsTimer(label: "edge_studio.query.latency_ms")

    private init() {}

    // MARK: Query Execution

    func executeSelectedAppQuery(query: String) async throws -> [String] {
        guard let ditto = await dittoManager.dittoSelectedApp else {
            // Distinct from an empty result set ("No results found") — the MCP
            // formatQueryResults special-cases this exact string.
            return ["No Ditto app selected"]
        }

        // Instrument: measure execution time
        let startDate = Date.now
        let results = try await ditto.store.execute(query: query)
        let elapsedMs = Date.now.timeIntervalSince(startDate) * 1000.0

        // Record metrics only when collection is enabled (reads UserDefaults synchronously)
        let isMetricsEnabled = UserDefaults.standard.bool(forKey: "metricsEnabled")
        if isMetricsEnabled {
            queryCounter.increment()
            queryTimer.recordMilliseconds(elapsedMs)
        }

        // Build result strings
        let resultStrings: [String]
        if results.items.isEmpty {
            if !results.mutatedDocumentIDs().isEmpty {
                var resultsStrings = results.mutatedDocumentIDs().compactMap {
                    "Document ID: \($0.stringValue)"
                }
                if let commitID = results.commitID {
                    resultsStrings.append("Commit ID: \(commitID)")
                } else {
                    resultsStrings.append("Commit ID: N/A")
                }
                resultStrings = resultsStrings
            } else {
                resultStrings = ["No results found"]
            }
        } else {
            let resultJsonStrings = results.items.compactMap { item -> String? in
                // Convert [String: Any?] to [String: Any] by removing nil values
                let cleanedValue = item.value.compactMapValues { $0 }
                do {
                    let data = try JSONSerialization.data(
                        withJSONObject: cleanedValue,
                        options: [
                            .prettyPrinted,
                            .fragmentsAllowed,
                            .sortedKeys,
                            .withoutEscapingSlashes
                        ]
                    )
                    return String(data: data, encoding: .utf8)
                } catch {
                    return nil
                }
            }
            resultStrings = resultJsonStrings.isEmpty ? ["No results found"] : resultJsonStrings
        }

        // Capture EXPLAIN + per-query metrics only when collection is enabled
        if isMetricsEnabled {
            let resultCount = results.items.count + results.mutatedDocumentIDs().count
            let explainOutput = await runExplain(ditto: ditto, query: query)
            await QueryMetricsRepository.shared.capture(
                dql: query,
                executionTimeMs: elapsedMs,
                resultCount: resultCount,
                explainOutput: explainOutput
            )
        }

        return resultStrings
    }

    /// Like `executeSelectedAppQuery(query:)` but also captures the
    /// execution-plan profile when:
    ///   1. Collect Metrics is enabled in Settings, AND
    ///   2. the statement starts with `SELECT` (PROFILE only supports
    ///      SELECT — see plans/dql-profile-feature.md), AND
    ///   3. the user hasn't already typed `PROFILE` themselves.
    ///
    /// When all three hold, the statement is prefixed with `PROFILE `
    /// before execution. Ditto appends an extra `~request_profile` item
    /// to the result set; we pop it off, parse it via
    /// `QueryProfileParser`, and return both pieces in
    /// `QueryExecutionResult`. The user-facing rows in `.items` look
    /// identical to what they'd see without profiling.
    ///
    /// When any condition fails, the query runs unmodified and
    /// `.profile` is nil — same wire behaviour as the legacy method.
    func executeSelectedAppQueryWithProfile(query: String) async throws -> QueryExecutionResult {
        guard let ditto = await dittoManager.dittoSelectedApp else {
            // Same sentinel as executeSelectedAppQuery — see note there.
            return QueryExecutionResult(items: ["No Ditto app selected"], profile: nil)
        }

        let isMetricsEnabled = UserDefaults.standard.bool(forKey: "metricsEnabled")
        let shouldProfile = isMetricsEnabled
            && Self.isSelectStatement(query)
            && !Self.alreadyHasProfilePrefix(query)
        let effectiveQuery = shouldProfile ? "PROFILE \(query)" : query

        // Instrument: measure execution time
        let startDate = Date.now
        let results = try await ditto.store.execute(query: effectiveQuery)
        let elapsedMs = Date.now.timeIntervalSince(startDate) * 1000.0

        // Record AppMetrics counters only when collection is enabled
        if isMetricsEnabled {
            queryCounter.increment()
            queryTimer.recordMilliseconds(elapsedMs)
        }

        // Separate the trailing `~request_profile` item (if profiling
        // was requested AND Ditto actually emitted one) from the
        // user-facing rows. Walk from the end so we don't iterate the
        // full result set when the profile sits where we expect it.
        var profile: QueryProfile?
        var userItems = results.items
        if shouldProfile, let lastIndex = userItems.indices.last {
            let lastValue = userItems[lastIndex].value.compactMapValues { $0 }
            if let parsed = QueryProfileParser.parseItem(lastValue) {
                profile = parsed
                userItems[lastIndex].dematerialize()
                userItems.removeLast()
            }
        }

        // Build result strings — same shape as executeSelectedAppQuery,
        // but reading from the (possibly trimmed) userItems.
        let resultStrings: [String]
        if userItems.isEmpty {
            if !results.mutatedDocumentIDs().isEmpty {
                var resultsStrings = results.mutatedDocumentIDs().compactMap {
                    "Document ID: \($0.stringValue)"
                }
                if let commitID = results.commitID {
                    resultsStrings.append("Commit ID: \(commitID)")
                } else {
                    resultsStrings.append("Commit ID: N/A")
                }
                resultStrings = resultsStrings
            } else {
                resultStrings = ["No results found"]
            }
        } else {
            let resultJsonStrings = userItems.compactMap { item -> String? in
                let cleanedValue = item.value.compactMapValues { $0 }
                do {
                    let data = try JSONSerialization.data(
                        withJSONObject: cleanedValue,
                        options: [
                            .prettyPrinted,
                            .fragmentsAllowed,
                            .sortedKeys,
                            .withoutEscapingSlashes
                        ]
                    )
                    return String(data: data, encoding: .utf8)
                } catch {
                    return nil
                }
            }
            resultStrings = resultJsonStrings.isEmpty ? ["No results found"] : resultJsonStrings
        }

        // Capture EXPLAIN + per-query metrics record only when collection
        // is enabled. Note we deliberately pass the ORIGINAL `query`
        // (without the PROFILE prefix) so EXPLAIN runs against the same
        // statement the user typed — EXPLAIN doesn't care about PROFILE
        // and prepending both would re-trigger profiling unnecessarily.
        if isMetricsEnabled {
            let resultCount = userItems.count + results.mutatedDocumentIDs().count
            let explainOutput = await runExplain(ditto: ditto, query: query)
            await QueryMetricsRepository.shared.capture(
                dql: query,
                executionTimeMs: elapsedMs,
                resultCount: resultCount,
                explainOutput: explainOutput
            )
        }

        return QueryExecutionResult(items: resultStrings, profile: profile)
    }

    /// Returns true iff `query`'s first non-whitespace word is `SELECT`.
    /// Used to gate the PROFILE prefix — Ditto's PROFILE keyword only
    /// supports SELECT (INSERT/UPDATE/DELETE/EVICT/ALTER would fail).
    /// Case-insensitive; matches both `"select"` and `"SELECT"`. The
    /// trailing word boundary check rejects `SELECTOR` / `SELECTED`.
    static func isSelectStatement(_ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let upper = trimmed.uppercased()
        let needle = "SELECT"
        guard upper.hasPrefix(needle) else { return false }
        // After "SELECT" we need whitespace or end-of-string. Anything
        // else (e.g. SELECTOR) is not a SELECT statement.
        let afterIndex = upper.index(upper.startIndex, offsetBy: needle.count)
        if afterIndex == upper.endIndex {
            return true
        }
        let next = upper[afterIndex]
        return next.isWhitespace || next.isNewline
    }

    /// Returns true iff the user has already typed `PROFILE` at the
    /// start of their statement. Prevents double-prepending — running
    /// `PROFILE PROFILE SELECT …` would be a syntax error.
    static func alreadyHasProfilePrefix(_ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let upper = trimmed.uppercased()
        let needle = "PROFILE"
        guard upper.hasPrefix(needle) else { return false }
        let afterIndex = upper.index(upper.startIndex, offsetBy: needle.count)
        if afterIndex == upper.endIndex {
            return true
        }
        let next = upper[afterIndex]
        return next.isWhitespace || next.isNewline
    }

    /// Sanitizes a user-entered `httpApiUrl` and composes it with an HTTP
    /// API path. Users sometimes paste the URL with a scheme (`http://host`)
    /// or a trailing slash; both would produce a malformed URL if
    /// interpolated directly, so strip them before composing. Shared by
    /// QueryService (`/api/v5/store/execute`) and AttachmentService
    /// (`/api/v4/attachments/…`).
    nonisolated static func makeHttpApiURL(httpApiUrl: String, path: String) -> String {
        var host = httpApiUrl.trimmingCharacters(in: .whitespaces)
        for scheme in ["https://", "http://"] where host.lowercased().hasPrefix(scheme) {
            host = String(host.dropFirst(scheme.count))
            break
        }
        while host.hasSuffix("/") {
            host.removeLast()
        }
        let normalizedPath = path.hasPrefix("/") ? path : "/\(path)"
        return "https://\(host)\(normalizedPath)"
    }

    /// Builds the HTTP API execute URL from a user-entered `httpApiUrl`.
    nonisolated static func makeHttpExecuteURL(httpApiUrl: String) -> String {
        makeHttpApiURL(httpApiUrl: httpApiUrl, path: "/api/v5/store/execute")
    }

    private func runExplain(ditto: Ditto, query: String) async -> String {
        // Guard against recursive EXPLAIN calls
        guard !query.trimmingCharacters(in: .whitespaces).uppercased().hasPrefix("EXPLAIN") else {
            return ""
        }
        do {
            let explainResults = try await ditto.store.execute(query: "EXPLAIN \(query)")
            if let firstItem = explainResults.items.first {
                let cleaned = firstItem.value.compactMapValues { $0 }
                let data = try JSONSerialization.data(
                    withJSONObject: cleaned,
                    options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
                )
                return String(data: data, encoding: .utf8) ?? "No explain output"
            }
            return "No explain output"
        } catch {
            return "EXPLAIN failed: \(error.localizedDescription)"
        }
    }

    func executeSelectedAppQueryHttp(query: String) async throws -> [String] {
        guard let appConfig = await dittoManager.dittoSelectedAppConfig else {
            return ["{'error': 'No Ditto SelectedApp available.  You should never see this message.'}"]
        }

        let urlString = Self.makeHttpExecuteURL(httpApiUrl: appConfig.httpApiUrl)
        let authorization = "Bearer \(appConfig.httpApiKey)"

        guard let url = URL(string: urlString) else {
            return ["{'error': 'Invalid URL string.'}"]
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(authorization, forHTTPHeaderField: "Authorization")

        // Create the request body with the query
        let requestBody = ["statement": query]
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response): (Data, URLResponse)

        if appConfig.allowUntrustedCerts {
            // Use cached URLSession that allows untrusted certificates
            let session = await dittoManager.getCachedUntrustedSession()
            (data, response) = try await session.data(for: request)
        } else {
            (data, response) = try await URLSession.shared.data(for: request)
        }

        guard let httpResponse = response as? HTTPURLResponse,
              (200 ... 299).contains(httpResponse.statusCode) else
        {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            return ["HTTP Error: \(errorBody)"]
        }

        // Parse the response data
        if let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let mutatedDocumentIDs = (jsonObject["mutatedDocumentIds"] as? [String]) {
                if !mutatedDocumentIDs.isEmpty {
                    var resultStrings = mutatedDocumentIDs.map { "Document ID: \($0)" }
                    if let commitId = jsonObject["commitId"] as? String {
                        resultStrings.append("Commit ID: \(commitId)")
                    }
                    return resultStrings
                }
            }

            if let results = jsonObject["items"] as? [[String: Any]] {
                // Convert each item to a JSON string
                var resultStrings = [String]()

                for item in results {
                    if let itemData = try? JSONSerialization.data(
                        withJSONObject: item,
                        options: [
                            .withoutEscapingSlashes,
                            .fragmentsAllowed,
                            .prettyPrinted,
                            .sortedKeys
                        ]
                    ),
                        let itemString = String(data: itemData, encoding: .utf8)
                    {
                        resultStrings.append(itemString)
                    }
                }

                return resultStrings.isEmpty ? ["No items found"] : resultStrings
            }
        }

        // If response format is different, return the whole thing as one item
        if let jsonString = String(data: data, encoding: .utf8) {
            return [jsonString]
        }
        return ["No results found"]
    }

    // MARK: Small Peer Info

    func fetchSmallPeerInfo() async throws -> [SmallPeerInfo] {
        let query = "SELECT * FROM __small_peer_info"
        let jsonResults = try await executeSelectedAppQueryHttp(query: query)

        let decoder = JSONDecoder()
        var peerInfos: [SmallPeerInfo] = []

        for jsonString in jsonResults {
            if let data = jsonString.data(using: .utf8) {
                do {
                    let peerInfo = try decoder.decode(SmallPeerInfo.self, from: data)
                    peerInfos.append(peerInfo)
                } catch {
                    // Skip items that fail to decode
                    continue
                }
            }
        }

        return peerInfos
    }
}

// MARK: - Protocol Conformance

extension QueryService: QueryServiceProtocol {}
