import SwiftUI
import MonitorCore

struct BrowserAnalysisView: View {
    @EnvironmentObject private var model: MonitorModel
    let scrollProxy: ScrollViewProxy

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("浏览器分析").font(.system(size: 30, weight: .semibold))
                Spacer()
                ChromeConnectionNotice()
            }
            ReportPicker()
            if let report = model.browserReport, !report.visits.isEmpty {
                BrowserReportContent(report: report, scrollProxy: scrollProxy)
                    .id(report.chrome.interval)
            } else {
                ContentUnavailableView("所选时段没有网页记录", systemImage: "globe", description:
                    Text(model.browserReportError ?? "可以切换日期，或连接 Chrome 扩展后浏览普通网页。"))
                if let report = model.browserReport, !report.chrome.days.isEmpty {
                    BrowserHistoryView(report: report, site: nil, bucket: .constant(nil), scrollProxy: scrollProxy)
                        .id(report.chrome.interval)
                }
            }
        }
    }
}

/// Holds the selection shared by the rankings, the chart and the history list.
private struct BrowserReportContent: View {
    let report: BrowserReport
    let scrollProxy: ScrollViewProxy
    @State private var selectedSite: String?
    @State private var bucket: Date?

    var body: some View {
        let site = report.sites.first { $0.id == selectedSite } ?? BrowserMetric.duration.ranked(report.sites).first
        VStack(alignment: .leading, spacing: 16) {
            BrowserSummaryTiles(report: report)
            BrowserRankings(report: report, focus: site, selectedSite: $selectedSite, bucket: $bucket)
            BrowserRhythm(report: report, site: site, bucket: $bucket)
            BrowserHistoryView(report: report, site: site, bucket: $bucket, scrollProxy: scrollProxy)
            Text("网站按可注册域名合并子域名。同一页面连续停留记为一次访问，切走后再回来另计一次。标题中的邮箱地址和验证码仅在显示时隐藏。")
                .font(.caption).foregroundStyle(Palette.muted)
        }
    }
}

// MARK: - Summary

private struct BrowserSummaryTiles: View {
    let report: BrowserReport

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) { primary; secondary }.fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 12) {
                HStack(alignment: .top, spacing: 12) { primary }.fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .top, spacing: 12) { secondary }.fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private var primary: some View {
        tile("网页停留", durationText(report.seconds), lead: true) {
            if report.hasComparison {
                let change = changeText(report.seconds, report.previousSeconds)
                Text(report.comparisonLabel + " ") + Text(change.text).fontWeight(.semibold)
            }
            if let coverage = report.chromeCoverage {
                Text("占 Chrome 前台 \(UsageShare.percentText(coverage))")
            }
        }
        tile("访问的网站", "\(report.sites.count) 个") {
            Text("\(report.hosts.count) 个域名 · \(report.pages.count) 个页面")
        }
    }

    @ViewBuilder private var secondary: some View {
        tile("平均单次停留", durationText(report.averageVisitSeconds)) {
            Text("共 \(report.visits.count) 次访问")
        }
        tile("最长连续停留", durationText(report.longestVisit?.seconds ?? 0)) {
            if let longest = report.longestVisit {
                Text(visitTitle(longest)).lineLimit(1).truncationMode(.middle).help(visitTitle(longest))
                Text(visitRangeText(longest, period: report.chrome.period, calendar: report.chrome.calendar))
                    .monospacedDigit()
            }
        }
    }

    private func tile<Detail: View>(_ label: String, _ value: String, lead: Bool = false,
                                    @ViewBuilder detail: () -> Detail) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 12, weight: .medium)).opacity(lead ? 0.85 : 1)
                .foregroundStyle(lead ? Color.white : Palette.muted)
            Text(value).font(.system(size: 22, weight: .semibold)).monospacedDigit()
                .lineLimit(1).fixedSize()
                .foregroundStyle(lead ? Color.white : Palette.ink)
            VStack(alignment: .leading, spacing: 1) { detail() }
                .font(.system(size: 12)).foregroundStyle(lead ? Color.white.opacity(0.88) : Palette.ink.opacity(0.78))
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(lead ? Palette.green : .white, in: RoundedRectangle(cornerRadius: 12))
        .overlay { if !lead { RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.line) } }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Rankings and site detail

