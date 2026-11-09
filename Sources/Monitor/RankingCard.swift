import SwiftUI
import MonitorCore

struct RankingCard: View {
    let kind: ActivityKind
    let items: [UsageSummary]
    var reportLabel = ""
    var selectedApplicationKey: String?
    var showApplication: ((ActivityIdentity) -> Void)?
    var close: (() -> Void)?

    @State private var query = ""
    @State private var highlighted: String?
    private let previewCount = 5

    var body: some View {
        let shares = UsageShare.make(items, limit: previewCount)
        let total = shares.reduce(0) { $0 + $1.seconds }
        VStack(alignment: .leading, spacing: 12) {
            OverviewModuleHeader(module: .ranking(kind), subtitle: "\(items.count) 个", close: close)
            if items.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: kind == .application ? "clock" : "globe").font(.title2)
                    Text(kind == .application ? "所选时段还没有应用记录" : "所选时段还没有网站记录")
                }.font(.callout).foregroundStyle(Palette.muted).frame(maxWidth: .infinity).padding(.vertical, 36)
            } else {
                ViewThatFits(in: .horizontal) {
                    summary(shares, size: UsageShareRing.classicSize)
                    summary(shares, size: UsageShareRing.narrowSize)
                }
                Divider()
                if close == nil {
                    rows(Array(items.prefix(previewCount)), shares: shares, total: total)
                } else {
                    let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
                    let matches = search.isEmpty ? items : items.filter { $0.name.localizedCaseInsensitiveContains(search) }
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("使用排行").font(.system(size: 13, weight: .semibold))
                            Text(reportLabel).font(.system(size: 10)).foregroundStyle(Palette.muted)
                        }
                        Spacer()
                        Image(systemName: "magnifyingglass").foregroundStyle(Palette.muted)
                        TextField(kind == .application ? "搜索应用名称" : "搜索网站域名", text: $query)
                            .textFieldStyle(.roundedBorder).frame(maxWidth: 190)
                    }
                    if matches.isEmpty {
                        Text("没有匹配的\(kind == .application ? "应用" : "网站")")
                            .foregroundStyle(Palette.muted).frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            rows(matches, shares: shares, total: total).padding(.trailing, 6)
                        }.id(search)
                    }
                }
            }
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func summary(_ shares: [UsageShare], size: CGFloat) -> some View {
        HStack(spacing: 13) {
            UsageShareRing(shares: shares, kind: kind, highlighted: $highlighted, size: size)
            if let first = shares.first {
                VStack(alignment: .leading, spacing: 4) {
                    Text(first.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.ink)
                        .lineLimit(1).minimumScaleFactor(0.85).truncationMode(.middle).help(first.name)
                    Text("占\(kind == .application ? "前台" : "网站")时长 \(UsageShare.percentText(first.fraction))")
                        .font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.ink)
                    if let second = shares.dropFirst().first {
                        let remaining = shares.dropFirst().reduce(0) { $0 + $1.seconds }
                        if first.fraction >= 0.5, remaining > 0 {
                            let ratio = String(format: "%.1f", first.seconds / remaining)
                            Text("约是其余\(kind == .application ? "应用" : "网站")合计的 \(ratio) 倍。")
                        } else {
                            Text("前两项合计占 \(UsageShare.percentText(first.fraction + second.fraction))。")
                        }
                    }
                }
                .font(.system(size: 11)).foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minWidth: 100, maxWidth: .infinity, alignment: .leading)
            }
        }
        // Select the ring size by the card width, independently of the current names or percentages.
        .frame(idealWidth: size + 13 + 100, maxWidth: .infinity, alignment: .leading)
    }

    private func rows(_ items: [UsageSummary], shares: [UsageShare], total: Double) -> some View {
        LazyVStack(spacing: 6) {
            ForEach(items) { item in
                let share = shares.first { $0.key == item.key }
                let shareKey = share?.key ?? UsageShare.otherKey
                let row = rankingRow(item, maximum: self.items.first?.seconds ?? 1,
                                     color: SharePalette.color(slot: share?.slot),
                                     fraction: item.seconds / max(total, 1), highlighted: highlighted == shareKey)
                    .accessibilityIdentifier("ranking-row-\(item.key)")
                    .onHover { inside in
                        if inside { highlighted = shareKey }
                        else if highlighted == shareKey { highlighted = nil }
                    }
                if kind == .application, close != nil, let showApplication {
                    Button { showApplication(ActivityIdentity(key: item.key, name: item.name)) } label: { row }
                        .buttonStyle(.plain).accessibilityLabel("查看\(item.name)的使用时间段")
                } else {
                    row
                }
            }
        }
    }

    private func rankingRow(_ item: UsageSummary, maximum: Double,
                            color: Color, fraction: Double, highlighted: Bool) -> some View {
        HStack(spacing: 10) {
            ActivityIcon(key: item.key, kind: kind).frame(width: 23, height: 23)
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Circle().fill(color).frame(width: 7, height: 7)
                    Text(item.name).font(.system(size: 12, weight: .medium)).lineLimit(1).help(item.name)
                    Spacer(minLength: 4)
                    Text(durationText(item.seconds)).font(.system(size: 10)).foregroundStyle(Palette.muted).monospacedDigit()
                    Text(UsageShare.percentText(fraction)).font(.system(size: 10)).foregroundStyle(Palette.muted.opacity(0.8))
                        .monospacedDigit().frame(width: 30, alignment: .trailing)
                }
                GeometryReader { geometry in
                    Capsule().fill(Palette.background)
                    Capsule().fill(color.opacity(0.85))
                        .frame(width: max(3, geometry.size.width * item.seconds / max(maximum, 1)))
                }.frame(height: 4)
            }
            if kind == .application, close != nil, showApplication != nil {
                Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(Palette.muted)
            }
        }.padding(.vertical, 4).contentShape(Rectangle())
            .background(rowBackground(item, highlighted: highlighted), in: RoundedRectangle(cornerRadius: 7))
    }

    private func rowBackground(_ item: UsageSummary, highlighted: Bool) -> Color {
        if kind == .application && selectedApplicationKey == item.key { return Palette.green.opacity(0.06) }
        return highlighted ? Palette.background.opacity(0.8) : .clear
    }
}
