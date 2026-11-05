import AppKit
import Combine
import MonitorCore
import UniformTypeIdentifiers

enum DashboardPage { case overview, applications, dayTimeline, connection }

@MainActor
final class MonitorModel: ObservableObject {
    static let shared = MonitorModel()
    @Published var paused = UserDefaults.standard.bool(forKey: "recordingPaused")
    @Published var period: ReportPeriod = .day { didSet { refresh() } }
    @Published var selectedDate = Date() { didSet { refresh() } }
    @Published var reportTimeZone: ReportTimeZone {
        didSet {
            guard reportTimeZone != oldValue else { return }
            preferences.set(reportTimeZone.rawValue, forKey: ReportTimeZone.preferenceKey)
            let now = Date(), oldCalendar = oldValue.calendar
            let wasCurrent = period.interval(containing: selectedDate, calendar: oldCalendar).start ==
                period.interval(containing: now, calendar: oldCalendar).start
            let day = oldCalendar.dateComponents([.year, .month, .day], from: selectedDate)
            selectedDate = wasCurrent ? now : min(reportCalendar.date(from: day) ?? selectedDate, now)
        }
    }
    @Published var applications: [UsageSummary] = []
    @Published var websites: [UsageSummary] = []
    @Published private(set) var dailyActivities: [ActivitySlice] = []
    @Published var timeline: [ActivitySlice] = []
    @Published var selectedApplication: ActivityIdentity? { didSet { refreshApplicationReport() } }
    @Published private(set) var applicationReport: ApplicationReport?
    @Published private(set) var applicationReportError: String?
    @Published var currentApp = "等待应用活动"
    @Published private(set) var currentApplicationID: String?
    let mascot = MascotState()
    @Published var browserConnected = false
    @Published var serverReady = false
    @Published var serverError: String?
    @Published var storageError: String?
    @Published var notice: String?
    @Published var dashboardPage: DashboardPage = .overview
    @Published private(set) var today = TodaySnapshot.empty(at: Date())
    var menuDashboardVisible = false
    @Published var screenUnavailable = false
    let dataDirectory: URL
    private(set) var pairingToken = ""
    private var store: ActivityStore?
    private var tracker = ActivityTracker(now: Date())
    private var server: LocalServer?
    private var timer: Timer?
    private var napActivity: NSObjectProtocol?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var suspensionReasons: Set<String> = []
    private var started = false
    private let preferences: UserDefaults

    var recording: Bool { !paused && !screenUnavailable && storageError == nil && store != nil }
    var appSeconds: Double { applications.reduce(0) { $0 + $1.seconds } }
    var websiteSeconds: Double { websites.reduce(0) { $0 + $1.seconds } }
    var reportCalendar: Calendar { reportTimeZone.calendar }
    var reportInterval: DateInterval { period.interval(containing: selectedDate, calendar: reportCalendar) }
    var reportLabel: String { period.label(for: selectedDate, calendar: reportCalendar) }

    func stepPeriod(_ delta: Int) {
        let calendar = reportCalendar
        if let next = calendar.date(byAdding: period.component, value: delta, to: reportInterval.start) {
            selectedDate = min(next, Date())
        }
    }

    init(dataDirectory: URL? = nil, preferences: UserDefaults = .standard) {
        self.preferences = preferences
        reportTimeZone = preferences.string(forKey: ReportTimeZone.preferenceKey).flatMap(ReportTimeZone.init(rawValue:)) ?? .system
        self.dataDirectory = dataDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Monitor", isDirectory: true)
        mascot.bind(to: self)
    }

