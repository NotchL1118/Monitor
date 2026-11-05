import AppKit
import SwiftUI

/// The current installed location, not a path recorded with historical usage.
struct ApplicationLocationView: View {
    let bundleIdentifier: String
    @State private var applicationURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let applicationURL {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Image(systemName: "folder")
                    Text(applicationURL.path)
                        .lineLimit(1).truncationMode(.middle)
                        .textSelection(.enabled)
                        .help(applicationURL.path)
                }
                .foregroundStyle(Palette.muted)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("当前安装位置：\(applicationURL.path)")

                Button(action: revealApplication) {
                    Label("在访达中显示", systemImage: "arrow.up.forward.square")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.green)
                .help("打开所在文件夹并选中应用")
            } else {
                Label("找不到应用位置，可能已卸载或移动", systemImage: "folder.badge.questionmark")
                    .foregroundStyle(Palette.muted)
            }
        }
        .font(.system(size: 11))
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: bundleIdentifier) { refreshLocation() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshLocation()
        }
    }

    private func refreshLocation() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier),
              FileManager.default.fileExists(atPath: url.path),
              Bundle(url: url)?.bundleIdentifier == bundleIdentifier else {
            applicationURL = nil
            return
        }
        applicationURL = url
    }

    private func revealApplication() {
        // Resolve again in case the app was moved or removed while this report was open.
        refreshLocation()
        guard let applicationURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([applicationURL])
    }
}
