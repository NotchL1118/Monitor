import Charts
import SwiftUI
import MonitorCore

/// Fixed colors by rank, checked for color-vision deficiency on the white card. "Other" stays neutral gray.
enum SharePalette {
    static let slots: [Color] = [
        Color(red: 0.122, green: 0.502, blue: 0.345),
        Color(red: 0.690, green: 0.490, blue: 0.118),
        Color(red: 0.227, green: 0.463, blue: 0.722),
        Color(red: 0.769, green: 0.353, blue: 0.180),
        Color(red: 0.541, green: 0.333, blue: 0.675)
    ]
    static let other = Color(red: 0.765, green: 0.780, blue: 0.749)

    static func color(slot: Int?) -> Color {
        guard let slot, slots.indices.contains(slot) else { return other }
        return slots[slot]
    }
}

/// Ring chart of the selected period's time share. Hovering a sector highlights it and the matching rows.
struct UsageShareRing: View {
    static let size: CGFloat = 210
    private static let innerRatio = 0.52
    private static let outerRatio = 0.82

    let shares: [UsageShare]
    let kind: ActivityKind
    @Binding var highlighted: String?

    private var radius: CGFloat { Self.size / 2 }
    private var total: Double { shares.reduce(0) { $0 + $1.seconds } }

    var body: some View {
        ZStack {
            Chart(shares) { share in
                SectorMark(angle: .value("时长", share.seconds),
                           innerRadius: .ratio(Self.innerRatio), outerRadius: .ratio(Self.outerRatio),
                           angularInset: shares.count > 1 ? 1.2 : 0)
                    .cornerRadius(2)
                    .foregroundStyle(SharePalette.color(slot: share.slot))
                    .opacity(dimmed(share.key) ? 0.3 : 1)
            }
            .chartLegend(.hidden)
            ForEach(shares.filter { !$0.isOther }) { share in
                badge(share)
            }
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
        if let key = highlighted, let share = shares.first(where: { $0.key == key }) {
            VStack(spacing: 2) {
                Text(UsageShare.percentText(share.fraction)).font(.system(size: 19, weight: .semibold, design: .rounded)).foregroundStyle(Palette.ink)
                Text(share.name).font(.system(size: 10)).foregroundStyle(Palette.muted).lineLimit(1)
            }.monospacedDigit().frame(maxWidth: radius * Self.innerRatio * 1.7)
        } else {
            Text(compactDuration(total)).font(.system(size: 17, weight: .semibold, design: .rounded)).foregroundStyle(Palette.ink)
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                .frame(maxWidth: radius * Self.innerRatio * 1.8)
        }
    }

    /// Icons sit on the ring when the arc is wide enough, just outside it when narrower, and are omitted below that.
    @ViewBuilder private func badge(_ share: UsageShare) -> some View {
        let angle = share.middle * 2 * .pi
        let ringRadius = radius * (Self.innerRatio + Self.outerRatio) / 2
        let outsideRadius = radius * Self.outerRatio + 12
        if share.fraction * 2 * .pi * ringRadius >= 30 {
            icon(share, size: 24).position(point(angle, ringRadius))
        } else if share.fraction * 2 * .pi * outsideRadius >= 20 {
            icon(share, size: 17).position(point(angle, outsideRadius))
        }
    }

    private func icon(_ share: UsageShare, size: CGFloat) -> some View {
        ZStack {
            Circle().fill(.white)
            Circle().strokeBorder(Palette.background, lineWidth: 1)
            if kind == .application {
                ActivityIcon(key: share.key, kind: kind).frame(width: size - 3, height: size - 3)
            } else {
                Text(siteInitial(share.name))
                    .font(.system(size: size * 0.45, weight: .semibold)).foregroundStyle(Palette.muted)
            }
        }
        .frame(width: size, height: size)
        .opacity(dimmed(share.key) ? 0.3 : 1)
        .allowsHitTesting(false)
    }

    /// "www.youtube.com" reads "Y", not "W".
    private func siteInitial(_ domain: String) -> String {
        let host = domain.lowercased().hasPrefix("www.") ? String(domain.dropFirst(4)) : domain
        return String((host.isEmpty ? domain : host).prefix(1)).uppercased()
    }

    private func point(_ angle: Double, _ distance: CGFloat) -> CGPoint {
        CGPoint(x: radius + distance * sin(angle), y: radius - distance * cos(angle))
    }

    private func share(at point: CGPoint) -> UsageShare? {
        let dx = point.x - radius, dy = point.y - radius
        let distance = (dx * dx + dy * dy).squareRoot()
        guard distance >= radius * Self.innerRatio - 2, distance <= radius * Self.outerRatio + 22 else { return nil }
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

/// Short duration for the ring center: "5小时53分", "33分钟", "50秒".
func compactDuration(_ seconds: Double) -> String {
    let value = max(0, Int(seconds))
    if value < 60 { return "\(value)秒" }
    if value < 3600 { return "\(value / 60)分钟" }
    let minutes = (value % 3600) / 60
    return minutes == 0 ? "\(value / 3600)小时" : "\(value / 3600)小时\(minutes)分"
}
