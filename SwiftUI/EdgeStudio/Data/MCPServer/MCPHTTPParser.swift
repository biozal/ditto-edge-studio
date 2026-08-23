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

        // Chunked transfer encoding has no Content-Length — decode the chunks.
        if headers["transfer-encoding"]?.lowercased().contains("chunked") == true {
            guard let decoded = decodeChunkedBody(bodyData) else { return nil }
            return HTTPRequest(
                method: method,
                path: path,
                queryParams: queryParams,
                headers: headers,
                body: decoded
            )
        }

        // Wait for full body before returning a request
        let contentLength = Int(headers["content-length"] ?? "0") ?? 0
        if contentLength > 0, bodyData.count < contentLength {
            return nil
        }

        return HTTPRequest(
            method: method,
            path: path,
            queryParams: queryParams,
            headers: headers,
            body: contentLength > 0 ? Data(bodyData.prefix(contentLength)) : Data()
        )
    }

    /// Decodes an HTTP/1.1 chunked body. Returns `nil` while the terminating
    /// zero-length chunk (or any chunk data) has not fully arrived yet.
    private static func decodeChunkedBody(_ data: Data) -> Data? {
        let crlf = Data("\r\n".utf8)
        var decoded = Data()
        var offset = data.startIndex

        while true {
            // Chunk header: hex size (optional ";ext" suffix) terminated by CRLF
            guard let lineEnd = data.range(of: crlf, in: offset ..< data.endIndex),
                  let sizeLine = String(data: data[offset ..< lineEnd.lowerBound], encoding: .utf8),
                  let size = Int(sizeLine.split(separator: ";").first.map(String.init) ?? "", radix: 16) else { return nil }

            offset = lineEnd.upperBound

            // Zero-size chunk terminates the body; wait for the final CRLF
            // (trailers, if any, are ignored).
            if size == 0 {
                guard data.range(of: crlf, in: offset ..< data.endIndex) != nil else { return nil }
                return decoded
            }

            // Compare as a subtraction: a hostile chunk-size line (e.g.
            // "7FFFFFFFFFFFFFFF" → Int.max) would trap on overflow in
            // `size + crlf.count`. A negative rhs simply fails the guard —
            // the body is treated as incomplete, same as any short read.
            let remaining = data.distance(from: offset, to: data.endIndex)
            guard size <= remaining - crlf.count else { return nil }
            decoded.append(data[offset ..< data.index(offset, offsetBy: size)])
            offset = data.index(offset, offsetBy: size + crlf.count)
        }
    }
}
#endif