private struct BrowserRankings: View {
    let report: BrowserReport
    let focus: BrowserGroup?
    @Binding var selectedSite: String?
    @Binding var bucket: Date?
    @State private var level: BrowserLevel = .site
    @State private var metric: BrowserMetric = .duration
    @State private var rankLimit = 8
    @State private var openPage: String?
    @State private var hovered: String?

    var body: some View {
        let span = report.buckets.first { $0.id == bucket }?.interval
        let ranked = metric.ranked(report.groups(at: level, within: span))
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { title(span); Spacer(minLength: 8); controls }
                    VStack(alignment: .leading, spacing: 8) { title(span); controls }
                }
                if ranked.isEmpty {
                    Text(level == .page ? "这个时段只有域名记录。" : "这个时段没有网页记录。")
                        .font(.caption).foregroundStyle(Palette.muted).padding(.vertical, 8)
                } else {
                    let maximum = metric.value(ranked[0]), total = ranked.reduce(0) { $0 + $1.seconds }
                    VStack(spacing: 2) {
                        ForEach(ranked.prefix(rankLimit)) { row($0, maximum: maximum, total: total, filtered: span != nil) }
                    }
                    if ranked.count > rankLimit {
                        textButton("显示更多（共 \(ranked.count) 项）") { rankLimit += 20 }
                    } else if rankLimit > 8 {
                        textButton("收起") { rankLimit = 8 }
                    }
                }
                if level == .page && span == nil && report.unaddressedSeconds > 0 {
                    Text("另有 \(durationText(report.unaddressedSeconds)) 仅记录了域名。")
                        .font(.caption).foregroundStyle(Palette.muted)
                }
            }.padding(16).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Rectangle().fill(Palette.line).frame(width: 1)
            Group {
                if let focus { BrowserSiteDetail(report: report, site: focus).id(focus.id) }
            }.padding(16).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Palette.background.opacity(0.5))
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(.white).clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.line))
        .onChange(of: level) { _, _ in rankLimit = 8; openPage = nil }
        .onChange(of: metric) { _, _ in rankLimit = 8 }
        .onChange(of: bucket) { _, _ in rankLimit = 8 }
    }

    private func title(_ span: DateInterval?) -> some View {
        HStack(spacing: 8) {
            sectionTitle("浏览排行")
            if let span {
                FilterChip(text: bucketText(span, period: report.chrome.period, calendar: report.chrome.calendar)) { bucket = nil }
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            SegmentedControl(options: BrowserLevel.allCases, selection: $level, compact: true, title: \.rawValue,
                             identifier: { "browser-level-\($0 == .site ? "site" : "page")" })
            SegmentedControl(options: BrowserMetric.allCases, selection: $metric, compact: true,
                             title: { $0 == .duration ? "按时长" : "按次数" })
        }
    }

    private func row(_ group: BrowserGroup, maximum: Double, total: Double, filtered: Bool) -> some View {
        let site = level == .site ? group.id : report.site(of: group.visits[0])
        let selected = level == .site ? site == focus?.id : openPage == group.id
        let subtitle = level == .site ? (group.title == group.id ? nil : group.id) : group.visits[0].key
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                selectedSite = site
                if level == .page { openPage = openPage == group.id ? nil : group.id }
            } label: {
                HStack(spacing: 10) {
                    SiteAvatar(site: site, size: 28)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(group.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.ink)
                                .lineLimit(1).truncationMode(.middle).layoutPriority(1)
                            if let subtitle {
                                Text(subtitle).font(.system(size: 11)).foregroundStyle(Palette.muted)
                                    .lineLimit(1).truncationMode(.middle)
                            }
                            Spacer(minLength: 6)
                            Text(metric.label(group)).font(.system(size: 13, weight: .semibold)).monospacedDigit().fixedSize()
                        }
                        HStack(spacing: 10) {
                            Meter(fraction: maximum > 0 ? metric.value(group) / maximum : 0,
                                  track: selected ? .white : Palette.sunk)
                            secondary(group, total: total, filtered: filtered)
                                .font(.system(size: 11)).monospacedDigit().foregroundStyle(Palette.muted).fixedSize()
                        }
                    }
                }.padding(.horizontal, 10).padding(.vertical, 8).contentShape(Rectangle())
            }.buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("browser-rank-\(group.id)")
                .help(group.id)
            if level == .page && selected {
                VStack(alignment: .leading, spacing: 6) {
                    BrowserVisitList(visits: group.visits, period: report.chrome.period, calendar: report.chrome.calendar)
                    if let visit = group.visits.first { BrowserPageAddress(visit: visit) }
                }.padding(.leading, 48).padding(.trailing, 10).padding(.bottom, 10)
            }
        }
        .background(selected ? Palette.selection : hovered == group.id ? Palette.background : .clear,
                    in: RoundedRectangle(cornerRadius: 9))
        .overlay { if selected { RoundedRectangle(cornerRadius: 9).strokeBorder(Palette.mint) } }
        .onHover { inside in
            if inside { hovered = group.id } else if hovered == group.id { hovered = nil }
        }
    }

    private func secondary(_ group: BrowserGroup, total: Double, filtered: Bool) -> Text {
        let other = metric == .duration ? "\(group.visits.count) 次" : durationText(group.seconds)
        if filtered {
            return Text("\(other) · 占该时段 \(UsageShare.percentText(total > 0 ? group.seconds / total : 0))")
        }
        guard level == .site, report.hasComparison else { return Text(other) }
        let change = changeText(group.seconds, report.previousSites[group.id] ?? 0)
        return Text(other + " · ") + Text(change.text).foregroundStyle(change.color)
    }
}

