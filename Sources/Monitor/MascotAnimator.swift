import AppKit
import Combine
import SwiftUI

@MainActor
final class MascotAnimator: ObservableObject {
    @Published private(set) var frame: MascotFrame = .waiting
    private var subscriptions = Set<AnyCancellable>()
    private var animation: Task<Void, Never>?
    private var applicationID: String?
    private var restingFrame: MascotFrame = .waiting
    private var lastAnimation = -Double.infinity

    func bind(to model: MonitorModel) {
        let motion = NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification)
            .map { _ in NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
            .prepend(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        Publishers.CombineLatest4(model.$currentApplicationID, model.$paused, model.$screenUnavailable, model.$storageError)
            .combineLatest(model.$mascotAnimationsEnabled, motion)
            .sink { [weak self] state, enabled, reduced in
                let (id, paused, unavailable, error) = state
                let face: MascotFrame = error != nil ? .waiting : (paused || unavailable ? .sleeping : (id == nil ? .waiting : .awake))
                self?.update(applicationID: id, resting: face, animate: enabled && !reduced)
            }.store(in: &subscriptions)
    }

    /// Identity changes, not repeated five-second samples or browser heartbeats, trigger a blink.
    func update(applicationID id: String?, resting: MascotFrame, animate: Bool,
                now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        let previousID = applicationID
        let previousResting = restingFrame
        applicationID = id
        restingFrame = resting
        if resting != .awake || !animate {
            cancelAnimation()
            frame = resting
            return
        }
        if previousResting != resting { cancelAnimation(); frame = resting }
        guard let id, let previousID, id != previousID,
              previousResting == .awake, now - lastAnimation >= 1.2 else { return }
        cancelAnimation()
        lastAnimation = now
        frame = .focus
        animation = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(80))
                self?.frame = .blink
                try await Task.sleep(for: .milliseconds(140))
                self?.frame = .focus
                try await Task.sleep(for: .milliseconds(140))
                guard let self else { return }
                self.frame = self.restingFrame
                self.animation = nil
            } catch { /* A state change or shutdown immediately restores the resting face. */ }
        }
    }

    private func cancelAnimation() { animation?.cancel(); animation = nil }
    func stop() { cancelAnimation(); subscriptions.removeAll(); frame = restingFrame }
    deinit { animation?.cancel() }
}

struct MascotAvatar: View {
    @ObservedObject var animator: MascotAnimator
    var size: CGFloat = 48
    private static let frames = Dictionary(uniqueKeysWithValues: MascotFrame.allCases.map {
        ($0, MascotArtwork.image(frame: $0))
    })
    var body: some View {
        Image(nsImage: Self.frames[animator.frame]!)
            .resizable().interpolation(.high).scaledToFit().frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct BrandPortrait: View {
    private static let portrait: NSImage = {
        if let url = Bundle.main.resourceURL?.appendingPathComponent("Brand/app-icon.png"),
           let image = NSImage(contentsOf: url) { return image }
        // SwiftPM's test executable has no application bundle.
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/Brand/app-icon.png")
        return NSImage(contentsOf: source) ?? MascotArtwork.image()
    }()
    var body: some View {
        Image(nsImage: Self.portrait).resizable().interpolation(.high).scaledToFit().accessibilityHidden(true)
    }
}
