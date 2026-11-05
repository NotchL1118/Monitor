import AppKit
import SwiftUI
import MonitorCore

/// Consecutive visits to the same host form one expandable group; return visits stay chronological.
struct BrowserVisitGroup: Identifiable {
    var id: Int64 { visits[0].id }
    var domain: String { visits[0].key }
    var visits: [ActivitySlice]
    var seconds: Double { visits.reduce(0) { $0 + $1.seconds } }

    static func groups(_ visits: [ActivitySlice]) -> [BrowserVisitGroup] {
        var groups: [BrowserVisitGroup] = []
        for visit in visits {
            if let last = groups.last, last.domain == visit.key,
               abs(last.visits.last!.end.timeIntervalSince(visit.start)) < 0.001 {
                groups[groups.count - 1].visits.append(visit)
            } else { groups.append(BrowserVisitGroup(visits: [visit])) }
        }
        return groups
    }
}

struct BrowserSessionView: View {
    let session: ActivitySlice
    let visits: [ActivitySlice]
    let calendar: Calendar
    let highlighted: Bool
    @State private var expanded: Bool

    /// Recorded Chrome time inside a merged block; the span itself also covers brief switches away.
    let activeSeconds: Double
    let interruptions: Int

    init(session: ActivitySlice, visits: [ActivitySlice], calendar: Calendar, activeSeconds: Double? = nil, interruptions: Int = 0,
         initiallyExpanded: Bool = false, highlighted: Bool = false) {
        self.session = session; self.visits = visits; self.calendar = calendar
        self.activeSeconds = min(activeSeconds ?? session.seconds, session.seconds); self.interruptions = interruptions
        self.highlighted = highlighted
        _expanded = State(initialValue: initiallyExpanded)
    }

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(BrowserVisitGroup.groups(visits)) { group in
                    BrowserDomainView(group: group, calendar: calendar)
                }
                let missing = max(0, activeSeconds - visits.reduce(0) { $0 + $1.seconds })
                if visits.isEmpty || missing >= 1 {
                    Label(visits.isEmpty ? "该时段没有网页记录" : "另有 \(durationText(missing)) 未记录网页",
                          systemImage: "minus.circle")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                    Text("未连接扩展、无痕窗口或内部页面等情况下，只有应用记录。")
                        .font(.system(size: 10)).foregroundStyle(Palette.muted)
                }
            }.padding(.top, 12).padding(.leading, 6)
        } label: {
            HStack(spacing: 10) {
                Text("\(time(session.start)) – \(time(session.end))")
                    .font(.system(size: 12, design: .monospaced))
                Spacer()
                Text(durationText(session.seconds)).font(.system(size: 11, weight: .medium))
                if interruptions > 0 {
                    Text("含 \(interruptions) 次短暂切换").font(.system(size: 10)).foregroundStyle(Palette.muted)
                }
                Text("\(Set(visits.map(\.key)).count) 个网站").font(.system(size: 10)).foregroundStyle(Palette.muted)
            }.padding(.vertical, 5)
        }.tint(Palette.green).padding(14)
            .background(highlighted ? Palette.green.opacity(0.08) : Palette.background.opacity(0.65), in: RoundedRectangle(cornerRadius: 10))
    }

    private func time(_ date: Date) -> String {
        date == calendar.startOfDay(for: date) && date > session.start ? "24:00:00" : browserTime(date, calendar: calendar)
    }
}

private struct BrowserDomainView: View {
    let group: BrowserVisitGroup
    let calendar: Calendar
    @State private var expanded = true

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(group.visits) { visit in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: visit.pageURL == nil ? "globe" : "doc.text")
                                .foregroundStyle(Palette.muted).padding(.top, 1)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(visit.pageTitle ?? (visit.pageURL == nil ? "历史域名记录" : "未提供页面标题"))
                                    .font(.system(size: 12, weight: .medium)).lineLimit(2).textSelection(.enabled)
                                if let url = visit.pageURL {
                                    Text(url).font(.system(size: 10)).foregroundStyle(Palette.muted)
                                        .lineLimit(2).textSelection(.enabled).help(url)
                                } else {
                                    Text("当时未记录页面标题和地址").font(.system(size: 10)).foregroundStyle(Palette.muted)
                                }
                                Text("\(browserTime(visit.start, calendar: calendar)) – \(browserTime(visit.end, calendar: calendar))")
                                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.muted)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            VStack(alignment: .trailing, spacing: 7) {
                                Text(durationText(visit.seconds)).font(.system(size: 11)).fixedSize()
                                if let url = visit.pageURL {
                                    Button {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(url, forType: .string)
                                    } label: { Image(systemName: "doc.on.doc").font(.system(size: 10)) }
                                        .buttonStyle(.plain).foregroundStyle(Palette.muted).help("复制页面地址")
                                }
                            }
                        }.padding(.vertical, 12)
                        if visit.id != group.visits.last?.id { Divider().opacity(0.35) }
                    }
                }
            }.padding(.leading, 10)
        } label: {
            HStack {
                Label(group.domain, systemImage: "globe").font(.system(size: 12, weight: .medium))
                Spacer()
                Text(durationText(group.seconds)).font(.system(size: 11)).foregroundStyle(Palette.muted)
            }.padding(.vertical, 6)
        }.padding(.horizontal, 12).padding(.vertical, 6)
            .background(.white, in: RoundedRectangle(cornerRadius: 8))
    }
}

private func browserTime(_ date: Date, calendar: Calendar) -> String {
    date.formatted(Date.FormatStyle(locale: Locale(identifier: "zh_CN"), calendar: calendar, timeZone: calendar.timeZone)
        .hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits))
}
