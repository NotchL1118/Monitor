import AppKit
import SwiftUI
import MonitorCore

enum BrowserDetailMode: String, CaseIterable {
    case list = "紧凑清单"
    case trace = "时段轨迹"
}

struct BrowserViewSwitcher: View {
    @Binding var selection: BrowserDetailMode
    @State private var hovered: BrowserDetailMode?

    var body: some View {
        HStack(spacing: 5) {
            ForEach(BrowserDetailMode.allCases, id: \.self) { mode in
                let active = selection == mode
                Button {
                    selection = mode
                } label: {
                    Label(mode.rawValue, systemImage: mode == .list ? "list.bullet" : "chart.bar.xaxis")
                        .font(.system(size: 12, weight: active ? .semibold : .regular))
                        .foregroundStyle(active ? Palette.green : Palette.muted)
                        .padding(.horizontal, 9).frame(height: 30)
                        .background(hovered == mode ? Palette.background : .clear, in: RoundedRectangle(cornerRadius: 5))
                        .overlay(alignment: .bottom) {
                            if active { Capsule().fill(Palette.green).frame(height: 2).padding(.horizontal, 8) }
                        }
                        .contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .onHover { inside in
                        if inside { hovered = mode } else if hovered == mode { hovered = nil }
                    }
                    .accessibilityAddTraits(active ? .isSelected : [])
                    .accessibilityIdentifier("browser-mode-" + (mode == .list ? "list" : "trace"))
            }
        }.fixedSize().accessibilityElement(children: .contain).accessibilityLabel("浏览明细视图")
    }
}

struct BrowserSessionView: View {
    let session: ActivitySlice
    let visits: [ActivitySlice]
    let calendar: Calendar
    let mode: BrowserDetailMode
    let scrollProxy: ScrollViewProxy?
    let activeSeconds: Double
    let interruptions: Int
    let highlighted: Bool
    /// The visits are a filtered subset: omit "无页面记录" gaps between them.
    let filtered: Bool
    @State private var expanded: Bool
    @State private var headerHovered = false
    @State private var selected: Int64?
    @State private var showPageDetails = false

    init(session: ActivitySlice, visits: [ActivitySlice], calendar: Calendar, mode: BrowserDetailMode,
         scrollProxy: ScrollViewProxy?, activeSeconds: Double, interruptions: Int,
         initiallyExpanded: Bool, highlighted: Bool, filtered: Bool = false) {
        self.session = session; self.visits = visits; self.calendar = calendar; self.mode = mode
        self.scrollProxy = scrollProxy; self.activeSeconds = activeSeconds; self.interruptions = interruptions
        self.highlighted = highlighted
        self.filtered = filtered
        _expanded = State(initialValue: initiallyExpanded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                expanded.toggle()
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .medium)).foregroundStyle(Palette.muted).frame(width: 10)
                    Text(browserRange(session.start, session.end, calendar: calendar))
                        .font(.system(size: 13, weight: .medium)).monospacedDigit().foregroundStyle(Palette.ink)
                    Spacer(minLength: 4)
                    if interruptions > 0 { Text("含 \(interruptions) 次短暂切换") }
                    Text(filtered ? "匹配 \(visits.count) 次访问" : "\(Set(visits.map(\.key)).count) 个域名 · \(visits.count) 次访问")
                    Text(durationText(session.seconds)).monospacedDigit().foregroundStyle(Palette.ink)
                }.font(.system(size: 11)).foregroundStyle(Palette.muted)
                    .padding(.horizontal, 12).frame(maxWidth: .infinity, minHeight: 38)
                    .background(headerHovered ? Palette.green.opacity(0.05) : .clear)
                    .contentShape(Rectangle())
            }.buttonStyle(.plain).onHover { headerHovered = $0 }
                .accessibilityValue(expanded ? "已展开" : "已折叠")
                .accessibilityHint("展开或收起此时间段的浏览记录")
                .accessibilityIdentifier("browser-session-\(session.id)")
            if expanded {
                if visits.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        Label("该时段没有网页记录", systemImage: "minus.circle").font(.system(size: 12))
                        Text("未连接扩展、无痕窗口或内部页面等情况下，只有应用记录。").font(.system(size: 11))
                    }.foregroundStyle(Palette.muted).padding(.horizontal, 14).padding(.bottom, 12)
                } else {
                    BrowserVisitDetail(timeline: BrowserVisitTimeline(session: session, visits: visits, activeSeconds: activeSeconds,
                                                                     showsGaps: !filtered),
                                       calendar: calendar, mode: mode, scrollProxy: scrollProxy,
                                       selected: $selected, showPageDetails: $showPageDetails)
                        .padding(.horizontal, 12).padding(.bottom, 8)
                }
            }
        }
        .background(highlighted ? Palette.selection : Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay { RoundedRectangle(cornerRadius: 9).strokeBorder(highlighted ? Palette.mint : Palette.line).allowsHitTesting(false) }
    }
}

