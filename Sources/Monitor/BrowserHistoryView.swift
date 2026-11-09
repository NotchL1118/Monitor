import SwiftUI
import MonitorCore

/// Every page visited in the period, grouped by Chrome foreground sessions.
struct BrowserHistoryView: View {
    let report: BrowserReport
    /// The site selected in the rankings; offered as a "只看" filter.
    let site: BrowserGroup?
    @Binding var bucket: Date?
    let scrollProxy: ScrollViewProxy
    @State private var query = ""
    @State private var onlySite = false
    @State private var hideShort = false
    @State private var mode = BrowserDetailMode.list
    /// nil keeps each session's default; set by "全部展开/全部收起".
    @State private var expandAll: Bool?
    @State private var generation = 0
    @State private var focusedSession: Date?

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var bucketInterval: DateInterval? { report.buckets.first { $0.id == bucket }?.interval }
    private var filtering: Bool { (onlySite && site != nil) || hideShort || bucket != nil || !trimmedQuery.isEmpty }

    private func matches(_ visit: ActivitySlice) -> Bool {
        if onlySite, let site, report.site(of: visit) != site.id { return false }
        if hideShort && visit.seconds < 60 { return false }
        if let span = bucketInterval, !(visit.start < span.end && visit.end > span.start) { return false }
        let query = trimmedQuery
        if !query.isEmpty {
            let haystack = [visitTitle(visit), visit.pageURL ?? "", visit.key]
            if !haystack.contains(where: { $0.localizedCaseInsensitiveContains(query) }) { return false }
        }
        return true
    }

    var body: some View {
        let shown = filtering ? report.visits.filter(matches) : report.visits
        let sessions = groupedSessions()
        let defaultExpanded = filtering || report.visits.count <= 150
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                sectionTitle("浏览记录")
                Text("\(shown.count) 次访问 · \(Set(shown.map { $0.pageURL ?? $0.key }).count) 个页面 · \(durationText(shown.reduce(0) { $0 + $1.seconds }))")
                    .font(.system(size: 12)).monospacedDigit().foregroundStyle(Palette.muted)
                Spacer(minLength: 8)
                BrowserViewSwitcher(selection: $mode)
            }
            if report.chrome.period == .day && !report.visits.isEmpty {
                BrowserDayStrip(report: report, shown: filtering ? Set(shown.map(\.id)) : nil) { visit in focus(on: visit) }
            }
            FlowLayout(spacing: 10) {
                searchField
                if let site {
                    SegmentedControl(options: [false, true], selection: $onlySite, compact: true,
                                     title: { $0 ? "只看 \(site.title)" : "全部网站" })
                }
                Toggle(isOn: $hideShort) { Text("隐藏 1 分钟以内").font(.system(size: 12)) }
                    .toggleStyle(.switch).controlSize(.mini).tint(Palette.green).padding(.top, 3)
                if let span = bucketInterval {
                    FilterChip(text: bucketText(span, period: report.chrome.period, calendar: report.chrome.calendar)) { bucket = nil }
                        .padding(.top, 2)
                }
                if !sessions.isEmpty {
                    let expanded = expandAll ?? defaultExpanded
                    textButton(expanded ? "全部收起" : "全部展开") {
                        expandAll = !expanded
                        focusedSession = nil
                        generation += 1
                    }.padding(.top, 5)
                }
            }
            if sessions.isEmpty {
                Text(filtering ? "没有符合条件的网页。可以换个关键词，或关掉上面的筛选。" : "这个时段没有 Chrome 使用记录。")
                    .font(.system(size: 13)).foregroundStyle(Palette.muted)
                    .frame(maxWidth: .infinity).padding(.vertical, 22)
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.line, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            } else {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(sessions, id: \.day) { group in
                        if report.chrome.period != .day {
                            Text(dayText(group.day, calendar: report.chrome.calendar))
                                .font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.muted).padding(.top, 4)
                        }
                        ForEach(group.sessions, id: \.session.start) { item in
                            let focused = focusedSession == item.session.start
                            BrowserSessionView(session: item.session, visits: item.visits, calendar: report.chrome.calendar,
                                mode: mode, scrollProxy: scrollProxy,
                                activeSeconds: report.chrome.activeSeconds[item.session.start] ?? item.session.seconds,
                                interruptions: report.chrome.interruptions[item.session.id] ?? 0,
                                initiallyExpanded: focused || (expandAll ?? defaultExpanded),
                                highlighted: focused, filtered: filtering)
                                .id(anchor(item.session, focused: focused))
                        }
                    }
                }
            }
        }.padding(16).background(.white, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.line))
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(Palette.muted)
            TextField("搜索网页标题或网址", text: $query).textFieldStyle(.plain).font(.system(size: 13))
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.muted) }
                    .buttonStyle(.plain).help("清除搜索").accessibilityLabel("清除搜索")
            }
        }.padding(.horizontal, 9).frame(width: 240, height: 28)
            .background(Palette.sunk, in: RoundedRectangle(cornerRadius: 7))
    }

    private struct SessionItem { let session: ActivitySlice; let visits: [ActivitySlice] }
    private struct DayGroup { let day: Date; let sessions: [SessionItem] }

    private func groupedSessions() -> [DayGroup] {
        report.chrome.days.compactMap { day in
            let items = day.sessions.compactMap { session -> SessionItem? in
                let visits = report.visits(in: session)
                guard filtering else { return SessionItem(session: session, visits: visits) }
                let matched = visits.filter(matches)
                return matched.isEmpty ? nil : SessionItem(session: session, visits: matched)
            }
            return items.isEmpty ? nil : DayGroup(day: day.date, sessions: items)
        }
    }

    /// Identity changes when filtering, focusing or "全部展开/收起" should reset a session's expansion.
    private func anchor(_ session: ActivitySlice, focused: Bool) -> String {
        "browser-history-\(session.start.timeIntervalSince1970)-\(generation)-\(filtering)-\(focused)"
    }

    private func focus(on visit: ActivitySlice) {
        guard let session = report.chrome.days.lazy.flatMap(\.sessions)
            .first(where: { $0.start <= visit.start && visit.start < $0.end }) else { return }
        focusedSession = session.start
        let id = anchor(session, focused: true)
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.25)) { scrollProxy.scrollTo(id, anchor: .top) }
        }
    }
}

