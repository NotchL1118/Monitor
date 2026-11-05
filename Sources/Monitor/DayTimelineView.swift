import SwiftUI
import MonitorCore

struct DayTimelineView: View {
    @EnvironmentObject private var model: MonitorModel
    @State private var hoursPerLane = 4
    @State private var selected: ActivitySlice?
    @State private var showRecords = false

    private var report: DayTimelineReport {
        DayTimelineReport(date: model.selectedDate, calendar: model.reportCalendar,
                          sessions: model.dailyActivities, hoursPerLane: hoursPerLane)
    }

    var body: some View {
        let report = report
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("FOLLOW YOUR DAY").font(.system(size: 10, weight: .semibold)).tracking(2).foregroundStyle(Palette.muted)
                Text("一天，沿着时间展开。").font(.system(size: 30, weight: .semibold))
                Text("图标就是当时的应用，轨迹的长度就是停留的时间。")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted)
            }
            ReportPicker(dayOnly: true)
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("一日轨迹").font(.system(size: 18, weight: .semibold))
                        Text("\(durationText(report.seconds)) 已记录 · \(report.sessions.count) 段使用")
                            .font(.system(size: 11)).foregroundStyle(Palette.muted)
                    }
                    Spacer()
                    Picker("轨迹刻度", selection: $hoursPerLane) {
                        Text("4 小时 / 行").tag(4)
                        Text("2 小时 / 行").tag(2)
                    }.labelsHidden().pickerStyle(.segmented).frame(width: 205)
                }
                selectionStrip
                HStack(spacing: 14) {
                    Label("点击图标或色块查看详情", systemImage: "cursorarrow.rays")
                    Spacer()
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 3).fill(Palette.background).frame(width: 15, height: 9)
                        Text("未记录")
                    }
                }.font(.system(size: 10)).foregroundStyle(Palette.muted)
                VStack(spacing: 16) {
                    ForEach(report.lanes) { lane in
                        if lane.empty {
                            HStack {
                                Text("\(time(lane.interval.start)) — \(time(lane.interval.end, end: true))")
                                    .monospacedDigit()
                                Rectangle().fill(Palette.muted.opacity(0.15)).frame(height: 1)
                                Text("未记录")
                            }.font(.system(size: 11)).foregroundStyle(Palette.muted).padding(.vertical, 9)
                        } else {
                            TimelineLaneView(lane: lane, calendar: model.reportCalendar, selectedID: selected?.id) {
                                selected = $0
                            }
                        }
                    }
                }
                if report.sessions.isEmpty {
                    Text("这一天还没有应用记录。让 Monitor 保持运行，新的足迹会显示在这里。")
                        .font(.system(size: 12)).foregroundStyle(Palette.muted).padding(.vertical, 16)
                }
                if report.elapsedEnd < report.interval.end {
                    Label("截至 \(time(report.elapsedEnd)) · 后续时间尚未发生", systemImage: "clock")
                        .font(.system(size: 10)).foregroundStyle(Palette.muted)
                }
                Text("空白仅表示没有记录，可能是休眠、锁屏、暂停或应用未运行。网站停留包含在 Chrome 应用时长内。")
                    .font(.system(size: 10)).foregroundStyle(Palette.muted)
            }.padding(24).background(.white, in: RoundedRectangle(cornerRadius: 16))
            DisclosureGroup(isExpanded: $showRecords) {
                LazyVStack(spacing: 0) {
                    ForEach(report.sessions) { session in
                        Button { selected = session } label: {
                            HStack(spacing: 12) {
                                Text("\(time(session.start)) – \(time(session.end, end: true))")
                                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(Palette.muted)
                                ActivityIcon(key: session.key, kind: .application).frame(width: 25, height: 25)
                                Text(session.name).font(.system(size: 12))
                                Spacer()
                                Text(durationText(session.seconds)).font(.system(size: 11)).foregroundStyle(Palette.muted)
                            }.padding(.vertical, 10).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        Divider().opacity(0.4)
                    }
                }.padding(.top, 12)
            } label: { Text("逐段记录 · \(report.sessions.count) 段").font(.system(size: 13, weight: .medium)) }
                .tint(Palette.green).padding(20).background(.white, in: RoundedRectangle(cornerRadius: 14))
        }
        .onChange(of: model.selectedDate) { _, _ in selected = nil }
        .onChange(of: model.reportTimeZone) { _, _ in selected = nil }
        .onChange(of: model.dailyActivities.map(\.id)) { _, ids in
            if let selected, !ids.contains(selected.id) { self.selected = nil }
        }
    }

    @ViewBuilder private var selectionStrip: some View {
        // Use the refreshed slice for an ongoing session rather than freezing its initial duration.
        let current = selected.flatMap { chosen in model.dailyActivities.first { $0.id == chosen.id } }
        HStack(spacing: 12) {
            if let session = current {
                ActivityIcon(key: session.key, kind: .application).frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 5) {
                    Text(session.name).font(.system(size: 14, weight: .semibold))
                    Text("\(time(session.start)) – \(time(session.end, end: true)) · \(durationText(session.seconds))")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
                Spacer(minLength: 6)
                Button {
                    model.period = .day
                    model.showApplication(ActivityIdentity(key: session.key, name: session.name))
                } label: { Label("查看该应用", systemImage: "arrow.up.right").font(.system(size: 11, weight: .medium)) }
                    .buttonStyle(.plain).foregroundStyle(Palette.green)
            } else {
                Image(systemName: "point.topleft.down.curvedto.point.bottomright.up").font(.system(size: 24)).foregroundStyle(Palette.green)
                VStack(alignment: .leading, spacing: 5) {
                    Text("从一段足迹开始").font(.system(size: 14, weight: .medium))
                    Text("选中一段，查看当时的应用与准确时间。Chrome 可继续展开网页明细。")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
                Spacer(minLength: 0)
            }
        }.padding(16).frame(minHeight: 66)
            .background(Palette.green.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
    }

    private func time(_ date: Date, end: Bool = false) -> String {
        if end && date == report.interval.end { return "24:00" }
        return timelineTime(date, calendar: model.reportCalendar)
    }
}

private struct TimelineLaneView: View {
    let lane: TimelineLane
    let calendar: Calendar
    let selectedID: Int64?
    let choose: (ActivitySlice) -> Void
    @State private var expandedCluster: Date?

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let clusters = iconClusters(width: width)
            ZStack(alignment: .topLeading) {
                let recordedWidth = position(lane.segments.last?.end ?? lane.interval.start, width: width)
                RoundedRectangle(cornerRadius: 9).fill(Palette.background)
                    .frame(width: recordedWidth, height: 48).offset(y: 43)
                if width - recordedWidth > 60 {
                    Text("尚未发生").font(.system(size: 10)).foregroundStyle(Palette.muted.opacity(0.55))
                        .frame(width: width - recordedWidth, height: 48).offset(x: recordedWidth, y: 43)
                }
                ForEach(lane.segments) { segment in
                    let x = position(segment.start, width: width)
                    let span = position(segment.end, width: width) - x
                    if let app = segment.activity {
                        Button { choose(app) } label: {
                            HStack(spacing: 7) {
                                if span >= 42 { ActivityIcon(key: app.key, kind: .application).frame(width: 26, height: 26) }
                                if span >= 132 {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(app.name).font(.system(size: 11, weight: .medium)).lineLimit(1)
                                        Text(durationText(segment.seconds)).font(.system(size: 9)).foregroundStyle(Palette.muted).lineLimit(1)
                                    }
                                }
                            }.padding(.horizontal, span >= 42 ? 8 : 0)
                                .frame(width: max(1, span - (span > 5 ? 2 : 0)), height: 48)
                                .background(color(app.key).opacity(selectedID == app.id ? 0.32 : 0.16), in: RoundedRectangle(cornerRadius: span > 16 ? 8 : 1))
                                .overlay(RoundedRectangle(cornerRadius: span > 16 ? 8 : 1)
                                    .strokeBorder(selectedID == app.id ? color(app.key) : .clear, lineWidth: 1.5))
                                .clipped().contentShape(Rectangle())
                        }.buttonStyle(.plain).offset(x: x, y: 43)
                            .help("\(app.name) · \(timelineTime(segment.start, calendar: calendar)) – \(timelineTime(segment.end, calendar: calendar)) · \(durationText(segment.seconds))")
                            .accessibilityLabel("\(app.name)，\(durationText(segment.seconds))")
                    } else if span > 65 {
                        Text("未记录").font(.system(size: 10)).foregroundStyle(Palette.muted.opacity(0.75))
                            .frame(width: span, height: 48).offset(x: x, y: 43)
                    }
                }
                ForEach(clusters) { cluster in
                    let center = min(width - 20, max(20, cluster.center))
                    Path { path in
                        path.move(to: CGPoint(x: center, y: 31))
                        path.addLine(to: CGPoint(x: cluster.center, y: 43))
                    }.stroke(Palette.muted.opacity(0.45), lineWidth: 1)
                    Button {
                        if cluster.activities.count == 1 { choose(cluster.activities[0]) }
                        else { expandedCluster = cluster.id }
                    } label: {
                        HStack(spacing: 2) {
                            ActivityIcon(key: cluster.activities[0].key, kind: .application).frame(width: 24, height: 24)
                            if cluster.activities.count > 1 {
                                Text("\(cluster.activities.count)").font(.system(size: 9, weight: .semibold)).foregroundStyle(Palette.green)
                            }
                        }.padding(3).background(.white, in: RoundedRectangle(cornerRadius: 7))
                            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Palette.green.opacity(0.15)))
                    }.buttonStyle(.plain).position(x: center, y: 17)
                        .help(cluster.activities.count == 1 ? cluster.activities[0].name : "展开 \(cluster.activities.count) 次短时切换")
                        .popover(isPresented: Binding(get: { expandedCluster == cluster.id }, set: { if !$0 { expandedCluster = nil } })) {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("这里的短时切换").font(.headline)
                                    ForEach(cluster.activities) { app in
                                        Button { choose(app); expandedCluster = nil } label: {
                                            HStack(spacing: 10) {
                                                ActivityIcon(key: app.key, kind: .application).frame(width: 25, height: 25)
                                                VStack(alignment: .leading, spacing: 4) {
                                                    Text(app.name).font(.system(size: 12, weight: .medium))
                                                    Text("\(timelineTime(app.start, calendar: calendar)) · \(durationText(app.seconds))")
                                                        .font(.system(size: 10)).foregroundStyle(Palette.muted)
                                                }
                                                Spacer()
                                            }.padding(6).contentShape(Rectangle())
                                        }.buttonStyle(.plain)
                                    }
                                }.padding(16)
                            }.scrollIndicators(.hidden).frame(width: 280, height: min(360, CGFloat(cluster.activities.count) * 58 + 60))
                        }
                }
                HStack {
                    Text(timelineTime(lane.interval.start, calendar: calendar))
                    Spacer()
                    Text(timelineTime(lane.interval.start.addingTimeInterval(lane.interval.duration / 2), calendar: calendar))
                    Spacer()
                    Text(lane.interval.end == calendar.startOfDay(for: lane.interval.end) ? "24:00" : timelineTime(lane.interval.end, calendar: calendar))
                }.font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.muted).offset(y: 102)
            }
        }.frame(height: 118)
    }

    private struct IconCluster: Identifiable {
        let id: Date
        var center: CGFloat
        var activities: [ActivitySlice]
    }

    private func iconClusters(width: CGFloat) -> [IconCluster] {
        var result: [IconCluster] = []
        for segment in lane.segments {
            guard let app = segment.activity else { continue }
            let x = position(segment.start, width: width), end = position(segment.end, width: width)
            guard end - x < 42 else { continue }
            let center = (x + end) / 2
            if let last = result.last, center - last.center < 48 {
                let count = CGFloat(last.activities.count)
                result[result.count - 1].center = (last.center * count + center) / (count + 1)
                result[result.count - 1].activities.append(app)
            } else { result.append(IconCluster(id: segment.start, center: center, activities: [app])) }
        }
        return result
    }
    private func position(_ date: Date, width: CGFloat) -> CGFloat {
        width * date.timeIntervalSince(lane.interval.start) / max(1, lane.interval.duration)
    }
    private func color(_ key: String) -> Color {
        let colors = [Palette.green, Color(red: 0.30, green: 0.48, blue: 0.64), Palette.orange,
                      Color(red: 0.49, green: 0.43, blue: 0.64), Color(red: 0.48, green: 0.54, blue: 0.32)]
        return colors[key.utf8.reduce(0) { ($0 * 31 + Int($1)) % colors.count }]
    }
}

private func timelineTime(_ date: Date, calendar: Calendar) -> String {
    date.formatted(Date.FormatStyle(locale: Locale(identifier: "zh_CN"), calendar: calendar, timeZone: calendar.timeZone)
        .hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
}
