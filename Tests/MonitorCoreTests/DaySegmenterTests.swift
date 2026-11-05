import XCTest
@testable import MonitorCore

final class DaySegmenterTests: XCTestCase {
    private let origin = Date(timeIntervalSince1970: 1_800_000_000)
    private var nextID: Int64 = 0
    private func app(_ key: String, _ a: Double, _ b: Double) -> ActivitySlice {
        nextID += 1
        return ActivitySlice(id: nextID, kind: .application, key: key, name: key,
                             start: origin.addingTimeInterval(a * 60), end: origin.addingTimeInterval(b * 60))
    }
    /// Alternates `main` with brief `side` glances every `every` minutes over [a, b) minutes.
    private func work(_ main: String, _ a: Double, _ b: Double, side: String = "chat", every: Double = 6) -> [ActivitySlice] {
        var result: [ActivitySlice] = []
        var t = a
        while t < b {
            let end = min(b, t + every - 0.5)
            result.append(app(main, t, end))
            if end < b { result.append(app(side, end, min(b, end + 0.5))) }
            t = end + 0.5
        }
        return result
    }

    func testRunsJoinSameAppAcrossTinyGapsOnly() {
        let runs = DaySegmenter.runs([app("a", 0, 1), app("a", 1.02, 2), app("b", 2, 3), app("a", 3, 4)])
        XCTAssertEqual(runs.map(\.key), ["a", "b", "a"])
        XCTAssertEqual(runs[0].seconds, 120)
        XCTAssertEqual(runs[0].id, 1)
    }

    func testDistinctActivitiesBecomeSeparatePeriodsAndAbsenceIsExplicit() {
        let slices = work("editor", 0, 120) + work("browser", 120, 180, side: "mail") + work("editor", 240, 300)
        let blocks = DaySegmenter.blocks(applications: slices, origin: origin)
        let segments = blocks.compactMap(\.segment)
        XCTAssertEqual(segments.map { $0.apps[0].key }, ["editor", "browser", "editor"])
        XCTAssertEqual(blocks.count, 4)
        guard case .away(let away) = blocks[2] else { return XCTFail("expected an absence") }
        XCTAssertEqual(away.seconds, 3600, accuracy: 0.001)
        XCTAssertEqual(segments[0].focus, .focused)
        XCTAssertGreaterThan(segments[0].switches, 10)
        // Periods partition the recorded time exactly: nothing is lost or double counted.
        let raw = slices.reduce(0) { $0 + $1.seconds }
        XCTAssertEqual(segments.reduce(0) { $0 + $1.activeSeconds }, raw, accuracy: 0.001)
        XCTAssertEqual(segments.flatMap(\.runs).reduce(0) { $0 + $1.seconds }, raw, accuracy: 0.001)
    }

    func testShortPeriodsFoldIntoTheMoreSimilarNeighbour() {
        // A 6-minute burst of mail between two long editor stretches is not its own period.
        let slices = work("editor", 0, 60) + [app("mail", 60, 66)] + work("editor", 66, 120)
        let segments = DaySegmenter.blocks(applications: slices, origin: origin).compactMap(\.segment)
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].apps.map(\.key).first, "editor")
        XCTAssertEqual(segments[0].apps.first { $0.key == "mail" }?.seconds, 360)
    }

    func testBriefUseBetweenAbsencesFoldsIntoOneAbsence() {
        let slices = work("editor", 0, 60) + [app("chat", 90, 90.5)] + work("editor", 120, 180)
        let blocks = DaySegmenter.blocks(applications: slices, origin: origin)
        XCTAssertEqual(blocks.count, 3)
        guard case .away(let away) = blocks[1] else { return XCTFail("expected an absence") }
        XCTAssertEqual(away.briefSeconds, 30, accuracy: 0.001)
        XCTAssertEqual(away.start, slices[slices.count / 2 - 1].end)
    }

    func testFragmentedSwitchingIsLabelledAndWebsitesAreClipped() {
        var slices: [ActivitySlice] = []
        for i in 0..<60 { slices.append(app(["chat", "browser", "mail"][i % 3], Double(i) * 0.5, Double(i) * 0.5 + 0.5)) }
        let site = ActivitySlice(id: 999, kind: .website, key: "example.com", name: "example.com",
                                 start: origin.addingTimeInterval(-600), end: origin.addingTimeInterval(600))
        let segments = DaySegmenter.blocks(applications: slices, websites: [site], origin: origin).compactMap(\.segment)
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].focus, .fragmented)
        XCTAssertEqual(segments[0].switches, 59)
        XCTAssertEqual(segments[0].websites.first?.seconds, 600)
    }

    func testEmptyInputAndSimilarity() {
        XCTAssertTrue(DaySegmenter.blocks(applications: [], origin: origin).isEmpty)
        XCTAssertEqual(DaySegmenter.similarity(["a": 3, "b": 1], ["a": 1, "b": 3]), 0.5, accuracy: 0.0001)
        XCTAssertEqual(DaySegmenter.similarity(["a": 1], ["b": 1]), 0)
    }
}