/// The whole day on one axis. Each visit is a mark in its site's color; filtered-out visits fade.
private struct BrowserDayStrip: View {
    let report: BrowserReport
    let shown: Set<Int64>?
    let select: (ActivitySlice) -> Void

    var body: some View {
        let span = report.chrome.interval
        VStack(spacing: 3) {
            GeometryReader { geometry in
                let width = geometry.size.width
                Canvas { context, size in
                    context.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 7), with: .color(Palette.sunk))
                    for visit in report.visits {
                        let x = width * visit.start.timeIntervalSince(span.start) / span.duration
                        let w = max(1.5, width * visit.seconds / span.duration)
                        let visible = shown?.contains(visit.id) ?? true
                        context.fill(Path(roundedRect: CGRect(x: x, y: 4, width: w, height: size.height - 8), cornerRadius: 1),
                                     with: .color(SiteAvatar.ink(report.site(of: visit)).opacity(visible ? 0.9 : 0.15)))
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { location in
                    let time = span.start.addingTimeInterval(span.duration * Double(location.x / max(1, width)))
                    let tolerance = span.duration * 4 / Double(max(1, width))
                    let candidates = report.visits.filter { shown?.contains($0.id) ?? true }
                    if let visit = candidates.min(by: { distance($0, time) < distance($1, time) }), distance(visit, time) <= tolerance {
                        select(visit)
                    }
                }
            }.frame(height: 26)
            HStack(spacing: 0) {
                ForEach(Array(stride(from: 0, through: 24, by: 3)), id: \.self) { hour in
                    Text("\(hour)")
                    if hour < 24 { Spacer(minLength: 0) }
                }
            }.font(.system(size: 10)).monospacedDigit().foregroundStyle(Palette.muted)
        }
        .help("点击色块跳到对应的浏览记录")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("全天网页分布，共 \(report.visits.count) 次访问")
    }

    private func distance(_ visit: ActivitySlice, _ time: Date) -> TimeInterval {
        if time < visit.start { return visit.start.timeIntervalSince(time) }
        if time > visit.end { return time.timeIntervalSince(visit.end) }
        return 0
    }
}
