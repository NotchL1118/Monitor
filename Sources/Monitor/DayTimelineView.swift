import SwiftUI
import MonitorCore

/// Fixed categorical colors for the day trail; slot 3 (yellow) takes dark text.
enum TrailPalette {
    static let slots: [Color] = [
        Color(red: 0.165, green: 0.471, blue: 0.839), Color(red: 0.922, green: 0.408, blue: 0.204),
        Color(red: 0.106, green: 0.686, blue: 0.478), Color(red: 0.929, green: 0.631, blue: 0.0),
        Color(red: 0.910, green: 0.482, blue: 0.643), Color(red: 0.0, green: 0.514, blue: 0.0),
        Color(red: 0.384, green: 0.314, blue: 0.839)
    ]
    static let other = Color(red: 0.72, green: 0.74, blue: 0.72)
    static let line = Color(red: 0.89, green: 0.89, blue: 0.87)
    static func color(_ slot: Int?) -> Color { slot.map { slots[$0 % slots.count] } ?? other }
    static func text(_ slot: Int?) -> Color { slot == 3 ? Color(white: 0.05) : .white }
}

struct DayTimelineView: View {
    @EnvironmentObject private var model: MonitorModel
    @State private var expanded: Set<Date> = []
    @State private var highlighted: Date?

    private var report: DayTimelineReport {
        DayTimelineReport(date: model.selectedDate, calendar: model.reportCalendar, activities: model.dailyActivities)
    }

    var body: some View {
        let report = report
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("FOLLOW YOUR DAY").font(.system(size: 10, weight: .semibold)).tracking(2).foregroundStyle(Palette.muted)
                    Text("这一天，你都在做什么。").font(.system(size: 30, weight: .semibold))
                    Text("按使用习惯自动分成若干时段，离开 10 分钟以上会单独标出。")
                        .font(.system(size: 12)).foregroundStyle(Palette.muted)
                }
                ReportPicker(dayOnly: true)
                if report.segments.isEmpty {
                    Text("这一天还没有应用记录。让 Monitor 保持运行，新的足迹会显示在这里。")
                        .font(.system(size: 12)).foregroundStyle(Palette.muted)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(24)
                        .background(.white, in: RoundedRectangle(cornerRadius: 16))
                } else {
                    summary(report)
                    VStack(alignment: .leading, spacing: 14) {
                        Text("全天概览").font(.system(size: 13, weight: .semibold))
                        DayOverviewChart(report: report, calendar: model.reportCalendar, highlighted: $highlighted) { id in
                            expanded.insert(id)
                            withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(id, anchor: .center) }
                        }
                        HStack(spacing: 18) {
                            Text("上：自动划分的时段，颜色为该时段的主要应用")
                            Text("下：主要应用各占一行，每一小段是一次实际使用")
                            Text("斜纹：离开")
                        }.font(.system(size: 10)).foregroundStyle(Palette.muted)
                    }.padding(20).background(.white, in: RoundedRectangle(cornerRadius: 16))
                    VStack(spacing: 0) {
                        ForEach(report.blocks) { block in
                            switch block {
                            case .away(let away): awayRow(away)
                            case .segment(let segment):
                                SegmentRow(segment: segment, colors: report.colors, calendar: model.reportCalendar,
                                           expanded: expanded.contains(segment.id), highlighted: highlighted == segment.id,
                                           toggle: { toggle(segment.id) },
                                           hover: { highlighted = $0 ? segment.id : (highlighted == segment.id ? nil : highlighted) },
                                           open: { app in
                                               model.period = .day
                                               model.showApplication(ActivityIdentity(key: app.key, name: app.name))
                                           }).id(segment.id)
                            }
                        }
                    }
                }
                if report.elapsedEnd < report.interval.end {
                    Label("截至 \(time(report.elapsedEnd)) · 后续时间尚未发生", systemImage: "clock")
                        .font(.system(size: 10)).foregroundStyle(Palette.muted)
                }
                Text("时段是为了便于阅读的自动划分，不改变原始记录，时长统计仍按实际记录计算。网站停留包含在 Chrome 应用时长内。")
                    .font(.system(size: 10)).foregroundStyle(Palette.muted)
            }
        }
        .onChange(of: model.selectedDate) { _, _ in expanded = []; highlighted = nil }
        .onChange(of: model.reportTimeZone) { _, _ in expanded = []; highlighted = nil }
    }

    private func toggle(_ id: Date) {
        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
    }

    private func summary(_ report: DayTimelineReport) -> some View {
        HStack(spacing: 28) {
            stat(durationText(report.seconds), "活跃")
            if let first = report.firstActivity, let last = report.lastActivity {
                stat("\(time(first)) – \(time(last, end: true))", "首末活动")
            }
            stat("\(report.segments.count)", "个时段")
            stat("\(report.awayCount)", "次离开")
            stat("\(report.switches)", "次切换")
            Spacer(minLength: 0)
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value).font(.system(size: 17, weight: .semibold)).monospacedDigit()
            Text(label).font(.system(size: 10)).foregroundStyle(Palette.muted)
        }
    }

    private func awayRow(_ away: DaySegmenter.Away) -> some View {
        HStack(spacing: 14) {
            Text("\(time(away.start)) – \(time(away.end, end: true))")
                .font(.system(size: 11, design: .monospaced)).foregroundStyle(Palette.muted)
                .frame(width: SegmentRow.timeWidth, alignment: .trailing)
            HStack(spacing: 10) {
                DashedLine().frame(width: 16)
                Text("离开 \(durationText(away.seconds))" + (away.briefSeconds > 0 ? "（中途短暂使用 \(durationText(away.briefSeconds))）" : ""))
                DashedLine()
            }.font(.system(size: 11)).foregroundStyle(Palette.muted)
        }.padding(.vertical, 6)
    }

    private func time(_ date: Date, end: Bool = false) -> String {
        if end && date == report.interval.end { return "24:00" }
        return timelineTime(date, calendar: model.reportCalendar)
    }
}

