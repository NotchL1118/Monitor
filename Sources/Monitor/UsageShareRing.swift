import Charts
import SwiftUI
import MonitorCore

enum SharePalette {
    private static let opacity = [1.0, 0.74, 0.54, 0.39, 0.28]

    static func color(slot: Int?, kind: ActivityKind) -> Color {
        guard let slot, opacity.indices.contains(slot) else { return Palette.muted.opacity(0.28) }
        return OverviewModule.ranking(kind).accent.opacity(opacity[slot])
    }
}

/// Ring chart of the selected period's time share. Hovering a sector highlights it and the matching rows.
struct UsageShareRing: View {
    static let size: CGFloat = 88
    private static let innerRatio = 0.68
    private static let outerRatio = 0.96

    let shares: [UsageShare]
    let kind: ActivityKind
    @Binding var highlighted: String?

    private var radius: CGFloat { Self.size / 2 }

    var body: some View {
        ZStack {
            Chart(shares) { share in
                SectorMark(angle: .value("时长", share.seconds),
                           innerRadius: .ratio(Self.innerRatio), outerRadius: .ratio(Self.outerRatio),
                           angularInset: shares.count > 1 ? 1.2 : 0)
                    .cornerRadius(2)
                    .foregroundStyle(SharePalette.color(slot: share.slot, kind: kind))
                    .opacity(dimmed(share.key) ? 0.3 : 1)
            }
            .chartLegend(.hidden)
            center
        }
        .frame(width: Self.size, height: Self.size)
        .contentShape(Circle())
        .onContinuousHover { phase in
            switch phase {
            case .active(let point): highlighted = share(at: point)?.key
            case .ended: highlighted = nil
            }
        }
        .animation(.easeOut(duration: 0.15), value: highlighted)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(kind == .application ? "应用时间占比" : "网站时间占比")
        .accessibilityValue(shares.map { "\($0.name) \(UsageShare.percentText($0.fraction))" }.joined(separator: "，"))
    }

    private func dimmed(_ key: String) -> Bool { highlighted != nil && highlighted != key }

    @ViewBuilder private var center: some View {
        if let share = shares.first(where: { $0.key == highlighted }) ?? shares.first {
            Text(UsageShare.percentText(share.fraction))
                .font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundStyle(Palette.ink)
                .monospacedDigit().help(share.name)
        }
    }

    private func share(at point: CGPoint) -> UsageShare? {
        let dx = point.x - radius, dy = point.y - radius
        let distance = (dx * dx + dy * dy).squareRoot()
        guard distance >= radius * Self.innerRatio - 2, distance <= radius * Self.outerRatio + 2 else { return nil }
        let angle = atan2(dx, -dy)
        return UsageShare.share(at: angle / (2 * .pi), in: shares)
    }
}

/// One-line summary next to the ring, e.g. "ChatGPT 占了 71%，是其余应用加起来的 2.5 倍。"
func shareHeadline(_ shares: [UsageShare], kind: ActivityKind) -> Text {
    let noun = kind == .application ? "应用" : "网站"
    guard let first = shares.first else { return Text("") }
    guard shares.count > 1 else {
        return Text("所选时段只用了 ") + Text(first.name).bold() + Text("。")
    }
    if first.fraction >= 0.5 {
        let ratio = first.fraction / max(1 - first.fraction, 0.0001)
        return Text(first.name).bold() + Text(" 占了 ") + Text(UsageShare.percentText(first.fraction)).bold()
            + Text("，是其余\(noun)加起来的 \(String(format: "%.1f", ratio)) 倍。")
    }
    let second = shares[1]
    return Text("前两名 ") + Text(first.name).bold() + Text(" 和 ") + Text(second.name).bold() + Text(" 合计 ")
        + Text(UsageShare.percentText(first.fraction + second.fraction)).bold() + Text("，时间分布相对分散。")
}

/// Short duration for the module summary: "5小时53分", "33分钟", "50秒".
func compactDuration(_ seconds: Double) -> String {
    let value = max(0, Int(seconds))
    if value < 60 { return "\(value)秒" }
    if value < 3600 { return "\(value / 60)分钟" }
    let minutes = (value % 3600) / 60
    return minutes == 0 ? "\(value / 3600)小时" : "\(value / 3600)小时\(minutes)分"
}
