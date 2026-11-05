import AppKit
import Combine
import SwiftUI

@MainActor
final class MascotState: ObservableObject {
    @Published private(set) var frame: MascotFrame = .waiting
    private var subscription: AnyCancellable?

    func bind(to model: MonitorModel) {
        subscription = Publishers.CombineLatest4(model.$currentApplicationID, model.$paused,
                                                 model.$screenUnavailable, model.$storageError)
            .map { id, paused, unavailable, error -> MascotFrame in
                error != nil ? .waiting : (paused || unavailable ? .sleeping : (id == nil ? .waiting : .awake))
            }
            .removeDuplicates()
            .sink { [weak self] in self?.frame = $0 }
    }

    func stop() { subscription = nil }
}

struct MascotAvatar: View {
    @ObservedObject var state: MascotState
    var size: CGFloat = 48
    private static let frames = Dictionary(uniqueKeysWithValues: MascotFrame.allCases.map {
        ($0, MascotArtwork.image(frame: $0))
    })
    var body: some View {
        Image(nsImage: Self.frames[state.frame]!)
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
