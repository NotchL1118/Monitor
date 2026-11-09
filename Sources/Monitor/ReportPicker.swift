import SwiftUI

struct ReportPicker: View {
    @EnvironmentObject private var model: MonitorModel
    var dayOnly = false
    private var period: ReportPeriod { dayOnly ? .day : model.period }
    private var interval: DateInterval { period.interval(containing: model.selectedDate, calendar: model.reportCalendar) }
    private func step(_ delta: Int) {
        if let next = model.reportCalendar.date(byAdding: period.component, value: delta, to: interval.start) {
            model.selectedDate = min(next, Date())
        }
    }
    @State private var showingCalendar = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
        HStack(spacing: 14) {
            if !dayOnly {
                SegmentedControl(options: ReportPeriod.allCases, selection: $model.period,
                                 title: \.rawValue, accessibilityTitle: { "按\($0.rawValue)查看" })
            }

            HStack(spacing: 0) {
                arrow("chevron.left", "上一\(period.rawValue)") { step(-1) }
                Button {
                    showingCalendar.toggle()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "calendar").foregroundStyle(Palette.green)
                        Text(period.label(for: model.selectedDate, calendar: model.reportCalendar)).font(.system(size: 15, weight: .medium))
                        Image(systemName: "chevron.down").font(.caption2).foregroundStyle(Palette.muted)
                    }.padding(.horizontal, 7).frame(height: 38).contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .popover(isPresented: $showingCalendar, arrowEdge: .bottom) {
                        ReportCalendar(period: period, selection: model.selectedDate, calendar: model.reportCalendar) { day in
                            model.selectedDate = day
                            showingCalendar = false
                        }
                    }
                arrow("chevron.right", "下一\(period.rawValue)") { step(1) }
                    .disabled(isCurrent)
            }.background(.white, in: RoundedRectangle(cornerRadius: 10))
            if !isCurrent {
                Button(period.currentLabel) { model.selectedDate = Date() }
                    .buttonStyle(.plain).foregroundStyle(Palette.green)
            }
            Spacer(minLength: 0)
        }
        Label(model.reportTimeZone.label, systemImage: "globe")
            .font(.system(size: 10)).foregroundStyle(Palette.muted)
        }
    }

    private var isCurrent: Bool { interval.start == period.interval(containing: Date(), calendar: model.reportCalendar).start }
}

private func arrow(_ icon: String, _ label: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Image(systemName: icon).font(.system(size: 12, weight: .semibold))
            .frame(width: 32, height: 36).contentShape(Rectangle())
    }.buttonStyle(.plain).accessibilityLabel(label).help(label)
}

struct ReportCalendar: View {
    let period: ReportPeriod
    let selection: Date
    let choose: (Date) -> Void
    @State private var page: Date
    private let calendar: Calendar

    init(period: ReportPeriod, selection: Date, calendar: Calendar = ReportPeriod.calendar, choose: @escaping (Date) -> Void) {
        self.period = period
        self.selection = selection
        self.calendar = calendar
        self.choose = choose
        _page = State(initialValue: ReportPeriod.month.interval(containing: selection, calendar: calendar).start)
    }

    private var pageUnit: Calendar.Component { period == .month ? .year : .month }
    private var pageStart: Date { calendar.dateInterval(of: pageUnit, for: page)!.start }
    private var pageTitle: String {
        period == .month ? "\(calendar.component(.year, from: page))年" : ReportPeriod.month.label(for: page, calendar: calendar)
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(pageTitle).font(.headline)
                Spacer()
                arrow("chevron.left", period == .month ? "上一年" : "上个月") { movePage(-1) }
                arrow("chevron.right", period == .month ? "下一年" : "下个月") { movePage(1) }
                    .disabled(calendar.isDate(page, equalTo: Date(), toGranularity: pageUnit))
            }
            if period == .month {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
                    ForEach(0..<12, id: \.self) { offset in
                        let month = calendar.date(byAdding: .month, value: offset, to: pageStart)!
                        cell(month, text: "\(offset + 1)月", dimmed: false)
                    }
                }
            } else {
                Grid(horizontalSpacing: 4, verticalSpacing: 4) {
                    GridRow {
                        ForEach(["一","二","三","四","五","六","日"], id: \.self) { day in
                            Text(day).font(.caption).foregroundStyle(Palette.muted)
                        }
                    }
                    let first = ReportPeriod.week.interval(containing: pageStart, calendar: calendar).start
                    let lastDay = calendar.date(byAdding: .day, value: -1,
                        to: ReportPeriod.month.interval(containing: page, calendar: calendar).end)!
                    let days = calendar.dateComponents([.day], from: first, to: lastDay).day!
                    ForEach(0...(days / 7), id: \.self) { row in
                        GridRow {
                            ForEach(0..<7, id: \.self) { column in
                                let day = calendar.date(byAdding: .day, value: row * 7 + column, to: first)!
                                cell(day, text: "\(calendar.component(.day, from: day))",
                                     dimmed: !calendar.isDate(day, equalTo: page, toGranularity: .month))
                            }
                        }
                    }
                }
            }
            Divider()
            Button("回到\(period.currentLabel)") { choose(Date()) }
                .buttonStyle(.plain).foregroundStyle(Palette.green).frame(maxWidth: .infinity, alignment: .trailing)
        }.padding(18).frame(width: 332).foregroundStyle(Palette.ink).background(.white)
    }

    private func movePage(_ delta: Int) {
        page = calendar.date(byAdding: pageUnit, value: delta, to: pageStart)!
    }

    private func cell(_ date: Date, text: String, dimmed: Bool) -> some View {
        let interval = period.interval(containing: date, calendar: calendar)
        let selected = interval.start == period.interval(containing: selection, calendar: calendar).start
        let future = interval.start > Date()
        return Button {
            choose(min(date, Date()))
        } label: {
            Text(text).font(.system(size: 14, weight: selected ? .semibold : .regular))
                .frame(maxWidth: .infinity, minHeight: 34)
                .foregroundStyle(selected ? .white : (dimmed || future ? Palette.muted : Palette.ink))
                .background(selected ? Palette.green : .clear, in: RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(future)
            .accessibilityLabel(period.label(for: date, calendar: calendar))
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
