import SwiftUI
import Charts
import MonitorCore

struct ApplicationDetailView: View {
    @EnvironmentObject private var model: MonitorModel
    let report: ApplicationReport
    @State private var selectedBucket: Date?
    @State private var hoveredBucket: Date?
    @State private var selectedSession: Int64?
    @State private var focusRecordedHours = false
    private var calendar: Calendar { report.calendar }
    private var dateStyle: Date.FormatStyle {
        Date.FormatStyle(locale: Locale(identifier: "zh_CN"), calendar: calendar, timeZone: calendar.timeZone)
    }

    private var highlighted: UsageBucket? {
        let date = hoveredBucket ?? selectedBucket
        return date.flatMap { report.bucket(containing: $0) } ?? report.peak
    }
    private var visibleDays: [SessionDay] {
        guard report.period != .day, let selectedBucket else { return report.days }
        return report.days.filter { calendar.isDate($0.date, inSameDayAs: selectedBucket) }
    }
    private var domain: ClosedRange<Date> {
        guard report.period == .day, focusRecordedHours,
              let first = report.sessions.first, let last = report.sessions.last else {
            return report.interval.start...report.interval.end
        }
        let start = calendar.dateInterval(of: .hour, for: first.start)!.start
        let end = calendar.dateInterval(of: .hour, for: last.end.addingTimeInterval(-0.001))!.end
        return start...max(end, start.addingTimeInterval(3600))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header
            HStack(spacing: 16) {
                metric("累计使用", value: durationText(report.seconds))
                metric("使用时段", value: "\(report.sessions.count) 段")
                metric("最长一段", value: durationText(report.longest))
            }
            if report.sessions.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "clock.badge.questionmark").font(.system(size: 30, weight: .light))
                    Text("这个时段还没有使用记录").font(.system(size: 15, weight: .medium))
                    Text("切换上方日期，查看其他日、周或月的足迹。")
                        .font(.system(size: 12)).foregroundStyle(Palette.muted)
                }.frame(maxWidth: .infinity).padding(.vertical, 55).foregroundStyle(Palette.muted)
            } else {
                chartCard
                sessionList
            }
            Label("只统计前台停留时间；锁屏、休眠和暂停期间不计时。时段可能从所选范围的边界截取。", systemImage: "info.circle")
                .font(.system(size: 10)).foregroundStyle(Palette.muted)
        }
        .padding(24).frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 16))
        .environment(\.calendar, calendar)
        .environment(\.timeZone, calendar.timeZone)
        .onChange(of: report.interval) { _, _ in resetSelection() }
        .onChange(of: report.application.key) { _, _ in resetSelection() }
        .onChange(of: report.period) { _, _ in resetSelection() }
        .onChange(of: report.calendar.timeZone) { _, _ in resetSelection() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                ActivityIcon(key: report.application.key, kind: .application).frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 5) {
                    Text(report.application.name).font(.system(size: 22, weight: .semibold)).lineLimit(2)
                    Text(report.period.label(for: report.interval.start, calendar: calendar)).font(.system(size: 11)).foregroundStyle(Palette.muted)
                    ApplicationLocationView(bundleIdentifier: report.application.key)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func metric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 11)).foregroundStyle(Palette.muted)
            Text(value).font(.system(size: 19, weight: .medium, design: .rounded)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.7)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(report.period == .day ? "一天中的使用节奏" : "每天的使用趋势")
                        .font(.system(size: 14, weight: .semibold))
                    Text(report.period == .day ? "每小时累计 · 分钟" : "每日累计 · 分钟")
                        .font(.system(size: 10)).foregroundStyle(Palette.muted)
                }
                Spacer(minLength: 8)
                if report.period == .day {
                    HStack(spacing: 2) {
                        zoomButton("全天", focused: false)
                        zoomButton("有记录时段", focused: true)
                    }.padding(3).background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 7))
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let bucket = highlighted {
                    Text(durationText(bucket.seconds)).font(.system(size: 23, weight: .medium, design: .rounded)).monospacedDigit()
                    Text(bucketLabel(bucket)).font(.system(size: 11)).foregroundStyle(Palette.muted)
                    Spacer(minLength: 0)
                    if selectedBucket == nil && hoveredBucket == nil {
                        Text("使用最多").font(.system(size: 10)).foregroundStyle(Palette.green)
                    }
                }
            }.frame(height: 30)
            usageChart.frame(height: 180)
            if report.period == .day { sessionRibbon }
            HStack(spacing: 5) {
                Image(systemName: "cursorarrow.rays")
                Text(report.period == .day ? "悬停查看每小时用量，点击高亮对应记录" : "悬停查看用量，点击日期查看当天记录")
            }.font(.system(size: 10)).foregroundStyle(Palette.muted)
        }
        .padding(18)
        .background(LinearGradient(colors: [Palette.green.opacity(0.075), Palette.background.opacity(0.7)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 14))
    }

    private func zoomButton(_ text: String, focused: Bool) -> some View {
        Button { focusRecordedHours = focused } label: {
            Text(text).font(.system(size: 10, weight: .medium)).padding(.horizontal, 8).padding(.vertical, 6)
                .foregroundStyle(focusRecordedHours == focused ? Color.white : Palette.muted)
                .background(focusRecordedHours == focused ? Palette.green : .clear, in: RoundedRectangle(cornerRadius: 5))
        }.buttonStyle(.plain).accessibilityAddTraits(focusRecordedHours == focused ? .isSelected : [])
    }

    private var usageChart: some View {
        Chart {
            ForEach(report.buckets) { bucket in
                AreaMark(x: .value("时间", bucket.midpoint), yStart: .value("零", 0), yEnd: .value("分钟", bucket.seconds / 60))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(LinearGradient(colors: [Palette.green.opacity(0.28), Palette.green.opacity(0.015)],
                                                    startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("时间", bucket.midpoint), y: .value("分钟", bucket.seconds / 60))
                    .interpolationMethod(.monotone).foregroundStyle(Palette.green.opacity(0.85))
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                if report.period != .day {
                    PointMark(x: .value("时间", bucket.midpoint), y: .value("分钟", bucket.seconds / 60))
                        .symbolSize(14).foregroundStyle(Palette.green.opacity(0.8))
                }
            }
            if let bucket = highlighted, domain.contains(bucket.midpoint) {
                RuleMark(x: .value("选中时间", bucket.midpoint))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4])).foregroundStyle(Palette.green.opacity(0.3))
                PointMark(x: .value("时间", bucket.midpoint), y: .value("分钟", bucket.seconds / 60))
                    .symbolSize(90).foregroundStyle(.white)
                PointMark(x: .value("时间", bucket.midpoint), y: .value("分钟", bucket.seconds / 60))
                    .symbolSize(36).foregroundStyle(Palette.green)
            }
        }
        .chartXScale(domain: domain)
        .chartYScale(domain: 0...max(1, (report.peak?.seconds ?? 0) / 60 * 1.2))
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: report.period == .week ? 7 : 5)) { value in
                AxisValueLabel(anchor: .top) {
                    if let date = value.as(Date.self) {
                        Text(axisLabel(date)).font(.system(size: 10)).foregroundStyle(Palette.muted)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine().foregroundStyle(Palette.green.opacity(0.08))
                AxisValueLabel(anchor: .trailing) {
                    if let minutes = value.as(Double.self) {
                        Text(minutes.formatted(.number.precision(.fractionLength(0...1))))
                            .font(.system(size: 10)).foregroundStyle(Palette.muted)
                    }
                }
            }
        }
        .chartPlotStyle { plot in plot.clipped() }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location): hoveredBucket = bucketAt(location, proxy: proxy, geometry: geometry)?.id
                        case .ended: hoveredBucket = nil
                        }
                    }
                    .onTapGesture { location in
                        if let bucket = bucketAt(location, proxy: proxy, geometry: geometry) {
                            selectedBucket = bucket.id
                            selectedSession = nil
                        }
                    }
            }
        }
        .accessibilityLabel(report.period == .day ? "每小时应用使用分钟数" : "每天应用使用分钟数")
    }

    private func bucketAt(_ point: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) -> UsageBucket? {
        guard let anchor = proxy.plotFrame else { return nil }
        let frame = geometry[anchor]
        guard frame.contains(point), let date: Date = proxy.value(atX: point.x - frame.minX) else { return nil }
        return report.bucket(containing: date)
    }

    private var sessionRibbon: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.green.opacity(0.055))
                    ForEach(report.sessions) { session in
                        let start = max(session.start, domain.lowerBound)
                        let end = min(session.end, domain.upperBound)
                        let span = domain.upperBound.timeIntervalSince(domain.lowerBound)
                        if end > start {
                            Capsule().fill(Palette.green.opacity(selectedSession == session.id ? 1 : 0.6))
                                .frame(width: max(1, geometry.size.width * end.timeIntervalSince(start) / span))
                                .offset(x: geometry.size.width * start.timeIntervalSince(domain.lowerBound) / span)
                                .help("\(time(session.start)) – \(time(session.end)) · \(durationText(session.seconds))\(interruptionText(report.interruptions[session.id]))")
                        }
                    }
                }
            }.frame(height: 5)
            Text("实际使用时段").font(.system(size: 9)).foregroundStyle(Palette.muted)
        }.accessibilityLabel("实际使用时段详见下方记录")
    }

    private var sessionList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("详细时间段").font(.system(size: 14, weight: .semibold))
                Spacer()
                if selectedBucket != nil {
                    Button(report.period == .day ? "取消高亮" : "查看全部日期") {
                        selectedBucket = nil; selectedSession = nil
                    }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Palette.green)
                } else {
                    Text("按时间先后").font(.system(size: 10)).foregroundStyle(Palette.muted)
                }
            }
            if visibleDays.isEmpty {
                Text("\(selectedBucket.map { dateLabel($0) } ?? "当天")没有使用记录")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted).padding(.vertical, 20)
            }
            LazyVStack(alignment: .leading, spacing: 14) {
                ForEach(visibleDays) { day in
                    VStack(alignment: .leading, spacing: 8) {
                        if report.period != .day {
                            HStack {
                                Text(dateLabel(day.date))
                                Spacer()
                                Text(durationText(day.seconds))
                            }.font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.muted)
                                .padding(.top, 5)
                        }
                        if report.period == .day {
                            ForEach(0..<4) { part in
                                let sessions = day.sessions.filter { calendar.component(.hour, from: $0.start) / 6 == part }
                                if !sessions.isEmpty {
                                    Label(["凌晨", "上午", "下午", "晚上"][part],
                                          systemImage: ["moon.stars", "sunrise", "sun.max", "moon"][part])
                                        .font(.system(size: 10)).foregroundStyle(Palette.muted).padding(.top, 6)
                                    ForEach(sessions) { session in sessionDetail(session) }
                                }
                            }
                        } else {
                            ForEach(day.sessions) { session in sessionDetail(session) }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private func sessionDetail(_ session: ActivitySlice) -> some View {
        if report.application.key == ActivityTracker.chromeBundleID {
            let bucket = selectedBucket.flatMap { report.bucket(containing: $0) }
            let highlighted = report.period == .day && bucket.map {
                session.start < $0.interval.end && session.end > $0.interval.start
            } == true
            BrowserSessionView(session: session, visits: report.browserVisits(in: session), calendar: calendar,
                activeSeconds: report.activeSeconds[session.id], interruptions: report.interruptions[session.id] ?? 0,
                initiallyExpanded: session.id == report.sessions.first?.id, highlighted: highlighted)
        } else { sessionRow(session) }
    }

    private func sessionRow(_ session: ActivitySlice) -> some View {
        let bucket = selectedBucket.flatMap { report.bucket(containing: $0) }
        let matches = selectedSession == session.id || (selectedSession == nil && report.period == .day &&
            bucket.map { session.start < $0.interval.end && session.end > $0.interval.start } == true)
        return Button {
            selectedSession = session.id
            selectedBucket = report.bucket(containing: session.start)?.id
        } label: {
            HStack(spacing: 12) {
                Circle().fill(matches ? Palette.green : Palette.green.opacity(0.4)).frame(width: 6, height: 6)
                Text("\(time(session.start))  –  \(time(session.end, ending: true))")
                    .font(.system(size: 12, design: .monospaced))
                Spacer()
                Text(durationText(session.seconds) + interruptionText(report.interruptions[session.id]))
                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
            }.padding(.horizontal, 12).padding(.vertical, 12)
                .background(matches ? Palette.green.opacity(0.08) : Palette.background.opacity(0.5),
                            in: RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityAddTraits(matches ? .isSelected : [])
    }

    private func bucketLabel(_ bucket: UsageBucket) -> String {
        report.period == .day ? "\(axisLabel(bucket.interval.start)) – \(axisLabel(bucket.interval.end))" : dateLabel(bucket.interval.start)
    }
    private func time(_ date: Date, ending: Bool = false) -> String {
        if ending && date == calendar.startOfDay(for: date) { return "24:00:00" }
        return date.formatted(dateStyle.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits))
    }
    private func axisLabel(_ date: Date) -> String {
        if report.period == .day {
            if date == report.interval.end { return "24:00" }
            return date.formatted(dateStyle.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
        }
        return "\(calendar.component(.month, from: date))/\(calendar.component(.day, from: date))"
    }
    private func dateLabel(_ date: Date) -> String {
        date.formatted(dateStyle.month().day().weekday(.wide))
    }
    private func resetSelection() {
        selectedBucket = nil; hoveredBucket = nil; selectedSession = nil; focusRecordedHours = false
    }
}
