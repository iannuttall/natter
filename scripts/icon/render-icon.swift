import AppKit

guard CommandLine.arguments.count == 4,
      let side = Int(CommandLine.arguments[2]) else {
    print("usage: render-icon <app-bundle> <size> <output.png>")
    exit(2)
}

let appPath = CommandLine.arguments[1]
let outputPath = CommandLine.arguments[3]
let icon = NSWorkspace.shared.icon(forFile: appPath)
icon.size = NSSize(width: side, height: side)

guard let representation = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: side,
    pixelsHigh: side,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    print("could not allocate a \(side)px bitmap")
    exit(1)
}

representation.size = NSSize(width: side, height: side)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: representation)
NSGraphicsContext.current?.imageInterpolation = .high
icon.draw(
    in: NSRect(x: 0, y: 0, width: side, height: side),
    from: .zero,
    operation: .sourceOver,
    fraction: 1
)
NSGraphicsContext.restoreGraphicsState()

guard let png = representation.representation(using: .png, properties: [:]) else {
    print("could not encode the render")
    exit(1)
}

do {
    try png.write(to: URL(fileURLWithPath: outputPath))
} catch {
    print("could not write \(outputPath): \(error.localizedDescription)")
    exit(1)
}
