import XCTest
@testable import MonitorCore

final class SessionMergerTests: XCTestCase {
    private let zero = Date(timeIntervalSince1970: 1_700_000_000)
    private var nextID: Int64 = 0

    private func slice(_ key: String, _ from: Double, _ to: Double) -> ActivitySlice {
        nextID += 1
        return ActivitySlice(id: nextID, kind: .application, key: key, name: key,
                             start: zero.addingTimeInterval(from), end: zero.addingTimeInterval(to))
    }

    func testBriefSwitchesAwayAreAbsorbedIntoOneBlock() {
        let merged = SessionMerger.merge([
            slice("chat", 0, 600), slice("wechat", 600, 601), slice("chat", 601, 900),
            slice("pixpin", 900, 903), slice("monitor", 903, 905), slice("chat", 905, 1500)
        ])
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].slice.key, "chat")
        XCTAssertEqual(merged[0].slice.seconds, 1500)
        XCTAssertEqual(merged[0].activeSeconds, 1494, accuracy: 0.001)
        XCTAssertEqual(merged[0].interruptions, 3)
        XCTAssertEqual(merged[0].slice.id, 1)
    }

    func testSwitchAtOrBeyondThresholdStaysSeparate() {
        let merged = SessionMerger.merge([slice("chat", 0, 100), slice("editor", 100, 130), slice("chat", 130, 200)])
        XCTAssertEqual(merged.map(\.slice.key), ["chat", "editor", "chat"])
        XCTAssertEqual(merged.map(\.interruptions), [0, 0, 0])
    }

    func testShortUnrecordedGapJoinsAndLongGapSplits() {
        let merged = SessionMerger.merge([slice("chat", 0, 100), slice("chat", 120, 200), slice("chat", 260, 300)])
        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged[0].slice.end, zero.addingTimeInterval(200))
        XCTAssertEqual(merged[0].interruptions, 1)
        XCTAssertEqual(merged[0].activeSeconds, 180, accuracy: 0.001)
    }

    func testContiguousSameAppIsNotAnInterruption() {
        let merged = SessionMerger.merge([slice("chat", 0, 100), slice("chat", 100, 200)])
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].interruptions, 0)
    }

    func testRealSwitchToShortLivedAppIsKept() {
        // A -> B (5 s) -> C: B is a genuine hand-off, not an interruption of anything.
        let merged = SessionMerger.merge([slice("a", 0, 100), slice("b", 100, 105), slice("c", 105, 400)])
        XCTAssertEqual(merged.map(\.slice.key), ["a", "b", "c"])
    }
}