    func start() {
        guard !started else { return }
        started = true
        do {
            try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dataDirectory.path)
            let tokenURL = dataDirectory.appendingPathComponent("pairing-token")
            if FileManager.default.fileExists(atPath: tokenURL.path) {
                pairingToken = try String(contentsOf: tokenURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
                guard pairingToken.count == 64, pairingToken.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
                    throw StoreError(message: "本地配对码文件损坏，请移走 pairing-token 文件后重新启动。使用记录不会受影响。")
                }
            } else {
                pairingToken = (UUID().uuidString + UUID().uuidString).replacingOccurrences(of: "-", with: "").lowercased()
                try pairingToken.write(to: tokenURL, atomically: true, encoding: .utf8)
            }
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tokenURL.path)
            store = try ActivityStore(path: dataDirectory.appendingPathComponent("activity.sqlite").path)
        } catch { storageError = "无法保存使用记录：\(error.localizedDescription)"; return }

        let server = LocalServer(token: pairingToken)
        server.onUpdate = { [weak self] update in self?.receiveBrowser(update) }
        server.isRecording = { [weak self] in self?.recording ?? false }
        server.onState = { [weak self] error in self?.serverError = error; self?.serverReady = error == nil }
        self.server = server
        do { try server.start() } catch { serverError = error.localizedDescription }

        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.didActivateApplicationNotification) { [weak self] _ in self?.sample() }
        observe(workspace, NSWorkspace.willSleepNotification) { [weak self] _ in self?.suspend("sleep") }
        observe(workspace, NSWorkspace.didWakeNotification) { [weak self] _ in self?.resume("sleep") }
        observe(workspace, NSWorkspace.screensDidSleepNotification) { [weak self] _ in self?.suspend("display") }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { [weak self] _ in self?.resume("display") }
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification) { [weak self] _ in self?.suspend("session") }
        observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification) { [weak self] _ in self?.resume("session") }
        let distributed = DistributedNotificationCenter.default()
        observe(distributed, NSNotification.Name("com.apple.screenIsLocked")) { [weak self] _ in self?.suspend("lock") }
        observe(distributed, NSNotification.Name("com.apple.screenIsUnlocked")) { [weak self] _ in self?.resume("lock") }
        observe(NotificationCenter.default, .NSSystemTimeZoneDidChange) { [weak self] _ in
            if self?.reportTimeZone == .system { self?.refresh() }
        }
        tracker.setEnabled(recording, at: Date())
        updateFrontmost()
        refresh()
        // Without this, App Nap throttles the background sampling timer and intervals get discarded as gaps.
        napActivity = ProcessInfo.processInfo.beginActivity(options: [.userInitiatedAllowingIdleSystemSleep],
            reason: "记录前台应用使用时长")
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sample() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name,
                         _ action: @escaping @MainActor (Notification) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { notification in
            MainActor.assumeIsolated { action(notification) }
        }
        observers.append((center, token))
    }

    func stop() {
        mascot.stop()
        persist(until: Date())
        timer?.invalidate()
        if let napActivity { ProcessInfo.processInfo.endActivity(napActivity); self.napActivity = nil }
        for (center, token) in observers { center.removeObserver(token) }
        observers.removeAll()
        server?.stop()
    }

    private func persist(until now: Date) {
        let slices = tracker.advance(to: now)
        do { try store?.record(slices) }
        catch { storageError = "保存失败，记录已停止：\(error.localizedDescription)"; tracker.setEnabled(false, at: now) }
    }

    func sample() {
        let now = Date()
        persist(until: now)
        updateFrontmost()
        browserConnected = tracker.browserSeen.map { now.timeIntervalSince($0) < ActivityTracker.browserTTL } ?? false
        refresh()
    }

    private func updateFrontmost() {
        if let app = NSWorkspace.shared.frontmostApplication, let bundle = app.bundleIdentifier {
            if bundle == "com.apple.loginwindow" {
                suspensionReasons.insert("loginwindow")
                screenUnavailable = true
                tracker.setEnabled(false, at: Date())
                tracker.setApplication(nil)
                tracker.invalidateBrowser()
                currentApp = "屏幕已锁定"
                currentApplicationID = nil
                return
            }
            if suspensionReasons.remove("loginwindow") != nil {
                screenUnavailable = !suspensionReasons.isEmpty
                tracker.setEnabled(recording, at: Date())
            }
            let name = app.localizedName ?? bundle
            currentApp = name
            currentApplicationID = bundle
            tracker.setApplication(ActivityIdentity(key: bundle, name: name))
        } else { tracker.setApplication(nil); currentApp = "等待应用活动"; currentApplicationID = nil }
    }

    private func receiveBrowser(_ update: BrowserUpdate) {
        let now = Date()
        persist(until: now)
        tracker.setBrowser(update, at: now)
        browserConnected = true
        updateFrontmost()
        refresh()
    }

    private func suspend(_ reason: String) {
        let now = Date()
        persist(until: now)
        suspensionReasons.insert(reason)
        screenUnavailable = true
        tracker.setEnabled(false, at: now)
        tracker.invalidateBrowser()
        browserConnected = false
        refresh()
    }

    private func resume(_ reason: String) {
        suspensionReasons.remove(reason)
        screenUnavailable = !suspensionReasons.isEmpty
        if !screenUnavailable { tracker.invalidateBrowser(); browserConnected = false }
        tracker.setEnabled(recording, at: Date())
        updateFrontmost()
        refresh()
    }

    func togglePause() {
        let now = Date()
        persist(until: now)
        paused.toggle()
        UserDefaults.standard.set(paused, forKey: "recordingPaused")
        tracker.setEnabled(recording, at: now)
        updateFrontmost()
        refresh()
    }

    func refresh() {
        guard let store else { return }
        do {
            let interval = reportInterval
            applications = try store.summaries(kind: .application, from: interval.start, to: interval.end)
            websites = try store.summaries(kind: .website, from: interval.start, to: interval.end)
            timeline = try store.activities(from: interval.start, to: interval.end)
            let day = ReportPeriod.day.interval(containing: selectedDate, calendar: reportCalendar)
            dailyActivities = try store.activities(from: day.start, to: min(day.end, Date()), limit: -1)
                .filter { $0.kind == .application }.sorted { $0.start < $1.start }
            refreshApplicationReport()
            if menuDashboardVisible { today = try TodaySnapshot.read(from: store, at: Date(), calendar: reportCalendar) }
        } catch { storageError = error.localizedDescription; tracker.setEnabled(false, at: Date()) }
    }

    private func refreshApplicationReport() {
        guard let application = selectedApplication, let store else {
            applicationReport = nil
            applicationReportError = nil
            return
        }
        do {
            let interval = reportInterval
            let sessions = try store.sessions(kind: .application, key: application.key, from: interval.start, to: interval.end)
            applicationReport = ApplicationReport(application: application, period: period, interval: interval,
                sessions: sessions, calendar: reportCalendar,
                websites: application.key == ActivityTracker.chromeBundleID
                    ? try store.activities(from: interval.start, to: interval.end, limit: -1).filter { $0.kind == .website } : [])
            applicationReportError = nil
        } catch {
            applicationReport = nil
            applicationReportError = "无法读取应用详情：\(error.localizedDescription)"
        }
    }

    func showApplication(_ application: ActivityIdentity) {
        selectedApplication = application
        dashboardPage = .applications
    }

    func copyPairingCode() {
        guard !pairingToken.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(pairingToken, forType: .string)
        notice = "配对码已复制。请粘贴到 Chrome 扩展中。"
    }

    func exportReport() {
        sample()
        let interval = reportInterval
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Monitor-\(reportLabel).json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try store?.activities(from: interval.start, to: interval.end, limit: -1) ?? []
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(data).write(to: url, options: .atomic)
            notice = "已导出所选时段的记录。"
        } catch { notice = "导出失败：\(error.localizedDescription)" }
    }

    func deleteHistory() {
        do {
            try store?.deleteAll()
            tracker.reset(at: Date())
            refresh()
            notice = "历史记录已清空。"
        } catch { notice = "清空失败：\(error.localizedDescription)" }
    }
}

/// Suffix for a merged block, e.g. " · 含 3 次短暂切换"; empty when nothing was absorbed.
func interruptionText(_ count: Int?) -> String {
    guard let count, count > 0 else { return "" }
    return " · 含 \(count) 次短暂切换"
}

func durationText(_ seconds: Double) -> String {
    let value = max(0, Int(seconds))
    if value < 60 { return "\(value) 秒" }
    if value < 3600 { return "\(value / 60) 分钟" }
    return "\(value / 3600) 小时 \((value % 3600) / 60) 分钟"
}
