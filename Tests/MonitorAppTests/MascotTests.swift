import AppKit
import SwiftUI
import XCTest
@testable import Monitor

final class MascotTests: XCTestCase {
    @MainActor
    func testSwitchesBlinkOnceAndPauseCancelsPendingFrames() async throws {
        let mascot = MascotAnimator()
        defer { mascot.stop() }
        mascot.update(applicationID: "editor", resting: .awake, animate: true, now: 0)
        XCTAssertEqual(mascot.frame, .awake, "startup must not animate")
        mascot.update(applicationID: "editor", resting: .awake, animate: true, now: 1)
        XCTAssertEqual(mascot.frame, .awake, "sampling the same app must not animate")
        mascot.update(applicationID: "browser", resting: .awake, animate: true, now: 2)
        XCTAssertEqual(mascot.frame, .focus)
        try await Task.sleep(for: .milliseconds(110))
        XCTAssertEqual(mascot.frame, .blink)
        mascot.update(applicationID: "finder", resting: .awake, animate: true, now: 2.1)
        XCTAssertEqual(mascot.frame, .blink, "rapid switches must not restart the animation")
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(mascot.frame, .awake)
        mascot.update(applicationID: "editor", resting: .awake, animate: true, now: 4)
        XCTAssertEqual(mascot.frame, .focus)
        mascot.update(applicationID: "editor", resting: .sleeping, animate: true, now: 4.1)
        XCTAssertEqual(mascot.frame, .sleeping)
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(mascot.frame, .sleeping, "cancelled frames must not wake a paused mascot")
        mascot.update(applicationID: "browser", resting: .awake, animate: false, now: 6)
        XCTAssertEqual(mascot.frame, .awake)
        mascot.update(applicationID: "editor", resting: .awake, animate: true, now: 8)
        mascot.update(applicationID: "editor", resting: .awake, animate: false, now: 8.1)
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(mascot.frame, .awake, "turning off motion must cancel an in-flight blink")
    }

    @MainActor
    func testMotionPreferencePersistsAndPausedBindingSleeps() throws {
        let suite = "Monitor-Mascot-QA-\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let model = MonitorModel(preferences: preferences)
        XCTAssertTrue(model.mascotAnimationsEnabled)
        model.mascotAnimationsEnabled = false
        let restored = MonitorModel(preferences: preferences)
        XCTAssertFalse(restored.mascotAnimationsEnabled)
        model.paused = true
        XCTAssertEqual(model.mascot.frame, .sleeping)
        model.storageError = "Test storage failure"
        XCTAssertEqual(model.mascot.frame, .waiting)
        model.mascot.stop(); restored.mascot.stop()
    }

    @MainActor
    func testRenderBrandAtRealMenuBarSizes() async throws {
        _ = NSApplication.shared
        let sheet = VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 24) {
                BrandPortrait().frame(width: 160, height: 160)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Monitor · 镜头发夹机娘").font(.title2)
                    Text("主应用 / 记录中 / 已暂停 / 未连接").foregroundStyle(.secondary)
                    HStack(spacing: 20) {
                        ForEach([MascotFrame.awake, .sleeping, .waiting], id: \.rawValue) { frame in
                            Image(nsImage: MascotArtwork.image(frame: frame)).resizable().frame(width: 80, height: 80)
                        }
                    }
                }
            }
            ForEach([false, true], id: \.self) { dark in
                HStack(spacing: 24) {
                    Text(dark ? "深色菜单栏" : "浅色菜单栏").font(.caption)
                    ForEach(MascotFrame.allCases, id: \.rawValue) { frame in
                        Image(nsImage: MascotArtwork.image(frame: frame, size: 18, template: true))
                            .renderingMode(.template).frame(width: 18, height: 18)
                    }
                    Spacer()
                    Text("Wed 10:24").font(.caption)
                }.padding(14).foregroundStyle(dark ? .white : .black)
                    .background(dark ? Color(white: 0.18) : Color(white: 0.91), in: RoundedRectangle(cornerRadius: 10))
            }
        }.padding(28).frame(width: 640).background(Color(white: 0.97)).environment(\.colorScheme, .light)
        let host = NSHostingView(rootView: sheet)
        host.setFrameSize(host.fittingSize)
        let window = NSWindow(contentRect: host.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(100))
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let output = root.appendingPathComponent(".build/qa")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: output.appendingPathComponent("brand-preview.png"))
    }
}