private struct BrowserSiteDetail: View {
    let report: BrowserReport
    let site: BrowserGroup
    @State private var openPage: String?
    @State private var limit = 6

    var body: some View {
        let pages = BrowserMetric.duration.ranked(BrowserReport.pageGroups(in: site.visits, includingUnaddressed: true))
        let hosts = report.hosts(inSite: site.id)
        let rank = (BrowserMetric.duration.ranked(report.sites).firstIndex { $0.id == site.id } ?? 0) + 1
        let hidden = pages.filter { page in
            guard let raw = page.visits.reversed().compactMap(\.pageTitle).first(where: { !$0.isEmpty }) else { return false }
            return PageTitle.display(raw) != raw
        }.count
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                SiteAvatar(site: site.id, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(site.title).font(.system(size: 18, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                    Text("\(site.id) · 占网页时长 \(UsageShare.percentText(report.seconds > 0 ? site.seconds / report.seconds : 0)) · 第 \(rank) 名")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted).textSelection(.enabled)
                }
            }
            Grid(horizontalSpacing: 1, verticalSpacing: 1) {
                GridRow {
                    stat("停留", durationText(site.seconds), change: report.hasComparison
                         ? changeText(site.seconds, report.previousSites[site.id] ?? 0) : nil)
                    stat("访问", "\(site.visits.count) 次")
                }
                GridRow {
                    stat("平均单次", durationText(site.seconds / Double(max(1, site.visits.count))))
                    stat("最长连续", durationText(site.visits.map(\.seconds).max() ?? 0))
                }
            }.background(Palette.line).clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.line))
            VStack(alignment: .leading, spacing: 6) {
                label(report.chrome.period == .day ? "时段分布" : "每日分布")
                BrowserMiniBars(buckets: report.buckets, site: site.id, period: report.chrome.period, calendar: report.chrome.calendar)
            }
            if hosts.count > 1 {
                VStack(alignment: .leading, spacing: 6) {
                    label("子域名 · \(hosts.count) 个")
                    FlowLayout(spacing: 6) {
                        ForEach(hosts) { host in
                            HStack(spacing: 5) {
                                Text(host.id).foregroundStyle(Palette.ink.opacity(0.8))
                                Text(durationText(host.seconds)).fontWeight(.semibold).monospacedDigit()
                            }.font(.system(size: 11)).padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Palette.sunk, in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                label("页面 · \(pages.count) 个").padding(.bottom, 4)
                ForEach(pages.prefix(limit)) { page in pageRow(page, showsHost: hosts.count > 1) }
                if pages.count > limit {
                    textButton("显示更多（共 \(pages.count) 项）") { limit += 20 }.padding(.top, 6)
                }
            }
            if hidden > 0 {
                Label("已隐藏 \(hidden) 个标题中的邮箱地址或验证码", systemImage: "eye.slash")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
            }
        }
    }

    private func stat(_ title: String, _ value: String, change: (text: String, color: Color)? = nil) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.system(size: 14, weight: .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
            HStack(spacing: 4) {
                Text(title).foregroundStyle(Palette.muted)
                if let change { Text(change.text).foregroundStyle(change.color) }
            }.font(.system(size: 11))
        }.padding(.horizontal, 10).padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading).background(.white)
    }

    private func label(_ text: String) -> some View {
        Text(text).font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.muted)
    }

    private func pageRow(_ page: BrowserGroup, showsHost: Bool) -> some View {
        let open = openPage == page.id
        return VStack(alignment: .leading, spacing: 6) {
            Button {
                openPage = open ? nil : page.id
            } label: {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(page.title).font(.system(size: 13)).foregroundStyle(Palette.ink)
                            .lineLimit(open ? 3 : 1).truncationMode(.middle)
                        Text((showsHost ? page.visits[0].key + " · " : "") + "\(page.visits.count) 次访问")
                            .font(.system(size: 11)).foregroundStyle(Palette.muted).lineLimit(1)
                    }
                    Spacer(minLength: 6)
                    Text(durationText(page.seconds)).font(.system(size: 12, weight: .semibold)).monospacedDigit().fixedSize()
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(Palette.muted)
                        .rotationEffect(.degrees(open ? 90 : 0))
                }.padding(.vertical, 8).contentShape(Rectangle())
            }.buttonStyle(.plain).help(page.title)
                .accessibilityValue(open ? "已展开" : "已折叠")
            if open {
                VStack(alignment: .leading, spacing: 6) {
                    BrowserVisitList(visits: page.visits, period: report.chrome.period, calendar: report.chrome.calendar)
                    if let visit = page.visits.first { BrowserPageAddress(visit: visit) }
                }.padding(10).background(Palette.sunk.opacity(0.7), in: RoundedRectangle(cornerRadius: 8)).padding(.bottom, 8)
            }
        }.overlay(alignment: .top) { Rectangle().fill(Palette.line).frame(height: 1) }
    }
}

