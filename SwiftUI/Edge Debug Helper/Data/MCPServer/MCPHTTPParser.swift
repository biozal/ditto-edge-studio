#if os(macOS)
import Foundation

// MARK: - MCP HTTP Parser

/// Parses raw TCP byte stream data into HTTPRequest values.
///
/// Extracted from MCPHTTPConnectionHandler so the parsing logic
/// can be unit tested without a live NWConnection.
enum MCPHTTPParser {
    /// Attempts to parse a complete HTTP/1.1 request from accumulated TCP data.
    ///
    /// Returns `nil` if the data does not yet contain a complete request —
    /// i.e. the `\r\n\r\n` header terminator hasn't arrived yet, or the body
    /// is still being received according to the `Content-Length` header.
    static func tryParse(_ data: Data) -> HTTPRequest? {
        guard let headerEndRange = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }

        let headerData = data[..<headerEndRange.lowerBound]
        let bodyData = data[headerEndRange.upperBound...]

        guard let headerString = String(data: headerData, encoding: .utf8) else { return nil }

        let lines = headerString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }

        let parts = requestLine.components(separatedBy: " ")
        guard parts.count >= 2 else { return nil }

        let method = parts[0]
        let rawPath = parts[1]

        // Split path from query string
        let pathParts = rawPath.components(separatedBy: "?")
        let path = pathParts[0]
        var queryParams: [String: String] = [:]
        if pathParts.count > 1 {
            for pair in pathParts[1].components(separatedBy: "&") {
                let kv = pair.components(separatedBy: "=")
                if kv.count == 2 {
                    let key = kv[0].removingPercentEncoding ?? kv[0]
                    let val = kv[1].removingPercentEncoding ?? kv[1]
                    queryParams[key] = val
                }
            }
        }

        // Parse headers (lower-cased keys per HTTP spec)
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            if let colonIdx = line.firstIndex(of: ":") {
                let key = String(line[..<colonIdx]).trimmingCharacters(in: .whitespaces).lowercased()
                let val = String(line[line.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)
                headers[key] = val
            }
        }

        // Wait for full body before returning a request
        let contentLength = Int(headers["content-length"] ?? "0") ?? 0
        if contentLength > 0, bodyData.count < contentLength { return nil }

        return HTTPRequest(
            method: method,
            path: path,
            queryParams: queryParams,
            headers: headers,
            body: contentLength > 0 ? Data(bodyData.prefix(contentLength)) : Data()
        )
    }
}
#endif