private struct DashedLine: View {
    var body: some View {
        GeometryReader { g in
            Path { p in p.move(to: CGPoint(x: 0, y: 0.5)); p.addLine(to: CGPoint(x: g.size.width, y: 0.5)) }
                .stroke(Palette.muted.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        }.frame(height: 1)
    }
}

struct Hatch: View {
    var body: some View {
        Canvas { context, size in
            var path = Path()
            var x: CGFloat = -size.height
            while x < size.width {
                path.move(to: CGPoint(x: x, y: size.height)); path.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += 6
            }
            context.stroke(path, with: .color(Palette.muted.opacity(0.22)), lineWidth: 2)
        }.clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

// MARK: - Overview

private struct DayOverviewChart: View {
    let report: DayTimelineReport
    let calendar: Calendar
    @Binding var highlighted: Date?
    let select: (Date) -> Void
    @State private var hover: CGFloat?

    private let labelWidth: CGFloat = 110
    private let bandHeight: CGFloat = 34
    private let laneHeight: CGFloat = 14
    private let laneSpacing: CGFloat = 6
    private let axisHeight: CGFloat = 18

    private var lanesTop: CGFloat { bandHeight + 12 }
    private var plotHeight: CGFloat { lanesTop + CGFloat(report.lanes.count) * (laneHeight + laneSpacing) }

    var body: some View {
        GeometryReader { geometry in
            let width = max(1, geometry.size.width - labelWidth)
            ZStack(alignment: .topLeading) {
                grid(width: width)
                Text("时段").font(.system(size: 11)).foregroundStyle(Palette.muted)
                    .frame(width: labelWidth, height: bandHeight, alignment: .leading)
                ForEach(report.blocks) { block in band(block, width: width) }
                ForEach(Array(report.lanes.enumerated()), id: \.element.id) { index, lane in
                    let y = lanesTop + CGFloat(index) * (laneHeight + laneSpacing)
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 2).fill(laneColor(lane)).frame(width: 8, height: 8)
                        Text(lane.name).font(.system(size: 11)).lineLimit(1).truncationMode(.tail)
                    }.frame(width: labelWidth - 8, height: laneHeight, alignment: .leading).offset(y: y)
                    Canvas { context, size in
                        for run in lane.runs {
                            let a = x(run.start, width: width), b = x(run.end, width: width)
                            let color = lane.key == nil ? TrailPalette.color(report.colors[run.key]) : laneColor(lane)
                            context.fill(Path(roundedRect: CGRect(x: a, y: 2, width: max(1, b - a), height: size.height - 4), cornerRadius: 1.5),
                                         with: .color(color))
                        }
                        context.fill(Path(CGRect(x: 0, y: size.height - 0.5, width: size.width, height: 0.5)), with: .color(TrailPalette.line))
                    }.frame(width: width, height: laneHeight).offset(x: labelWidth, y: y)
                }
                axis(width: width)
                if let hover { crosshair(at: hover, width: width) }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let point) where point.x >= labelWidth && point.x <= labelWidth + width:
                    hover = point.x - labelWidth
                    let date = date(at: point.x - labelWidth, width: width)
                    highlighted = report.block(at: date)?.segment?.id
                default:
                    if hover != nil { highlighted = nil }
                    hover = nil
                }
            }
        }.frame(height: plotHeight + axisHeight)
    }

    @ViewBuilder private func band(_ block: DaySegmenter.Block, width: CGFloat) -> some View {
        let a = x(block.start, width: width), w = max(2, x(block.end, width: width) - a)
        switch block {
        case .away(let away):
            Hatch().overlay {
                if w > 40 { Text("离开").font(.system(size: 10)).foregroundStyle(Palette.muted) }
            }.frame(width: w, height: bandHeight - 8).offset(x: labelWidth + a, y: 4)
                .help("离开 \(durationText(away.seconds))")
        case .segment(let segment):
            let slot = segment.apps.first.flatMap { report.colors[$0.key] }
            let dimmed = highlighted != nil && highlighted != segment.id
            Button { select(segment.id) } label: {
                Text(w > 60 ? (segment.apps.first?.name ?? "") : "")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(TrailPalette.text(slot)).lineLimit(1)
                    .padding(.horizontal, 6).frame(width: max(2, w - 2), height: bandHeight, alignment: .leading)
                    .background(TrailPalette.color(slot), in: RoundedRectangle(cornerRadius: 4))
                    .opacity(dimmed ? 0.35 : 1).contentShape(Rectangle())
            }.buttonStyle(.plain).offset(x: labelWidth + a, y: 0)
                .accessibilityLabel("\(DayTimelineReport.title(segment))，\(durationText(segment.span))")
        }
    }

    private func grid(width: CGFloat) -> some View {
        Canvas { context, size in
            for hour in hours() {
                let px = labelWidth + x(hour, width: width)
                context.fill(Path(CGRect(x: px, y: 0, width: 0.5, height: plotHeight)), with: .color(TrailPalette.line))
            }
        }.frame(height: plotHeight).allowsHitTesting(false)
    }

    private func axis(width: CGFloat) -> some View {
        let all = hours()
        let step = all.count > 13 ? 2 : 1
        return ZStack(alignment: .topLeading) {
            ForEach(Array(all.enumerated()), id: \.offset) { index, hour in
                if index % step == 0 {
                    Text(hourLabel(hour)).font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.muted)
                        .fixedSize().position(x: labelWidth + x(hour, width: width), y: axisHeight / 2)
                }
            }
        }.frame(height: axisHeight).offset(y: plotHeight)
    }

    private func crosshair(at px: CGFloat, width: CGFloat) -> some View {
        let date = date(at: px, width: width)
        let app = report.application(at: date)
        let block = report.block(at: date)
        let tipWidth: CGFloat = 210
        let left = labelWidth + px + 12 + tipWidth > labelWidth + width ? labelWidth + px - tipWidth - 12 : labelWidth + px + 12
        return ZStack(alignment: .topLeading) {
            Rectangle().fill(Palette.ink.opacity(0.55)).frame(width: 1, height: plotHeight).offset(x: labelWidth + px)
            VStack(alignment: .leading, spacing: 4) {
                Text(timelineTime(date, calendar: calendar)).font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.muted)
                if let app {
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 2).fill(TrailPalette.color(report.colors[app.key])).frame(width: 8, height: 8)
                        Text(app.name).font(.system(size: 12, weight: .medium))
                    }
                } else {
                    Text(block?.segment == nil && block != nil ? "离开" : "无记录").font(.system(size: 12)).foregroundStyle(Palette.muted)
                }
                if let block {
                    Text(blockCaption(block)).font(.system(size: 10)).foregroundStyle(Palette.muted).lineLimit(2)
                }
            }.padding(10).frame(width: tipWidth, alignment: .leading)
                .background(.white, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(TrailPalette.line))
                .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
                .offset(x: max(0, left), y: lanesTop)
        }.allowsHitTesting(false)
    }

    private func blockCaption(_ block: DaySegmenter.Block) -> String {
        let range = "\(timelineTime(block.start, calendar: calendar))–\(timelineTime(block.end, calendar: calendar))"
        switch block {
        case .segment(let segment): return "所在时段：\(DayTimelineReport.title(segment)) · \(range)"
        case .away(let away): return "离开 \(durationText(away.seconds)) · \(range)"
        }
    }

    private func hours() -> [Date] {
        var result: [Date] = []
        var cursor = report.range.start
        while cursor <= report.range.end {
            result.append(cursor)
            guard let next = calendar.date(byAdding: .hour, value: 1, to: cursor), next > cursor else { break }
            cursor = next
        }
        return result
    }

    private func hourLabel(_ date: Date) -> String {
        if date == report.interval.end { return "24" }
        return String(format: "%02d", calendar.component(.hour, from: date))
    }

    private func laneColor(_ lane: DayTimelineLane) -> Color {
        lane.key.map { TrailPalette.color(report.colors[$0]) } ?? TrailPalette.other
    }
    private func x(_ date: Date, width: CGFloat) -> CGFloat {
        width * date.timeIntervalSince(report.range.start) / max(1, report.range.duration)
    }
    private func date(at px: CGFloat, width: CGFloat) -> Date {
        report.range.start.addingTimeInterval(report.range.duration * Double(px / width))
    }
}

