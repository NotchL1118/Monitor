import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let model: MonitorModel
    private var status: StatusController?
    private(set) var mainWindow: NSWindow?

    init(model: MonitorModel) {
        self.model = model
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let identifier = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
            .contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            NSApp.terminate(nil)
            return
        }
        installKeyCommands()
        model.start()
        status = StatusController(model: model) { [weak self] page in self?.showWindow(page) }
        showWindow(.overview)
    }

    func showWindow(_ page: DashboardPage) {
        model.dashboardPage = page
        NSApp.setActivationPolicy(.regular)
        status?.ensureVisible()
        if mainWindow == nil {
            let host = NSHostingController(rootView: DashboardView().environmentObject(model))
            let window = NSWindow(contentViewController: host)
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.title = "Monitor · 时间足迹"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.contentMinSize = NSSize(width: 920, height: 650)
            window.setContentSize(NSSize(width: 1120, height: 780))
            window.center()
            window.setFrameAutosaveName("MonitorDashboard")
            mainWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        if mainWindow?.isMiniaturized == true { mainWindow?.deminiaturize(nil) }
        mainWindow?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === mainWindow else { return }
        // Closing the dashboard returns to menu-bar-only recording; minimizing does not.
        NSApp.setActivationPolicy(.accessory)
        status?.ensureVisible()
    }

    // These commands also remain available when reopening from the status item.
    private func installKeyCommands() {
        let menu = NSMenu()
        let commands = NSMenu(title: "Monitor")
        let appItem = NSMenuItem()
        menu.addItem(appItem)
        appItem.submenu = commands
        let report = commands.addItem(withTitle: "打开时间足迹", action: #selector(openReport), keyEquivalent: "o")
        report.target = self
        let pause = commands.addItem(withTitle: "暂停或继续记录", action: #selector(pauseRecording), keyEquivalent: "p")
        pause.keyEquivalentModifierMask = [.command, .shift]
        pause.target = self
        commands.addItem(withTitle: "关闭窗口", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        commands.addItem(withTitle: "退出 Monitor", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let editItem = NSMenuItem(title: "编辑", action: nil, keyEquivalent: "")
        menu.addItem(editItem)
        let edit = NSMenu(title: "编辑")
        editItem.submenu = edit
        for (name, selector, key) in [("剪切", "cut:", "x"), ("复制", "copy:", "c"),
                                      ("粘贴", "paste:", "v"), ("全选", "selectAll:", "a")] {
            edit.addItem(withTitle: name, action: Selector(selector), keyEquivalent: key)
        }
        NSApp.mainMenu = menu
    }

    @objc private func openReport() { showWindow(.overview) }
    @objc private func pauseRecording() { model.togglePause() }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) { status?.stop(); model.stop() }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow(.overview)
        return false
    }
}

@main
struct MonitorApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate(model: .shared)
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
