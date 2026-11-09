import SwiftUI
import XCTest
import MonitorCore
@testable import Monitor

final class UsageShareRingTests: XCTestCase {
    @MainActor
    func testLowerRanksHaveProgressivelyLighterColors() {
        let luminances = (0..<5).map { rank in
            let color = SharePalette.color(slot: rank).resolve(in: EnvironmentValues())
            return 0.2126 * color.linearRed + 0.7152 * color.linearGreen + 0.0722 * color.linearBlue
        }
        for (higherRank, lowerRank) in zip(luminances, luminances.dropFirst()) {
            XCTAssertLessThan(higherRank, lowerRank)
        }
    }

    @MainActor
    func testBadgesFitWideAndNarrowSectorsAtBothSizes() throws {
        let minutes = [242, 42, 32, 16, 10] + Array(repeating: 3, count: 10) + [2, 2]
        let items = minutes.enumerated().map {
            UsageSummary(key: "app-\($0.offset)", name: "App \($0.offset)", seconds: Double($0.element))
        }
        let shares = UsageShare.make(items)
        for size in [UsageShareRing.classicSize, UsageShareRing.narrowSize] {
            let ring = UsageShareRing(shares: shares, kind: .application, highlighted: .constant(nil), size: size)
            let wide = try XCTUnwrap(ring.badgeFrame(for: shares[0]))
            let narrow = try XCTUnwrap(ring.badgeFrame(for: shares[3]))
            XCTAssertGreaterThan(wide.width, narrow.width)
            let center = size / 2
            XCTAssertGreaterThan(hypot(narrow.midX - center, narrow.midY - center),
                                 hypot(wide.midX - center, wide.midY - center))
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
