import XCTest
@testable import MonitorCore

final class UsageShareTests: XCTestCase {
    private func summary(_ key: String, _ seconds: Double) -> UsageSummary {
        UsageSummary(key: key, name: key, seconds: seconds)
    }

    func testKeepsTopFiveAndFoldsTheRestIntoOther() {
        let items = [summary("a", 100), summary("b", 50), summary("c", 20), summary("d", 10),
                     summary("e", 8), summary("f", 7), summary("g", 5)]
        let shares = UsageShare.make(items)
        XCTAssertEqual(shares.map(\.key), ["a", "b", "c", "d", "e", UsageShare.otherKey])
        XCTAssertEqual(shares.map(\.slot), [0, 1, 2, 3, 4, nil])
        XCTAssertEqual(shares.last?.seconds, 12)
        XCTAssertEqual(shares.last?.foldedCount, 2)
        XCTAssertEqual(shares.last?.name, "其他 2 项")
        XCTAssertEqual(shares.last?.end ?? 0, 1, accuracy: 1e-9)
        XCTAssertEqual(shares.reduce(0) { $0 + $1.fraction }, 1, accuracy: 1e-9)
    }

    func testSortsByDurationAndSkipsEmptyItems() {
        let shares = UsageShare.make([summary("small", 10), summary("zero", 0), summary("big", 30)])
        XCTAssertEqual(shares.map(\.key), ["big", "small"])
        XCTAssertEqual(shares[0].fraction, 0.75, accuracy: 1e-9)
        XCTAssertEqual(shares[1].start, 0.75, accuracy: 1e-9)
        XCTAssertTrue(UsageShare.make([summary("zero", 0)]).isEmpty)
        XCTAssertTrue(UsageShare.make([]).isEmpty)
    }

    func testFindsSectorAtClockwisePosition() {
        let shares = UsageShare.make([summary("a", 75), summary("b", 25)])
        XCTAssertEqual(UsageShare.share(at: 0.1, in: shares)?.key, "a")
        XCTAssertEqual(UsageShare.share(at: 0.8, in: shares)?.key, "b")
        XCTAssertEqual(UsageShare.share(at: 1.1, in: shares)?.key, "a")
        XCTAssertEqual(UsageShare.share(at: -0.1, in: shares)?.key, "b")
    }

    func testPercentText() {
        XCTAssertEqual(UsageShare.percentText(0.714), "71%")
        XCTAssertEqual(UsageShare.percentText(0.004), "<1%")
        XCTAssertEqual(UsageShare.percentText(0), "0%")
    }
}
