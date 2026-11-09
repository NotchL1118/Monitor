import SwiftUI
import MonitorCore

enum OverviewModule: Hashable {
    case ranking(ActivityKind)
    case timeline

    var title: String {
        switch self {
        case .ranking(.application): return "应用"
        case .ranking(.website): return "域名"
        case .timeline: return "时间足迹"
        }
    }

    var accent: Color { self == .ranking(.website) ? Palette.orange : Palette.green }
}

struct OverviewModuleBounds: PreferenceKey {
    static let defaultValue: [OverviewModule: Anchor<CGRect>] = [:]
    static func reduce(value: inout [OverviewModule: Anchor<CGRect>], nextValue: () -> [OverviewModule: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

struct OverviewModuleHeader: View {
    let module: OverviewModule
    let subtitle: String
    var close: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            Text(module.title).font(.system(size: 17, weight: .semibold))
            Text(subtitle).font(.system(size: 11)).foregroundStyle(Palette.muted)
            Spacer()
            if let close {
                Button(action: close) { symbol("xmark") }
                    .buttonStyle(.plain).keyboardShortcut(.cancelAction)
                    .accessibilityLabel("关闭\(module.title)明细")
            } else {
                symbol("arrow.up.right").accessibilityHidden(true)
            }
        }
    }

    private func symbol(_ name: String) -> some View {
        Image(systemName: name).font(.system(size: 11, weight: .semibold))
            .foregroundStyle(module.accent).frame(width: 28, height: 28)
            .background(module.accent.opacity(0.10), in: Circle())
    }
}

extension View {
    func overviewCardSurface(_ module: OverviewModule) -> some View {
        let shape = RoundedRectangle(cornerRadius: 16)
        return self.background(LinearGradient(colors: [module.accent.opacity(0.05), .white],
                                               startPoint: .topLeading, endPoint: .bottomTrailing))
            .background(.white).clipShape(shape)
            .overlay(shape.strokeBorder(module.accent.opacity(0.13), lineWidth: 1))
    }
}

/// The home card keeps its place in the page. Its live bounds also serve as the
/// destination on dismissal, including after the window has been resized.
struct OverviewModuleOverlay<Content: View>: View {
    let module: OverviewModule
    let source: CGRect
    let size: CGSize
    let dismiss: () -> Void
    @ViewBuilder let content: (Bool, @escaping () -> Void) -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = false
    @State private var closing = false

    private var destination: CGRect {
        let width = min(720, max(1, size.width - 64))
        let height = min(600, max(1, size.height - 64))
        return CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2, width: width, height: height)
    }

    var body: some View {
        let rect = expanded ? destination : source
        ZStack(alignment: .topLeading) {
            Button(action: close) {
                Color.black.opacity(expanded ? 0.22 : 0).contentShape(Rectangle())
            }.buttonStyle(.plain).focusable(false).accessibilityHidden(true)
            content(expanded, close)
                .frame(width: rect.width, height: rect.height, alignment: .topLeading)
                .overviewCardSurface(module)
                .contentShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: .black.opacity(expanded ? 0.15 : 0), radius: 22, y: 8)
                .position(x: rect.midX, y: rect.midY)
        }
        .frame(width: size.width, height: size.height)
        .accessibilityAddTraits(.isModal)
        .onExitCommand { close() }
        .task {
            await Task.yield()
            guard !Task.isCancelled, !closing else { return }
            withAnimation(reduceMotion ? nil : .timingCurve(0.23, 0.82, 0.26, 1, duration: 0.42)) { expanded = true }
        }
    }

    private func close() {
        guard !closing else { return }
        closing = true
        withAnimation(reduceMotion ? nil : .timingCurve(0.23, 0.82, 0.26, 1, duration: 0.34)) {
            expanded = false
        } completion: { dismiss() }
    }
}
