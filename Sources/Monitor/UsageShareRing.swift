import Charts
import SwiftUI
import MonitorCore

enum SharePalette {
    // Keep the classic hues; each successive rank has a higher perceptual lightness.
    static let slots: [Color] = [
        Color(red: 0.122, green: 0.502, blue: 0.345),
        Color(red: 0.690, green: 0.490, blue: 0.118),
        Color(red: 0.471, green: 0.632, blue: 0.810),
        Color(red: 0.876, green: 0.653, blue: 0.560),
        Color(red: 0.837, green: 0.763, blue: 0.884)
    ]
    static let other = Color(red: 0.765, green: 0.780, blue: 0.749)

    static func color(slot: Int?) -> Color {
        guard let slot, slots.indices.contains(slot) else { return other }
        return slots[slot]
    }
}

/// Ring chart of the selected period's time share. Hovering a sector highlights it and the matching rows.
struct UsageShareRing: View {
    static let classicSize: CGFloat = 210
    static let narrowSize: CGFloat = 160
    private static let innerRatio = 0.52
    private static let outerRatio = 0.82

    let shares: [UsageShare]
    let kind: ActivityKind
    @Binding var highlighted: String?
    let size: CGFloat

    private var radius: CGFloat { size / 2 }
    private var outerRadius: CGFloat { radius * Self.outerRatio }
    private var innerRadius: CGFloat { outerRadius * Self.innerRatio }
    private var scale: CGFloat { size / Self.classicSize }
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
            ForEach(shares) { share in
                if let frame = badgeFrame(for: share) {
                    badge(share, diameter: frame.width)
                        .position(x: frame.midX, y: frame.midY)
                }
            }
            center
        }
        .frame(width: size, height: size)
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
        .accessibilityValue(([compactDuration(total)] + shares.map { "\($0.name) \(UsageShare.percentText($0.fraction))" }).joined(separator: "，"))
    }

    private func dimmed(_ key: String) -> Bool { highlighted != nil && highlighted != key }

    @ViewBuilder private var center: some View {
        if let key = highlighted, let share = shares.first(where: { $0.key == key }) {
            VStack(spacing: 2) {
                Text(UsageShare.percentText(share.fraction)).font(.system(size: 17 * scale, weight: .semibold, design: .rounded)).foregroundStyle(Palette.ink)
                Text(share.name).font(.system(size: 10)).foregroundStyle(Palette.muted).lineLimit(1)
            }.monospacedDigit().frame(maxWidth: innerRadius * 1.7)
        } else {
            Text(compactDuration(total)).font(.system(size: 15 * scale, weight: .semibold, design: .rounded)).foregroundStyle(Palette.ink)
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                .frame(maxWidth: innerRadius * 1.8)
        }
    }

    /// Keep the whole badge within its sector; a narrow slice has more room at the outer edge.
    func badgeFrame(for share: UsageShare) -> CGRect? {
        guard !share.isOther else { return nil }
        let angle = share.middle * 2 * .pi
        let halfAngle = min(share.fraction, 0.5) * .pi
        let onRing = (innerRadius + outerRadius) / 2
        let smallDiameter = 17 * scale
        let outside = radius - smallDiameter / 2 - 1
        let candidates = [(onRing, 24 * scale, 30 * scale), (outside, smallDiameter, 20 * scale)]
        for (distance, diameter, minimumSpan) in candidates where 2 * distance * sin(halfAngle) >= minimumSpan {
            return CGRect(x: radius + distance * sin(angle) - diameter / 2,
                          y: radius - distance * cos(angle) - diameter / 2,
                          width: diameter, height: diameter)
        }
        return nil
    }

    private func badge(_ share: UsageShare, diameter: CGFloat) -> some View {
        ZStack {
            Circle().fill(.white)
            if kind == .application {
                ActivityIcon(key: share.key, kind: kind).frame(width: diameter - 2, height: diameter - 2)
            } else {
                let name = share.name
                let host = name.lowercased().hasPrefix("www.") ? String(name.dropFirst(4)) : name
                Text(String((host.isEmpty ? name : host).prefix(1)).uppercased())
                    .font(.system(size: max(9, diameter * 0.52), weight: .semibold)).foregroundStyle(Palette.ink)
            }
        }
        .frame(width: diameter, height: diameter)
        .clipShape(Circle()).overlay(Circle().strokeBorder(Palette.background, lineWidth: 1))
        .opacity(dimmed(share.key) ? 0.3 : 1)
        .allowsHitTesting(false)
    }

    private func share(at point: CGPoint) -> UsageShare? {
        let dx = point.x - radius, dy = point.y - radius
        let distance = (dx * dx + dy * dy).squareRoot()
        guard distance >= innerRadius - 2, distance <= radius else { return nil }
        let angle = atan2(dx, -dy)
        return UsageShare.share(at: angle / (2 * .pi), in: shares)
    }
}

/// Short duration for the module summary: "5小时53分", "33分钟", "50秒".
func compactDuration(_ seconds: Double) -> String {
    let value = max(0, Int(seconds))
    if value < 60 { return "\(value)秒" }
    if value < 3600 { return "\(value / 60)分钟" }
    let minutes = (value % 3600) / 60
    return minutes == 0 ? "\(value / 3600)小时" : "\(value / 3600)小时\(minutes)分"
}