/// Chronological stays on one page, shown under an expanded page row.
private struct BrowserVisitList: View {
    let visits: [ActivitySlice]
    let period: ReportPeriod
    let calendar: Calendar
    @State private var limit = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(visits.prefix(limit)) { visit in
                HStack {
                    Text(visitRangeText(visit, period: period, calendar: calendar))
                    Spacer(minLength: 8)
                    Text(durationText(visit.seconds)).fixedSize()
                }.font(.system(size: 12)).monospacedDigit().foregroundStyle(Palette.ink.opacity(0.85))
            }
            if visits.count > limit {
                textButton("还有 \(visits.count - limit) 次访问") { limit += 30 }
            }
        }
    }
}

private struct BrowserMiniBars: View {
    let buckets: [BrowserBucket]
    let site: String
    let period: ReportPeriod
    let calendar: Calendar

    var body: some View {
        let values = buckets.map { bucket in bucket.sites.first { $0.key == site }?.seconds ?? 0 }
        let peak = values.max() ?? 0
        VStack(spacing: 3) {
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(Array(buckets.enumerated()), id: \.element.id) { index, bucket in
                    let value = values[index]
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(value > 0 ? Palette.green : Palette.line)
                        .frame(height: value > 0 && peak > 0 ? max(3, 40 * value / peak) : 2)
                        .frame(maxWidth: .infinity)
                        .help("\(bucketText(bucket.interval, period: period, calendar: calendar)) · \(durationText(value))")
                }
            }.frame(height: 40, alignment: .bottom)
            HStack {
                if period == .day {
                    ForEach([0, 6, 12, 18, 24], id: \.self) { hour in
                        Text("\(hour)")
                        if hour < 24 { Spacer(minLength: 0) }
                    }
                } else if let first = buckets.first, let last = buckets.last {
                    Text(dayText(first.interval.start, calendar: calendar))
                    Spacer(minLength: 0)
                    Text(dayText(last.interval.start, calendar: calendar))
                }
            }.font(.system(size: 10)).monospacedDigit().foregroundStyle(Palette.muted)
        }.accessibilityElement(children: .ignore)
            .accessibilityLabel("\(period == .day ? "各小时" : "每天")的停留分布，最高 \(durationText(peak))")
    }
}

