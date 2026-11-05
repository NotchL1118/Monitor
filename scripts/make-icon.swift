import AppKit

let destination = URL(fileURLWithPath: CommandLine.arguments[1])
let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Resources/Brand/app-icon-source.png")
guard let artwork = NSImage(contentsOf: source) else { fatalError("Missing approved A artwork: \(source.path)") }
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSGraphicsContext.current?.imageInterpolation = .high
// Apply the final app-icon mask at export, with even transparent margins.
NSBezierPath(roundedRect: NSRect(x: 94, y: 94, width: 836, height: 836), xRadius: 180, yRadius: 180).addClip()
artwork.draw(in: NSRect(x: 0, y: 0, width: 1024, height: 1024))
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: destination)
