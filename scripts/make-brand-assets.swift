import AppKit

@main
enum ExportBrandAssets {
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let icons = root.appendingPathComponent("ChromeExtension/icons", isDirectory: true)
        let brand = root.appendingPathComponent("Resources/Brand", isDirectory: true)
        try FileManager.default.createDirectory(at: icons, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: brand, withIntermediateDirectories: true)
        for frame in [MascotFrame.awake, .sleeping, .waiting] {
            for size in [16, 24, 32, 48, 128, 256] {
                let name = frame == .awake ? "monitor-\(size).png" : "monitor-\(frame.rawValue)-\(size).png"
                try export(MascotArtwork.image(frame: frame, showsLens: size > 48),
                           size: size, to: icons.appendingPathComponent(name))
            }
        }
        for frame in MascotFrame.allCases {
            try export(MascotArtwork.image(frame: frame, template: true), size: 144,
                       to: brand.appendingPathComponent("status-\(frame.rawValue).png"))
        }
    }

    static func export(_ image: NSImage, size: Int, to url: URL) throws {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
        NSGraphicsContext.restoreGraphicsState()
        try bitmap.representation(using: .png, properties: [:])!.write(to: url)
    }
}
