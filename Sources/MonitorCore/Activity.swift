import Foundation

public enum ActivityKind: String, Codable, CaseIterable {
    case application, website
}

public struct ActivityIdentity: Equatable {
    public let key: String
    public let name: String
    public init(key: String, name: String) { self.key = key; self.name = name }
}

public struct ActivitySlice: Codable, Identifiable {
    public var id: Int64
    public let kind: ActivityKind
    public let key: String
    public let name: String
    public let pageURL: String?
    public let pageTitle: String?
    public let start: Date
    public let end: Date
    public var seconds: Double { end.timeIntervalSince(start) }

    public init(id: Int64 = 0, kind: ActivityKind, key: String, name: String, start: Date, end: Date, pageURL: String? = nil, pageTitle: String? = nil) {
        self.id = id; self.kind = kind; self.key = key; self.name = name
        self.start = start; self.end = end
        self.pageURL = pageURL; self.pageTitle = pageTitle
    }
}

public struct UsageSummary: Identifiable {
    public var id: String { key }
    public let key: String
    public let name: String
    public let seconds: Double
}

public struct BrowserUpdate: Codable {
    public let domain: String?
    public let focused: Bool

    public let url: String?
    public let title: String?

    public init(domain: String?, focused: Bool, url: String? = nil, title: String? = nil) {
        self.domain = domain; self.focused = focused; self.url = url; self.title = title
    }

    public var isValid: Bool {
        guard let domain else { return url == nil && title == nil }
        guard !domain.isEmpty, domain.count <= 253, domain == domain.lowercased(),
              domain.split(separator: ".", omittingEmptySubsequences: false).allSatisfy({ label in
                  !label.isEmpty && label.count <= 63 && label.first != "-" && label.last != "-" &&
                  label.utf8.allSatisfy { (97...122).contains($0) || (48...57).contains($0) || $0 == 45 }
              }) else { return false }
        if let title {
            guard url != nil, title.utf8.count <= 1024,
                  !title.unicodeScalars.contains(where: { $0.value < 32 || (127...159).contains($0.value) }) else { return false }
        }
        if let url {
            guard focused, url.utf8.count <= 8192,
                  !url.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0) }),
                  let parsed = URLComponents(string: url), ["http", "https"].contains(parsed.scheme),
                  parsed.host?.lowercased() == domain, parsed.user == nil, parsed.password == nil else { return false }
        }
        return true
    }

}

/// Receives a monotonic sequence of samples. App and website durations are separate dimensions.
public struct ActivityTracker {
    public static let browserTTL: TimeInterval = 75
    /// Sleep, lock and session changes stop the clock via notifications; this only guards against
    /// unexplained stalls. Kept well above the 5 s sampling period so a late timer doesn't lose time.
    public static let maximumGap: TimeInterval = 60
    public static let chromeBundleID = "com.google.Chrome"
    public private(set) var application: ActivityIdentity?
    public private(set) var browser: BrowserUpdate?
    public private(set) var browserSeen: Date?
    private var lastSample: Date
    private var enabled = true

    public init(now: Date) { lastSample = now }

    public mutating func advance(to now: Date) -> [ActivitySlice] {
        let start = lastSample
        lastSample = now
        let delta = now.timeIntervalSince(start)
        guard enabled, delta > 0, delta <= Self.maximumGap, let app = application else { return [] }
        var slices = [ActivitySlice(kind: .application, key: app.key, name: app.name, start: start, end: now)]
        if app.key == Self.chromeBundleID, let browser, browser.focused,
           let domain = browser.domain, let seen = browserSeen {
            let websiteEnd = min(now, seen.addingTimeInterval(Self.browserTTL))
            let websiteStart = max(start, seen)
            if websiteEnd > websiteStart {
                slices.append(ActivitySlice(kind: .website, key: domain, name: domain, start: websiteStart, end: websiteEnd,
                    pageURL: browser.url, pageTitle: browser.title))
            }
        }
        return slices
    }

    public mutating func setApplication(_ value: ActivityIdentity?) {
        application = value?.key == "com.apple.loginwindow" ? nil : value
    }
    public mutating func setBrowser(_ update: BrowserUpdate, at now: Date) {
        guard update.isValid else { return }
        browser = update; browserSeen = now
    }
    public mutating func setEnabled(_ value: Bool, at now: Date) { enabled = value; lastSample = now }
    public mutating func reset(at now: Date) { lastSample = now }
    public mutating func invalidateBrowser() { browser = nil; browserSeen = nil }
}