// MARK: - Rhythm chart

private struct BrowserRhythm: View {
    let report: BrowserReport
    let site: BrowserGroup?
    @Binding var bucket: Date?
    @State private var hovered: Date?
    private let chartHeight: CGFloat = 140
    private let axisWidth: CGFloat = 46

    var body: some View {
        let buckets = report.buckets
        let peak = buckets.max { $0.seconds < $1.seconds }
        let top = niceCeiling(peak?.seconds ?? 0)
        let focus = buckets.first { $0.id == (hovered ?? bucket) } ?? peak
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                sectionTitle(report.chrome.period == .day ? "浏览时段" : "每日浏览")
                Spacer()
                legend(Palette.mint, "全部网页")
                if let site { legend(Palette.green, site.title) }
            }
            HStack(alignment: .top, spacing: 0) {
                ZStack(alignment: .topTrailing) {
                    ForEach([1.0, 0.5, 0], id: \.self) { fraction in
                        Text(fraction == 0 ? "0" : axisText(top * fraction))
                            .font(.system(size: 10)).monospacedDigit().foregroundStyle(Palette.muted)
                            .offset(x: -6, y: chartHeight * (1 - fraction) - 6)
                    }
                }.frame(width: axisWidth, height: chartHeight, alignment: .topTrailing)
                VStack(spacing: 6) {
                    ZStack(alignment: .bottom) {
                        VStack(spacing: 0) {
                            gridLine(dashed: true); Spacer(); gridLine(dashed: true); Spacer(); gridLine(dashed: false)
                        }
                        HStack(alignment: .bottom, spacing: 3) {
                            ForEach(buckets) { item in bar(item, top: top) }
                        }
                    }.frame(height: chartHeight)
                    HStack(spacing: 3) {
                        ForEach(buckets) { item in
                            Text(axisLabel(item, first: item.id == buckets.first?.id))
                                .font(.system(size: 10)).monospacedDigit().foregroundStyle(Palette.muted)
                                .lineLimit(1).fixedSize().frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            Rectangle().fill(Palette.line).frame(height: 1)
            if let focus { tip(focus, isPeak: focus.id == peak?.id && bucket == nil && hovered == nil) }
        }.padding(16).background(.white, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.line))
    }

    private func bar(_ item: BrowserBucket, top: Double) -> some View {
        let selected = bucket == item.id
        let siteSeconds = site.flatMap { site in item.sites.first { $0.key == site.id }?.seconds } ?? 0
        let label = bucketText(item.interval, period: report.chrome.period, calendar: report.chrome.calendar)
        return Button {
            bucket = selected ? nil : item.id
        } label: {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 3).fill(Palette.mint)
                    .frame(height: height(item.seconds, top: top))
                RoundedRectangle(cornerRadius: 3).fill(Palette.green)
                    .frame(height: siteSeconds > 0 ? max(2, height(siteSeconds, top: top)) : 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.top, 4)
            .background(selected ? Palette.selection : hovered == item.id ? Palette.background : .clear,
                        in: RoundedRectangle(cornerRadius: 4))
            .overlay { if selected { RoundedRectangle(cornerRadius: 4).strokeBorder(Palette.mint) } }
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
            .onHover { inside in
                if inside { hovered = item.id } else if hovered == item.id { hovered = nil }
            }
            .help("\(label) · \(durationText(item.seconds))")
            .accessibilityLabel("\(label)，\(durationText(item.seconds))")
            .accessibilityHint(selected ? "取消时段筛选" : "只看这个时段的排行和浏览记录")
            .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func height(_ seconds: Double, top: Double) -> CGFloat {
        guard top > 0, seconds > 0 else { return 0 }
        return max(1, (chartHeight - 4) * seconds / top)
    }

    private func tip(_ item: BrowserBucket, isPeak: Bool) -> some View {
        let label = bucketText(item.interval, period: report.chrome.period, calendar: report.chrome.calendar)
        let sites = item.sites.prefix(4).map { "\($0.name) \(durationText($0.seconds))" }
        var text = Text((isPeak ? "高峰 " : "") + label).fontWeight(.semibold).foregroundStyle(Palette.ink)
            + Text(" · \(durationText(item.seconds))" + (sites.isEmpty ? " · 没有网页记录" : " · " + sites.joined(separator: " · ")))
        if bucket == nil { text = text + Text("　点击柱子可按时段筛选排行和浏览记录").foregroundStyle(Palette.muted.opacity(0.8)) }
        else if bucket == item.id { text = text + Text("　再次点击取消筛选").foregroundStyle(Palette.muted.opacity(0.8)) }
        return text.font(.system(size: 12)).foregroundStyle(Palette.ink.opacity(0.8)).lineLimit(2)
    }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            Text(text).lineLimit(1)
        }.font(.system(size: 12)).foregroundStyle(Palette.ink.opacity(0.8))
    }

