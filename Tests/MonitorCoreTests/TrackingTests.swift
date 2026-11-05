import XCTest
@testable import MonitorCore

final class TrackingTests: XCTestCase {
    let zero = Date(timeIntervalSince1970: 1_700_000_000)
    let chrome = ActivityIdentity(key: ActivityTracker.chromeBundleID, name: "Google Chrome")
    let editor = ActivityIdentity(key: "test.editor", name: "Editor")

    func testApplicationSwitchAndWebsiteAreSeparateDimensions() {
        var tracker = ActivityTracker(now: zero)
        tracker.setApplication(chrome)
        tracker.setBrowser(BrowserUpdate(domain: "www.youtube.com", focused: true), at: zero)
        let first = tracker.advance(to: zero.addingTimeInterval(5))
        XCTAssertEqual(first.map(\.kind), [.application, .website])
        XCTAssertEqual(first.map(\.seconds), [5, 5])
        tracker.setApplication(editor)
        let second = tracker.advance(to: zero.addingTimeInterval(10))
        XCTAssertEqual(second.count, 1)
        XCTAssertEqual(second[0].key, editor.key)
        XCTAssertEqual(second[0].seconds, 5)
    }

    func testWebsiteSwitchFlushesOldWebsiteWithoutBackdating() {
        var tracker = ActivityTracker(now: zero)
        tracker.setApplication(chrome)
        tracker.setBrowser(BrowserUpdate(domain: "a.example", focused: true), at: zero)
        let old = tracker.advance(to: zero.addingTimeInterval(4))
        tracker.setBrowser(BrowserUpdate(domain: "b.example", focused: true), at: zero.addingTimeInterval(4))
        let new = tracker.advance(to: zero.addingTimeInterval(9))
        XCTAssertEqual(old.last?.key, "a.example")
        XCTAssertEqual(old.last?.seconds, 4)
        XCTAssertEqual(new.last?.key, "b.example")
        XCTAssertEqual(new.last?.seconds, 5)
    }

    func testBackgroundBrowserAndInternalPageDoNotCountWebsites() {
        for context in [BrowserUpdate(domain: "a.example", focused: false), BrowserUpdate(domain: nil, focused: true)] {
            var tracker = ActivityTracker(now: zero)
            tracker.setApplication(chrome)
            tracker.setBrowser(context, at: zero)
            XCTAssertEqual(tracker.advance(to: zero.addingTimeInterval(5)).count, 1)
        }
    }

    func testPauseResumeDoesNotBackfillPausedTime() {
        var tracker = ActivityTracker(now: zero)
        tracker.setApplication(editor)
        XCTAssertEqual(tracker.advance(to: zero.addingTimeInterval(5)).first?.seconds, 5)
        tracker.setEnabled(false, at: zero.addingTimeInterval(5))
        XCTAssertTrue(tracker.advance(to: zero.addingTimeInterval(10)).isEmpty)
        tracker.setEnabled(true, at: zero.addingTimeInterval(100))
        XCTAssertEqual(tracker.advance(to: zero.addingTimeInterval(105)).first?.seconds, 5)
    }

    func testSleepOrClockGapCannotBecomeHoursOfUsage() {
        var tracker = ActivityTracker(now: zero)
        tracker.setApplication(editor)
        XCTAssertTrue(tracker.advance(to: zero.addingTimeInterval(3600)).isEmpty)
        XCTAssertEqual(tracker.advance(to: zero.addingTimeInterval(3605)).first?.seconds, 5)
        XCTAssertTrue(tracker.advance(to: zero.addingTimeInterval(3604)).isEmpty)
    }

    func testStaleBrowserExpiresAtExactBoundaryWhileApplicationContinues() {
        var tracker = ActivityTracker(now: zero)
        tracker.setApplication(chrome)
        tracker.setBrowser(BrowserUpdate(domain: "a.example", focused: true), at: zero)
        for second in stride(from: 10, through: 70, by: 10) { _ = tracker.advance(to: zero.addingTimeInterval(Double(second))) }
        let boundary = tracker.advance(to: zero.addingTimeInterval(80))
        XCTAssertEqual(boundary[0].seconds, 10)
        XCTAssertEqual(boundary[1].seconds, 5)
        XCTAssertEqual(tracker.advance(to: zero.addingTimeInterval(85)).count, 1)
        tracker.setBrowser(BrowserUpdate(domain: "a.example", focused: true), at: zero.addingTimeInterval(85))
        XCTAssertEqual(tracker.advance(to: zero.addingTimeInterval(90)).last?.seconds, 5)
    }

    func testWakeRequiresFreshBrowserContext() {
        var tracker = ActivityTracker(now: zero)
        tracker.setApplication(chrome)
        tracker.setBrowser(BrowserUpdate(domain: "a.example", focused: true), at: zero)
        tracker.invalidateBrowser()
        XCTAssertEqual(tracker.advance(to: zero.addingTimeInterval(5)).count, 1)
    }

    func testLoginWindowIsNeverCountedAsComputerUsage() {
        var tracker = ActivityTracker(now: zero)
        tracker.setApplication(ActivityIdentity(key: "com.apple.loginwindow", name: "loginwindow"))
        XCTAssertTrue(tracker.advance(to: zero.addingTimeInterval(5)).isEmpty)
    }

    func testBrowserDomainValidationRejectsFullURLsAndSecrets() {
        for domain in ["https://example.com", "example.com/search?q=secret", "name@example.com", "EXAMPLE.COM", "-bad.com", "", "a..com", "example.com:443"] {
            XCTAssertFalse(BrowserUpdate(domain: domain, focused: true).isValid, domain)
        }
        for domain in ["www.youtube.com", "xn--fiqs8s.example", "localhost", "127.0.0.1"] {
            XCTAssertTrue(BrowserUpdate(domain: domain, focused: true).isValid, domain)
        }
    }
}
