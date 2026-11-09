import SwiftUI
import XCTest
import MonitorCore
@testable import Monitor

final class UsageShareRingTests: XCTestCase {
    @MainActor
    func testBadgesFitWideAndNarrowSectorsAtBothSizes() throws {
        let items = [67, 20, 7, 4, 1, 1].enumerated().map {
            UsageSummary(key: "app-\($0.offset)", name: "App \($0.offset)", seconds: Double($0.element))
        }
        let shares = UsageShare.make(items)
        for size: CGFloat in [88, 152] {
            let ring = UsageShareRing(shares: shares, kind: .application, highlighted: .constant(nil), size: size)
            let wide = try XCTUnwrap(ring.badgeFrame(for: shares[0]))
            let narrow = try XCTUnwrap(ring.badgeFrame(for: shares[2]))
            XCTAssertGreaterThan(wide.width, narrow.width)
            XCTAssertNil(ring.badgeFrame(for: shares[4]))
            XCTAssertNil(ring.badgeFrame(for: shares[5])) // "Other" has no single icon.
            let frames = shares.compactMap { ring.badgeFrame(for: $0) }
            for (index, frame) in frames.enumerated() {
                XCTAssertTrue(CGRect(x: 0, y: 0, width: size, height: size).contains(frame))
                for next in frames.dropFirst(index + 1) {
                    XCTAssertGreaterThanOrEqual(hypot(frame.midX - next.midX, frame.midY - next.midY),
                                                (frame.width + next.width) / 2)
                }
            }
        }
    }
}
