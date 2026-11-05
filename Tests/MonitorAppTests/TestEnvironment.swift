import Foundation
import XCTest

enum TestEnvironment {
    // Hosted macOS runners can abort inside Metal before XCTest can report a failure.
    // Keep rendering enabled by default on local Macs; CI opts out explicitly.
    static var skipsWindowRendering: Bool {
        ProcessInfo.processInfo.environment["MONITOR_SKIP_UI_TESTS"] == "1"
    }

    static func requireWindowRendering() throws {
        try XCTSkipIf(skipsWindowRendering,
                      "Window rendering requires a desktop with working Metal; run ./scripts/test.sh locally.")
    }
}
