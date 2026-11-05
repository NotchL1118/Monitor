import Foundation

public struct HTTPRequest {
    public let method: String
    public let path: String
    public let headers: [String: String]
    public let body: Data

    public enum ParseResult {
        case incomplete
        case invalid
        case complete(HTTPRequest)
    }

    public static func parse(_ data: Data) -> ParseResult {
        guard data.count <= 73728 else { return .invalid }
        guard let delimiter = data.range(of: Data("\r\n\r\n".utf8)) else { return data.count > 8192 ? .invalid : .incomplete }
        guard delimiter.lowerBound <= 8192 else { return .invalid }
        guard let head = String(data: data[..<delimiter.lowerBound], encoding: .utf8) else { return .invalid }
        let lines = head.components(separatedBy: "\r\n")
        let first = (lines.first ?? "").split(separator: " ")
        guard first.count == 3, first[2] == "HTTP/1.1" else { return .invalid }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { return .invalid }
            let key = line[..<colon].lowercased()
            guard !key.isEmpty, headers[key] == nil, !key.contains(" ") else { return .invalid }
            headers[key] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        guard headers["transfer-encoding"] == nil else { return .invalid }
        let length: Int
        if let raw = headers["content-length"] {
            guard !raw.isEmpty, raw.utf8.allSatisfy({ (48...57).contains($0) }),
                  let value = Int(raw), (0...65536).contains(value) else { return .invalid }
            length = value
        } else { length = 0 }
        let body = data[delimiter.upperBound...]
        guard body.count >= length else { return .incomplete }
        guard body.count == length else { return .invalid }
        return .complete(HTTPRequest(method: String(first[0]), path: String(first[1]), headers: headers, body: Data(body)))
    }

    public var extensionOrigin: String? {
        guard let origin = headers["origin"], origin.hasPrefix("chrome-extension://") else { return nil }
        let id = origin.dropFirst("chrome-extension://".count)
        guard id.count == 32, id.utf8.allSatisfy({ (97...112).contains($0) }) else { return nil }
        return origin
    }

    public func isAuthorized(token: String) -> Bool {
        guard headers["host"] == "127.0.0.1:47821",
              headers["origin"] == nil || extensionOrigin != nil,
              let auth = headers["authorization"] else { return false }
        let expected = Array("Bearer \(token)".utf8), actual = Array(auth.utf8)
        guard actual.count == expected.count else { return false }
        return zip(actual, expected).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }
}
