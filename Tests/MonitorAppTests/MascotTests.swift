import AppKit
import SwiftUI
import XCTest
@testable import Monitor

final class MascotTests: XCTestCase {
    @MainActor
    func testFaceFollowsRecordingState() throws {
        let suite = "Monitor-Mascot-QA-\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let model = MonitorModel(preferences: preferences)
        defer { model.mascot.stop() }
        model.paused = true
        XCTAssertEqual(model.mascot.frame, .sleeping)
        model.storageError = "Test storage failure"
        XCTAssertEqual(model.mascot.frame, .waiting)
    }

    @MainActor
    func testRenderBrandAtRealMenuBarSizes() async throws {
        try TestEnvironment.requireWindowRendering()
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
