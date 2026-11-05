import XCTest
@testable import MonitorCore

final class ProtocolTests: XCTestCase {
    let token = String(repeating: "a", count: 64)
    private func request(_ head: String, _ body: String = "") -> HTTPRequest.ParseResult {
        HTTPRequest.parse(Data((head + "\r\n\r\n" + body).utf8))
    }

    func testPartialBodyWaitsForMoreData() {
        guard case .incomplete = request("POST /v1/activity HTTP/1.1\r\nContent-Length: 5", "{") else { return XCTFail() }
        guard case .complete(let value) = request("POST /v1/activity HTTP/1.1\r\nContent-Length: 2", "{}") else { return XCTFail() }
        XCTAssertEqual(value.body, Data("{}".utf8))
    }

    func testRejectsAmbiguousOversizedAndPipelinedRequests() {
        for head in [
            "POST / HTTP/1.1\r\nContent-Length: 65537",
            "POST / HTTP/1.1\r\nContent-Length: -1",
            "POST / HTTP/1.1\r\nContent-Length: 0\r\nContent-Length: 1",
            "POST / HTTP/1.1\r\nTransfer-Encoding: chunked"
        ] {
            guard case .invalid = request(head) else { XCTFail(head); continue }
        }
        guard case .invalid = request("GET / HTTP/1.1", "unexpected") else { return XCTFail() }
        guard case .invalid = HTTPRequest.parse(Data(repeating: 65, count: 8193)) else { return XCTFail() }
    }

    func testPagePayloadMayExceedOldDomainOnlyLimit() {
        let body = String(repeating: "x", count: 10000)
        guard case .complete(let parsed) = request("POST /v1/activity HTTP/1.1\r\nContent-Length: 10000", body) else { return XCTFail() }
        XCTAssertEqual(parsed.body.count, 10000)
    }

    func testRequiresTokenAndLoopbackHostAndRejectsWebsiteOrigin() {
        let basic = "POST /v1/activity HTTP/1.1\r\nHost: 127.0.0.1:47821"
        guard case .complete(let missing) = request(basic) else { return XCTFail() }
        XCTAssertFalse(missing.isAuthorized(token: token))
        guard case .complete(let valid) = request(basic + "\r\nAuthorization: Bearer \(token)") else { return XCTFail() }
        XCTAssertTrue(valid.isAuthorized(token: token))
        XCTAssertFalse(valid.isAuthorized(token: String(repeating: "b", count: 64)))
        guard case .complete(let website) = request(basic + "\r\nAuthorization: Bearer \(token)\r\nOrigin: https://example.com") else { return XCTFail() }
        XCTAssertFalse(website.isAuthorized(token: token))
        guard case .complete(let rebinding) = request("GET /v1/status HTTP/1.1\r\nHost: attacker.example:47821\r\nAuthorization: Bearer \(token)") else { return XCTFail() }
        XCTAssertFalse(rebinding.isAuthorized(token: token))
    }

    func testOnlyValidChromeExtensionOriginsAreAccepted() {
        let origin = "chrome-extension://" + String(repeating: "a", count: 32)
        guard case .complete(let valid) = request("GET /v1/status HTTP/1.1\r\nHost: 127.0.0.1:47821\r\nOrigin: \(origin)\r\nAuthorization: Bearer \(token)") else { return XCTFail() }
        XCTAssertEqual(valid.extensionOrigin, origin)
        XCTAssertTrue(valid.isAuthorized(token: token))
        guard case .complete(let invalid) = request("GET / HTTP/1.1\r\nOrigin: chrome-extension://evil.example") else { return XCTFail() }
        XCTAssertNil(invalid.extensionOrigin)
    }
}