private struct BrowserVisitAnchor: Hashable {
    let session: Date
    let visit: Int64
}

private struct BrowserVisitDetail: View {
    let timeline: BrowserVisitTimeline
    let calendar: Calendar
    let mode: BrowserDetailMode
    let scrollProxy: ScrollViewProxy?

    @Binding var selected: Int64?
    @Binding var showPageDetails: Bool
    @State private var hovered: Int64?
    @State private var showsSiteColumn = false

    private let timeWidth: CGFloat = 138
    private let siteWidth: CGFloat = 124
    private let columnGap: CGFloat = 10
    private var visits: [ActivitySlice] { timeline.visits }
    private var durationWidth: CGFloat { timeline.interval.duration >= 3600 ? 92 : 58 }

    var body: some View {
        Group {
            if mode == .list { list } else { trace }
        }
        .onGeometryChange(for: Bool.self) { $0.size.width >= 650 } action: { showsSiteColumn = $0 }
        .onChange(of: mode, initial: true) { _, mode in
            hovered = nil
            if mode == .trace && !visits.contains(where: { $0.id == selected }) { selected = visits.first?.id }
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            band { visit in
                selected = visit.id
                showPageDetails = true
                let anchor = BrowserVisitAnchor(session: timeline.interval.start, visit: visit.id)
                DispatchQueue.main.async { scrollProxy?.scrollTo(anchor) }
            }
            timeAxis(overview: true).padding(.bottom, 8)
            HStack(spacing: columnGap) {
                Text("访问时段").frame(width: timeWidth, alignment: .leading)
                Text("页面").padding(.leading, 13).frame(maxWidth: .infinity, alignment: .leading)
                if showsSiteColumn { Text("域名").frame(width: siteWidth, alignment: .leading) }
                Text("停留").frame(width: durationWidth, alignment: .trailing)
                Color.clear.frame(width: 8, height: 1)
            }.font(.system(size: 11)).foregroundStyle(Palette.muted)
                .padding(.horizontal, 6).padding(.bottom, 5)
            Divider()
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(timeline.rows) { row in
                    switch row {
                    case .gap(let gap): gapRow(gap)
                    case .visit(let visit):
                        visitRow(visit).id(BrowserVisitAnchor(session: timeline.interval.start, visit: visit.id))
                    }
                }
            }
        }
    }

    private func visitRow(_ visit: ActivitySlice) -> some View {
        let isSelected = selected == visit.id
        let expanded = isSelected && showPageDetails
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                showPageDetails = !expanded
                selected = visit.id
            } label: {
                HStack(spacing: columnGap) {
                    rangeLabel(visit.start, visit.end)
                    HStack(spacing: 7) {
                        Circle().fill(color(visit.key)).frame(width: 6, height: 6)
                        Text(visit.browserTitle).font(.system(size: 13))
                            .foregroundStyle(Palette.ink).lineLimit(expanded ? nil : 1)
                            .fixedSize(horizontal: false, vertical: true).help(visit.browserTitle)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    if showsSiteColumn {
                        Text(visit.key).lineLimit(1).truncationMode(.middle).help(visit.key)
                            .font(.system(size: 11)).foregroundStyle(Palette.muted)
                            .frame(width: siteWidth, alignment: .leading)
                    }
                    Text(durationText(visit.seconds)).font(.system(size: 12)).monospacedDigit()
                        .frame(width: durationWidth, alignment: .trailing)
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8)).foregroundStyle(Palette.muted).frame(width: 8)
                }.padding(.horizontal, 6).padding(.vertical, 5).frame(maxWidth: .infinity, minHeight: 34)
                    .contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityValue(expanded ? "已展开" : "已折叠")
                .accessibilityIdentifier("browser-row-\(visit.id)")
            if expanded {
                BrowserPageAddress(visit: visit)
                    .padding(.leading, 6 + timeWidth + columnGap + 13).padding(.trailing, 8).padding(.bottom, 8)
            }
        }
        .background(isSelected ? Palette.green.opacity(0.08) : hovered == visit.id ? Palette.background : .clear,
                    in: RoundedRectangle(cornerRadius: 5))
        .onHover { hover($0, visit: visit) }
    }

    private func rangeLabel(_ start: Date, _ end: Date) -> some View {
        Text(browserRange(start, end, calendar: calendar)).font(.system(size: 12)).monospacedDigit()
            .frame(width: timeWidth, alignment: .leading)
    }

    private func gapRow(_ gap: DateInterval) -> some View {
        HStack(spacing: columnGap) {
            rangeLabel(gap.start, gap.end)
            Text("无页面记录 · \(durationText(gap.duration))").font(.system(size: 11)).padding(.leading, 13)
        }.foregroundStyle(Palette.muted).padding(.horizontal, 6).frame(minHeight: 24)
    }

    private var trace: some View {
        let index = visits.firstIndex { $0.id == selected } ?? visits.startIndex
        return VStack(alignment: .leading, spacing: 4) {
            ForEach(timeline.lanes) { lane in
                HStack(spacing: columnGap) {
                    HStack(spacing: 6) {
                        Circle().fill(color(lane.domain)).frame(width: 6, height: 6)
                        Text(lane.domain).font(.system(size: 11)).lineLimit(1).truncationMode(.middle).help(lane.domain)
                    }.frame(width: siteWidth, alignment: .leading)
                    band(lane: lane) { selected = $0.id }
                }
            }
            timeAxis(overview: false).padding(.leading, siteWidth + columnGap)
            if visits.indices.contains(index) {
                Divider().padding(.vertical, 4)
                let visit = visits[index]
                HStack(spacing: 10) {
                    Text(visit.browserTitle).font(.system(size: 13, weight: .medium)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    stepButton("上一次访问", backwards: true, enabled: index > 0) { selected = visits[index - 1].id }
                    Text("\(index + 1) / \(visits.count)").font(.system(size: 11)).monospacedDigit()
                        .foregroundStyle(Palette.muted).accessibilityLabel("第 \(index + 1) 次访问，共 \(visits.count) 次")
                    stepButton("下一次访问", backwards: false, enabled: index + 1 < visits.count) { selected = visits[index + 1].id }
                }
                Text("\(browserRange(visit.start, visit.end, calendar: calendar))  ·  \(durationText(visit.seconds))")
                    .font(.system(size: 12)).monospacedDigit().foregroundStyle(Palette.muted)
                BrowserPageAddress(visit: visit)
            }
        }.padding(.top, 2)
    }

    private func timeAxis(overview: Bool) -> some View {
        let span = timeline.interval
        return HStack {
            Text(browserTime(span.start, calendar: calendar))
            Spacer(minLength: 0)
            if overview && timeline.showsGaps {
                HStack(spacing: 5) {
                    Hatch().frame(width: 14, height: 8)
                    Text("无页面记录")
                }.help("本时段的浏览器使用时间中，有 \(durationText(timeline.missingSeconds)) 未记录网页")
            } else if span.duration >= 4 {
                Text(browserTime(span.start.addingTimeInterval(span.duration / 2), calendar: calendar))
            }
            Spacer(minLength: 0)
            Text(browserTime(span.end, calendar: calendar, ending: true))
        }.font(.system(size: 10)).monospacedDigit().foregroundStyle(Palette.muted)
    }

    private func stepButton(_ label: String, backwards: Bool, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                if backwards { Image(systemName: "chevron.left") }
                Text(backwards ? "上一条" : "下一条")
                if !backwards { Image(systemName: "chevron.right") }
            }.font(.system(size: 11)).foregroundStyle(enabled ? Palette.green : Palette.muted.opacity(0.5))
                .padding(.horizontal, 3).frame(height: 24).contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(!enabled).help(label).accessibilityLabel(label)
    }

    private func color(_ domain: String) -> Color {
        let colors = [Palette.green, Color(red: 0.67, green: 0.38, blue: 0.51), SharePalette.color(slot: 2),
                      Palette.orange, SharePalette.color(slot: 4)]
        return colors[timeline.domainSlots[domain, default: 0] % colors.count]
    }

    private func hover(_ inside: Bool, visit: ActivitySlice) {
        if inside { hovered = visit.id }
        else if hovered == visit.id { hovered = nil }
    }

    private func band(lane: BrowserVisitTimeline.Lane? = nil,
                      select: @escaping (ActivitySlice) -> Void) -> some View {
        let items = lane?.visits ?? visits
        let overview = lane == nil
        return GeometryReader { geometry in
            ZStack(alignment: .leading) {
                if let lane {
                    RoundedRectangle(cornerRadius: 3).fill(Palette.background).frame(height: 16)
                    ForEach(lane.runs, id: \.start) { run in
                        if let span = timeline.fractions(for: run) {
                            RoundedRectangle(cornerRadius: 2).fill(color(lane.domain).opacity(0.65))
                                .frame(width: geometry.size.width * (span.upperBound - span.lowerBound), height: 13)
                                .offset(x: geometry.size.width * span.lowerBound)
                                .allowsHitTesting(false).accessibilityHidden(true)
                        }
                    }
                } else if timeline.showsGaps {
                    Hatch().frame(height: 11)
                } else {
                    RoundedRectangle(cornerRadius: 2).fill(Palette.background).frame(height: 11)
                }
                ForEach(items) { visit in
                    if let span = timeline.fractions(for: visit) {
                        let x = geometry.size.width * span.lowerBound
                        let width = geometry.size.width * (span.upperBound - span.lowerBound)
                        let focused = selected == visit.id || hovered == visit.id
                        Button { select(visit) } label: {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(color(visit.key).opacity(focused ? 1 : (overview ? 0.65 : 0)))
                                .frame(height: overview ? 11 : 13)
                                .background(overview ? Color.white : .clear, in: RoundedRectangle(cornerRadius: 2))
                                .frame(width: width, height: 24).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                            .accessibilityLabel("\(visit.browserTitle)，\(browserRange(visit.start, visit.end, calendar: calendar))")
                            .accessibilityAddTraits(selected == visit.id ? .isSelected : [])
                            .accessibilityIdentifier("browser-\(overview ? "ribbon" : "lane")-\(visit.id)")
                            .help("\(visit.browserTitle) · \(durationText(visit.seconds))")
                            .onHover { hover($0, visit: visit) }
                            .offset(x: x)
                    }
                }
                if let visit = items.first(where: { $0.id == selected }) {
                    let range = lane?.runs.first { $0.start <= visit.start && visit.start < $0.end }
                        ?? DateInterval(start: visit.start, end: visit.end)
                    if let span = timeline.fractions(for: range) {
                        selectionOutline(span: span, trackWidth: geometry.size.width, height: overview ? 19 : 21)
                    }
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }.frame(height: 24)
    }

    private func selectionOutline(span: Range<Double>, trackWidth: CGFloat, height: CGFloat) -> some View {
        // Keep the outline visible for subpixel visits without widening their time spans or hit targets.
        let width = min(trackWidth + 8, max(14, trackWidth * (span.upperBound - span.lowerBound) + 8))
        let center = trackWidth * (span.lowerBound + span.upperBound) / 2
        let outline = RoundedRectangle(cornerRadius: 4)
        return outline.strokeBorder(.white, lineWidth: 4)
            .overlay { outline.strokeBorder(Palette.ink, lineWidth: 2) }
            .frame(width: width, height: height)
            .offset(x: min(max(-4, center - width / 2), trackWidth + 4 - width))
            .allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct BrowserPageAddress: View {
    let visit: ActivitySlice
    var body: some View {
        if let url = visit.pageURL {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(url).font(.system(size: 11)).foregroundStyle(Palette.green)
                    .textSelection(.enabled).lineLimit(1).truncationMode(.middle).help(url)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url, forType: .string)
                } label: { Image(systemName: "doc.on.doc") }
                .buttonStyle(.plain).foregroundStyle(Palette.muted)
                .help("复制页面地址").accessibilityLabel("复制页面地址")
            }.frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text("历史域名记录，当时未记录页面标题和地址").font(.system(size: 11)).foregroundStyle(Palette.muted)
        }
    }
}

private extension ActivitySlice {
    var browserTitle: String {
        guard let pageTitle, !pageTitle.isEmpty else { return pageURL == nil ? key : "未提供页面标题" }
        return PageTitle.display(pageTitle)
    }
}

func browserRange(_ start: Date, _ end: Date, calendar: Calendar) -> String {
    "\(browserTime(start, calendar: calendar)) – \(browserTime(end, calendar: calendar, ending: true))"
}

func browserTime(_ date: Date, calendar: Calendar, ending: Bool = false) -> String {
    if ending && date == calendar.startOfDay(for: date) { return "24:00:00" }
    return date.formatted(Date.FormatStyle(locale: Locale(identifier: "zh_CN"), calendar: calendar, timeZone: calendar.timeZone)
        .hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits))
}
