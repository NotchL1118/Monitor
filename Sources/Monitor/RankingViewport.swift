import AppKit
import SwiftUI

/// The native view covers the card, including its title and padding. Only the rows move.
struct RankingViewport<Rows: View>: NSViewRepresentable {
    /// Distance from the card's top edge to the first row; the title and ring sit above it.
    var topInset: CGFloat = 60
    @ViewBuilder var rows: () -> Rows

    func makeNSView(context: Context) -> RankingCardSurface<Rows> {
        RankingCardSurface(rows: rows(), topInset: topInset)
    }

    func updateNSView(_ view: RankingCardSurface<Rows>, context: Context) {
        view.document.rootView = rows()
        view.topInset = topInset
    }

    static func dismantleNSView(_ view: RankingCardSurface<Rows>, coordinator: ()) {
        view.removeMonitor()
    }
}

final class RankingCardSurface<Rows: View>: NSView {
    let scroller = NSScrollView()
    let document: NSHostingView<Rows>
    private var monitor: Any?
    private var topConstraint: NSLayoutConstraint!
    var topInset: CGFloat {
        get { topConstraint.constant }
        set { if topConstraint.constant != newValue { topConstraint.constant = newValue } }
    }

    init(rows: Rows, topInset: CGFloat = 60) {
        document = NSHostingView(rootView: rows)
        super.init(frame: .zero)
        scroller.drawsBackground = false
        scroller.hasHorizontalScroller = false
        scroller.hasVerticalScroller = false
        scroller.verticalScrollElasticity = .none
        scroller.horizontalScrollElasticity = .none
        scroller.verticalLineScroll = 16
        scroller.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroller)
        let clip = scroller.contentView
        scroller.documentView = document
        document.sizingOptions = [.intrinsicContentSize]
        document.translatesAutoresizingMaskIntoConstraints = false
        topConstraint = scroller.topAnchor.constraint(equalTo: topAnchor, constant: topInset)
        NSLayoutConstraint.activate([
            topConstraint,
            scroller.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -22),
            scroller.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 22),
            scroller.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -22),
            document.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            document.topAnchor.constraint(equalTo: clip.topAnchor),
            document.widthAnchor.constraint(equalTo: clip.widthAnchor)
        ])
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeMonitor()
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, let window = self.window, event.window === window else { return event }
            let point = self.convert(window.mouseLocationOutsideOfEventStream, from: nil)
            return self.handleWheel(event, at: point) ? nil : event
        }
    }

    func removeMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    func handleWheel(_ event: NSEvent, at point: NSPoint) -> Bool {
        // Recheck the pointer for every event, including ongoing gestures and inertia.
        guard !isHiddenOrHasHiddenAncestor, bounds.intersection(visibleRect).contains(point) else { return false }
        scrollRows(with: event)
        return true
    }

    private func scrollRows(with event: NSEvent) {
        let clip = scroller.contentView
        let step = event.hasPreciseScrollingDeltas ? 1 : scroller.verticalLineScroll
        var bounds = clip.bounds
        bounds.origin.y += event.scrollingDeltaY * step * (clip.isFlipped ? -1 : 1)
        clip.scroll(to: clip.constrainBoundsRect(bounds).origin)
        scroller.reflectScrolledClipView(clip)
    }
}