    private func gridLine(dashed: Bool) -> some View {
        Rectangle().fill(.clear).frame(height: 1).overlay {
            GeometryReader { geometry in
                Path { path in
                    path.move(to: .zero)
                    path.addLine(to: CGPoint(x: geometry.size.width, y: 0))
                }.stroke(Palette.line, style: StrokeStyle(lineWidth: 1, dash: dashed ? [3, 3] : []))
            }
        }
    }

    private func axisLabel(_ item: BrowserBucket, first: Bool) -> String {
        let calendar = report.chrome.calendar
        switch report.chrome.period {
        case .day:
            let hour = calendar.component(.hour, from: item.id)
            return hour % 3 == 0 || first ? "\(hour)" : ""
        case .week:
            return dayText(item.id, calendar: calendar)
        case .month:
            let day = calendar.component(.day, from: item.id)
            return day == 1 || day % 5 == 0 ? "\(day)" : ""
        }
    }

    private func niceCeiling(_ seconds: Double) -> Double {
        let steps: [Double] = [600, 1200, 1800, 2400, 3600, 7200, 10800, 14400, 21600, 28800, 43200, 57600, 86400]
        return steps.first { $0 >= seconds } ?? (seconds / 3600).rounded(.up) * 3600
    }

    private func axisText(_ seconds: Double) -> String {
        if seconds < 3600 { return "\(Int(seconds / 60)) 分" }
        let hours = seconds / 3600
        return hours == hours.rounded() ? "\(Int(hours)) 小时" : String(format: "%.1f 小时", hours)
    }
}

// MARK: - Shared pieces

/// Site initial on a tinted square. The tint is stable per site so the same site keeps its color everywhere.
struct SiteAvatar: View {
    let site: String
    var size: CGFloat = 28

    static let tints: [(fill: Color, ink: Color)] = [
        (Color(red: 0.875, green: 0.914, blue: 0.953), Color(red: 0.17, green: 0.33, blue: 0.47)),
        (Color(red: 0.953, green: 0.894, blue: 0.855), Color(red: 0.54, green: 0.29, blue: 0.15)),
        (Color(red: 0.902, green: 0.886, blue: 0.949), Color(red: 0.33, green: 0.27, blue: 0.54)),
        (Color(red: 0.945, green: 0.925, blue: 0.812), Color(red: 0.44, green: 0.36, blue: 0.07)),
        (Color(red: 0.863, green: 0.937, blue: 0.910), Color(red: 0.12, green: 0.40, blue: 0.31)),
        (Color(red: 0.949, green: 0.875, blue: 0.894), Color(red: 0.54, green: 0.21, blue: 0.31)),
    ]

    static func slot(_ site: String) -> Int {
        var hash: UInt32 = 5381
        for byte in site.utf8 { hash = hash &* 33 &+ UInt32(byte) }
        return Int(hash % UInt32(tints.count))
    }

    static func ink(_ site: String) -> Color { tints[slot(site)].ink }