// MARK: - Period list

private struct SegmentRow: View {
    static let timeWidth: CGFloat = 112

    let segment: DaySegmenter.Segment
    let colors: [String: Int]
    let calendar: Calendar
    let expanded: Bool
    let highlighted: Bool
    let toggle: () -> Void
    let hover: (Bool) -> Void
    let open: (DaySegmenter.Share) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .trailing, spacing: 3) {
                Text("\(t(segment.start)) – \(t(segment.end))").font(.system(size: 11, design: .monospaced))
                Text(durationText(segment.span)).font(.system(size: 10)).foregroundStyle(Palette.muted)
            }.frame(width: Self.timeWidth, alignment: .trailing).padding(.top, 16)
            VStack(alignment: .leading, spacing: 10) {
                header
                composition
                legend
                if !segment.websites.isEmpty {
                    Text("Chrome 里主要在看：" + segment.websites.prefix(4).map { "\($0.name) \(durationText($0.seconds))" }.joined(separator: "、"))
                        .font(.system(size: 11)).foregroundStyle(Palette.muted).lineLimit(2)
                }
                if expanded { detail }
            }
            .padding(14)
            .background(.white, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(highlighted ? Palette.green.opacity(0.45) : TrailPalette.line, lineWidth: highlighted ? 1.5 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .onTapGesture(perform: toggle)
            .onHover(perform: hover)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(named: expanded ? "收起" : "展开", toggle)
        }.padding(.vertical, 5)
    }

    private var header: some View {
        HStack(spacing: 10) {
            if let lead = segment.apps.first {
                ActivityIcon(key: lead.key, kind: .application).frame(width: 26, height: 26)
            }
            Text(DayTimelineReport.title(segment)).font(.system(size: 14, weight: .semibold)).lineLimit(1)
            focusChip
            Spacer(minLength: 8)
            Text("活跃 \(durationText(segment.activeSeconds)) · 切换 \(segment.switches) 次")
                .font(.system(size: 11)).foregroundStyle(Palette.muted).monospacedDigit()
            Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(Palette.muted)
        }
    }

    private var focusChip: some View {
        let (label, color): (String, Color) = switch segment.focus {
        case .focused: ("专注", Color(red: 0.0, green: 0.42, blue: 0.0))
        case .mixed: ("混合", Color(red: 0.63, green: 0.36, blue: 0.0))
        case .fragmented: ("碎片", Color(red: 0.69, green: 0.22, blue: 0.18))
        }
        return Text(label).font(.system(size: 10, weight: .medium)).foregroundStyle(color)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .overlay(Capsule().strokeBorder(color.opacity(0.8)))
    }

    private var composition: some View {
        GeometryReader { g in
            let gaps = CGFloat(max(0, segment.apps.count - 1)) * 2
            HStack(spacing: 2) {
                ForEach(segment.apps) { app in
                    Rectangle().fill(TrailPalette.color(colors[app.key]))
                        .frame(width: max(1, (g.size.width - gaps) * segment.share(of: app)))
                }
            }
        }.frame(height: 8).clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var legend: some View {
        let shown = segment.apps.prefix(4).filter { segment.share(of: $0) >= 0.01 }
        let rest = 1 - shown.reduce(0) { $0 + segment.share(of: $1) }
        return HStack(spacing: 14) {
            ForEach(shown) { app in
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 2).fill(TrailPalette.color(colors[app.key])).frame(width: 8, height: 8)
                    Text(app.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    Text(percent(segment.share(of: app))).font(.system(size: 11)).foregroundStyle(Palette.muted).monospacedDigit()
                }
            }
            if rest >= 0.005 {
                Text("其他 \(percent(rest))").font(.system(size: 11)).foregroundStyle(Palette.muted)
            }
        }
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider().opacity(0.5)
            Canvas { context, size in
                context.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 3), with: .color(Palette.background))
                let span = max(1, segment.span)
                for run in segment.runs {
                    let a = size.width * run.start.timeIntervalSince(segment.start) / span
                    let b = size.width * run.end.timeIntervalSince(segment.start) / span
                    context.fill(Path(CGRect(x: a, y: 0, width: max(1, b - a), height: size.height)),
                                 with: .color(TrailPalette.color(colors[run.key])))
                }
            }.frame(height: 14)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(rows) { row in
                    HStack(spacing: 10) {
                        Text(t(row.start)).font(.system(size: 11, design: .monospaced)).foregroundStyle(Palette.muted)
                            .frame(width: 42, alignment: .leading)
                        if let key = row.key {
                            RoundedRectangle(cornerRadius: 2).fill(TrailPalette.color(colors[key])).frame(width: 8, height: 8)
                        } else { Color.clear.frame(width: 8, height: 8) }
                        Text(row.label).font(.system(size: 12)).foregroundStyle(row.key == nil ? Palette.muted : Palette.ink).lineLimit(1)
                        Spacer(minLength: 8)
                        Text(durationText(row.seconds)).font(.system(size: 11)).foregroundStyle(Palette.muted).monospacedDigit()
                    }
                }
            }
            HStack(spacing: 16) {
                ForEach(segment.apps.prefix(3)) { app in
                    Button { open(app) } label: {
                        Label("查看 \(app.name)", systemImage: "arrow.up.right").font(.system(size: 11, weight: .medium))
                    }.buttonStyle(.plain).foregroundStyle(Palette.green)
                }
            }
        }
    }

    private struct Row: Identifiable {
        let start: Date
        let key: String?
        let label: String
        let seconds: Double
        var id: Date { start }
    }

    /// Uses of a minute or more are listed one by one; consecutive shorter switches collapse into one line.
    private var rows: [Row] {
        var result: [Row] = []
        var buffer: [ActivitySlice] = []
        func flush() {
            guard let first = buffer.first else { return }
            var counts: [String: Int] = [:]
            var order: [String] = []
            for run in buffer { if counts[run.name] == nil { order.append(run.name) }; counts[run.name, default: 0] += 1 }
            let names = order.sorted { counts[$0]! > counts[$1]! }.map { counts[$0]! > 1 ? "\($0) ×\(counts[$0]!)" : $0 }
            result.append(Row(start: first.start, key: nil, label: "\(buffer.count) 次短暂切换（\(names.joined(separator: "、"))）",
                              seconds: buffer.reduce(0) { $0 + $1.seconds }))
            buffer = []
        }
        for run in segment.runs {
            if run.seconds < 60 { buffer.append(run); continue }
            flush()
            result.append(Row(start: run.start, key: run.key, label: run.name, seconds: run.seconds))
        }
        flush()
        return result
    }

    private func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }
    private func t(_ date: Date) -> String { timelineTime(date, calendar: calendar) }
}

func timelineTime(_ date: Date, calendar: Calendar) -> String {
    date.formatted(Date.FormatStyle(locale: Locale(identifier: "zh_CN"), calendar: calendar, timeZone: calendar.timeZone)
        .hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
}
