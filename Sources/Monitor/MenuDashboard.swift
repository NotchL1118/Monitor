import SwiftUI
import MonitorCore

struct MenuDashboard: View {
    @ObservedObject var model: MonitorModel
    let openHome: () -> Void
    @State private var kind = ActivityKind.application
    private var today: TodaySnapshot { model.today }
    private var rows: [UsageSummary] { kind == .website ? today.sites : today.apps }
    private var status: String {
        if model.storageError != nil { return "记录异常" }
        if model.paused { return "已暂停" }
        return model.recording ? "记录中" : "等待恢复"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                MascotAvatar(state: model.mascot, size: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text("时间足迹").font(.headline)
                    Text(model.recording ? "陪你记下今天" : status).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Button(action: openHome) {
                        HStack(spacing: 4) {
                            Text("打开主页")
                            Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
                        }
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background(.secondary.opacity(0.09), in: RoundedRectangle(cornerRadius: 7))
                        .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    Text(today.date.formatted(model.reportTimeZone.formatStyle.month().day().weekday()))
                        .font(.caption2).foregroundStyle(.secondary)
                        .help(model.reportTimeZone.label)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(model.reportTimeZone == .utcPlus8 ? "今日前台时长 · UTC+8" : "今日前台时长")
                    Spacer()
                    Circle().fill(model.recording ? Color.mint : Color.orange).frame(width: 7, height: 7)
                    Text(status)
                }.font(.caption)
                Text(durationText(today.total)).font(.system(size: 34, weight: .semibold, design: .rounded)).monospacedDigit()
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(today.bars.indices, id: \.self) { i in
                        let seconds = today.bars[i]
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(red: 0.74, green: 0.85, blue: 0.72).opacity(seconds > 0 ? 1 : 0.35))
                            .frame(maxWidth: .infinity)
                            .frame(height: max(1, min(1, seconds / TodaySnapshot.bucketWidth) * 34))
                            .help(durationText(seconds))
                    }
                }.frame(height: 34, alignment: .bottom)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("近三小时前台时长 \(durationText(today.bars.reduce(0, +)))，每柱十分钟")
                HStack {
                    ForEach(0..<4) { i in
                        if i > 0 { Spacer() }
                        Text(today.chartStart.addingTimeInterval(Double(i) * 3600), format: model.reportTimeZone.formatStyle.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
                    }
                }.font(.caption2).monospacedDigit().opacity(0.8)
            }.padding(15).foregroundStyle(.white)
                .background(LinearGradient(colors: [Color(red: 0.14, green: 0.30, blue: 0.24), Palette.green],
                                           startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 12))
            HStack(spacing: 8) {
                metric("网站浏览", durationText(today.browsing))
                metric("使用过的应用", "\(today.apps.count) 个")
            }
            HStack {
                Text("使用排行").font(.headline)
                Spacer()
                SegmentedControl(options: [ActivityKind.website, .application], selection: $kind, compact: true,
                                 title: { $0 == .website ? "网站" : "应用" })
            }
            if rows.isEmpty {
                Text(kind == .website ? (model.browserConnected ? "今天还没有网站记录" : "连接 Chrome 扩展后显示网站时长") : "今天还没有应用记录")
                    .font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 54)
            } else {
                VStack(spacing: 9) {
                    ForEach(Array(rows.prefix(3).enumerated()), id: \.element.id) { index, item in
                        HStack(spacing: 9) {
                            Text(String(format: "%02d", index + 1)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(item.name).font(.callout.weight(.medium)).lineLimit(1).help(item.name)
                                GeometryReader { geo in
                                    Capsule().fill(.secondary.opacity(0.12))
                                    Capsule().fill(kind == .website ? Palette.orange : Palette.green)
                                        .frame(width: geo.size.width * item.seconds / max(rows.first?.seconds ?? 1, 1))
                                }.frame(height: 3)
                            }
                            Text(durationText(item.seconds)).font(.caption.monospacedDigit())
                        }
                    }
                }
            }
            Divider()
            HStack {
                Text(model.recording ? "当前应用 · \(model.currentApp)" : status).lineLimit(1)
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
        }.padding(16).frame(width: 350).fixedSize(horizontal: false, vertical: true)
            .environment(\.calendar, model.reportCalendar)
            .environment(\.timeZone, model.reportTimeZone.timeZone)
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(size: 20, weight: .semibold, design: .rounded)).monospacedDigit()
        }.padding(.vertical, 9).padding(.horizontal, 12).frame(maxWidth: .infinity, alignment: .leading)
            .background(.secondary.opacity(0.09), in: RoundedRectangle(cornerRadius: 9))
    }
}