    var body: some View {
        let tint = Self.tints[Self.slot(site)]
        let title = BrowserReport.siteTitle(site)
        Text(title.first { $0.isLetter || $0.isNumber }.map { String($0).uppercased() } ?? "?")
            .font(.system(size: size * 0.44, weight: .bold)).foregroundStyle(tint.ink)
            .frame(width: size, height: size)
            .background(tint.fill, in: RoundedRectangle(cornerRadius: size * 0.27))
            .accessibilityHidden(true)
    }
}

struct FilterChip: View {
    let text: String
    let clear: () -> Void

    var body: some View {
        HStack(spacing: 3) {
            Text(text).font(.system(size: 12, weight: .semibold)).monospacedDigit()
            Button(action: clear) {
                Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).frame(width: 16, height: 16).contentShape(Circle())
            }.buttonStyle(.plain).help("清除时段筛选").accessibilityLabel("清除时段筛选")
        }.foregroundStyle(Palette.green).padding(.leading, 9).padding(.trailing, 3).padding(.vertical, 2)
            .background(Palette.selection, in: Capsule()).overlay(Capsule().strokeBorder(Palette.mint))
            .fixedSize()
    }
}

private struct Meter: View {
    let fraction: Double
    let track: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule().fill(Palette.green).frame(width: max(3, geometry.size.width * min(1, fraction)))
            }
        }.frame(height: 4).accessibilityHidden(true)
    }
}

/// Wraps children onto new lines, left to right.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        return CGSize(width: rows.map(\.width).max() ?? 0, height: rows.last.map { $0.y + $0.height } ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.items {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row { var items: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0; var y: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !rows[rows.count - 1].items.isEmpty && rows[rows.count - 1].width + spacing + size.width > width {
                let last = rows[rows.count - 1]
                rows.append(Row(y: last.y + last.height + spacing))
            }
            var row = rows[rows.count - 1]
            row.width += (row.items.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.items.append(index)
            rows[rows.count - 1] = row
        }
        return rows.filter { !$0.items.isEmpty }
    }
}

func sectionTitle(_ title: String) -> some View {
    Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.ink)
}

func textButton(_ title: String, action: @escaping () -> Void) -> some View {
    Button(title, action: action).buttonStyle(.plain).font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.green)
}

/// "↑ 12 分钟" style change against a comparison value; under a minute reads as no change.
func changeText(_ current: Double, _ previous: Double) -> (text: String, color: Color) {
    let difference = current - previous
    if abs(difference) < 60 { return ("持平", Palette.muted) }
    return ((difference > 0 ? "↑ " : "↓ ") + durationText(abs(difference)), difference > 0 ? Palette.increase : Palette.decrease)
}

func visitTitle(_ visit: ActivitySlice) -> String {
    guard let title = visit.pageTitle, !title.isEmpty else { return visit.pageURL == nil ? visit.key : "未提供页面标题" }
    return PageTitle.display(title)
}

func visitRangeText(_ visit: ActivitySlice, period: ReportPeriod, calendar: Calendar) -> String {
    let range = timelineTime(visit.start, calendar: calendar) + "–" + clockEnd(visit.end, calendar: calendar)
    guard period != .day else { return range }
    let endDay = visit.end == calendar.startOfDay(for: visit.end) ? visit.end.addingTimeInterval(-1) : visit.end
    if !calendar.isDate(visit.start, inSameDayAs: endDay) {
        return "\(dayText(visit.start, calendar: calendar)) \(timelineTime(visit.start, calendar: calendar)) – \(dayText(endDay, calendar: calendar)) \(clockEnd(visit.end, calendar: calendar))"
    }
    return dayText(visit.start, calendar: calendar) + " " + range
}

func bucketText(_ interval: DateInterval, period: ReportPeriod, calendar: Calendar) -> String {
    guard period == .day else { return dayText(interval.start, calendar: calendar) }
    return timelineTime(interval.start, calendar: calendar) + "–" + clockEnd(interval.end, calendar: calendar)
}

private func clockEnd(_ date: Date, calendar: Calendar) -> String {
    date == calendar.startOfDay(for: date) ? "24:00" : timelineTime(date, calendar: calendar)
}

func dayText(_ date: Date, calendar: Calendar) -> String {
    date.formatted(Date.FormatStyle(locale: Locale(identifier: "zh_CN"), calendar: calendar, timeZone: calendar.timeZone).month().day())
}
