import AppKit
import SwiftUI
import Combine

@MainActor
final class StatusController: NSObject, NSPopoverDelegate, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let popover = NSPopover()
    private let model: MonitorModel
    private let openWindow: (DashboardPage) -> Void
    private var monitors: [Any] = []
    private var mascotSubscription: AnyCancellable?
    private let mascotFrames = Dictionary(uniqueKeysWithValues: MascotFrame.allCases.map {
        ($0, MascotArtwork.image(frame: $0, size: 18, template: true))
    })

    init(model: MonitorModel, openWindow: @escaping (DashboardPage) -> Void) {
        self.model = model
        self.openWindow = openWindow
        super.init()
        item.autosaveName = "MonitorStatus"
        ensureVisible()
        if let button = item.button {
            button.image = mascotFrames[model.mascot.frame]
            button.imagePosition = .imageOnly
            button.toolTip = "Monitor · 单击查看仪表盘，右键打开控制面板"
            button.setAccessibilityLabel("Monitor 时间足迹")
            button.target = self
            button.action = #selector(clicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        popover.delegate = self
        popover.behavior = .applicationDefined
        popover.animates = false
        mascotSubscription = model.mascot.$frame.sink { [weak self] frame in
            guard let self, let button = self.item.button else { return }
            button.image = self.mascotFrames[frame]
            let status = frame == .sleeping ? "记录已暂停" : (frame == .waiting ? "等待记录" : "正在记录")
            button.setAccessibilityLabel("Monitor 时间足迹 · \(status)")
            button.toolTip = "Monitor · \(status) · 单击查看仪表盘，右键打开控制面板"
        }
    }

    func ensureVisible() {
        // A restored hidden status item must not leave a background app without an entry point.
        item.isVisible = true
    }

    @objc private func clicked() {
        let event = NSApp.currentEvent
        let secondary = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
        handleClick(secondary: secondary)
    }

    func handleClick(secondary: Bool) {
        if secondary {
            showControls()
        } else if popover.isShown {
            popover.close()
        } else {
            showDashboard()
        }
    }

    @objc private func showDashboard() {
        guard let button = item.button, !popover.isShown else { return }
        model.menuDashboardVisible = true
        model.sample()
        let view = MenuDashboard(model: model) { [weak self] in self?.openReport() }
        let host = NSHostingController(rootView: view)
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host
        popover.contentSize = host.view.fittingSize
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        guard popover.isShown else { model.menuDashboardVisible = false; return }

        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: clicks, handler: { [weak self] _ in
            self?.popover.close()
        }) { monitors.append(monitor) }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: [clicks, .keyDown], handler: { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown {
                if event.keyCode == 53 { self.popover.close(); return nil }
            } else if event.window !== self.item.button?.window &&
                        event.window !== self.popover.contentViewController?.view.window {
                self.popover.close()
            }
            return event
        }) { monitors.append(monitor) }
    }

    func popoverDidClose(_ notification: Notification) {
        model.menuDashboardVisible = false
        removeMonitors()
    }

    private func removeMonitors() {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors.removeAll()
    }

    private func showControls() {
        guard let button = item.button else { return }
        popover.close()
        let menu = NSMenu()
        func add(_ title: String, _ icon: String, _ action: Selector, key: String = "") {
            let entry = NSMenuItem(title: title, action: action, keyEquivalent: key)
            entry.target = self
            entry.image = NSImage(systemSymbolName: icon, accessibilityDescription: nil)
            menu.addItem(entry)
        }
        add("打开时间足迹", "macwindow", #selector(openReport), key: "o")
        add("连接与设置", "gearshape", #selector(openSettings), key: ",")
        menu.addItem(.separator())
        add(model.paused ? "继续记录" : "暂停记录", model.paused ? "play" : "pause", #selector(toggleRecording))
        menu.addItem(.separator())
        add("退出 Monitor", "power", #selector(quit), key: "q")
        // Attach only while tracking so AppKit anchors the menu on the correct display.
        menu.delegate = self
        item.menu = menu
        button.performClick(nil)
    }

    func menuDidClose(_ menu: NSMenu) {
        if item.menu === menu { item.menu = nil }
    }

    @objc private func reopenDashboard() { DispatchQueue.main.async { [weak self] in self?.showDashboard() } }
    @objc private func openReport() {
        popover.close()
        openWindow(.overview)
    }
    @objc private func openSettings() { openWindow(.connection) }
    @objc private func toggleRecording() { model.togglePause(); reopenDashboard() }
    @objc private func quit() { NSApp.terminate(nil) }

    func stop() {
        mascotSubscription = nil
        popover.close()
        removeMonitors()
        NSStatusBar.system.removeStatusItem(item)
    }
}
