import AppKit
import Foundation

let outputPath = CommandLine.arguments.dropFirst().first ?? "Needle.icns"
let outputURL = URL(fileURLWithPath: outputPath)
let fileManager = FileManager.default
let iconsetURL = outputURL
    .deletingPathExtension()
    .appendingPathExtension("iconset")

try? fileManager.removeItem(at: iconsetURL)
try fileManager.createDirectory(
    at: iconsetURL,
    withIntermediateDirectories: true
)
try fileManager.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)

let sizes: [(points: Int, scale: Int)] = [
    (16, 1),
    (16, 2),
    (32, 1),
    (32, 2),
    (128, 1),
    (128, 2),
    (256, 1),
    (256, 2),
    (512, 1),
    (512, 2)
]

for size in sizes {
    let pixels = size.points * size.scale
    let suffix = size.scale == 1 ? "" : "@\(size.scale)x"
    let filename = "icon_\(size.points)x\(size.points)\(suffix).png"
    let image = drawNeedleIcon(pixelSize: CGFloat(pixels))
    let fileURL = iconsetURL.appendingPathComponent(filename)

    guard let tiff = image.tiffRepresentation,
          let representation = NSBitmapImageRep(data: tiff),
          let png = representation.representation(using: .png, properties: [:]) else {
        throw IconError.renderFailed(filename)
    }

    try png.write(to: fileURL)
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = [
    "-c",
    "icns",
    iconsetURL.path,
    "-o",
    outputURL.path
]
try process.run()
process.waitUntilExit()

try? fileManager.removeItem(at: iconsetURL)

if process.terminationStatus != 0 {
    throw IconError.iconutilFailed(process.terminationStatus)
}

private func drawNeedleIcon(pixelSize: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: pixelSize, height: pixelSize))
    image.lockFocus()
    defer { image.unlockFocus() }

    let bounds = NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize)
    let scale = pixelSize / 1024

    NSColor.clear.setFill()
    bounds.fill()

    let shell = bounds.insetBy(dx: 72 * scale, dy: 72 * scale)
    let shellPath = NSBezierPath(
        roundedRect: shell,
        xRadius: 190 * scale,
        yRadius: 190 * scale
    )
    let backgroundGradient = NSGradient(colors: [
        NSColor(red: 0.07, green: 0.08, blue: 0.08, alpha: 1),
        NSColor(red: 0.17, green: 0.19, blue: 0.18, alpha: 1)
    ])
    backgroundGradient?.draw(in: shellPath, angle: -35)

    NSColor.white.withAlphaComponent(0.10).setStroke()
    shellPath.lineWidth = 8 * scale
    shellPath.stroke()

    let recordRect = NSRect(
        x: 238 * scale,
        y: 214 * scale,
        width: 548 * scale,
        height: 548 * scale
    )
    let recordPath = NSBezierPath(ovalIn: recordRect)
    NSColor(red: 0.02, green: 0.025, blue: 0.025, alpha: 0.92).setFill()
    recordPath.fill()

    NSColor.white.withAlphaComponent(0.12).setStroke()
    recordPath.lineWidth = 10 * scale
    recordPath.stroke()

    for inset in [98, 170, 240] {
        let groove = NSBezierPath(ovalIn: recordRect.insetBy(dx: CGFloat(inset) * scale, dy: CGFloat(inset) * scale))
        NSColor.white.withAlphaComponent(0.06).setStroke()
        groove.lineWidth = 5 * scale
        groove.stroke()
    }

    NSColor(red: 0.74, green: 0.95, blue: 0.86, alpha: 1).setFill()
    NSBezierPath(
        ovalIn: NSRect(
            x: 459 * scale,
            y: 435 * scale,
            width: 106 * scale,
            height: 106 * scale
        )
    ).fill()

    let arm = NSBezierPath()
    arm.move(to: NSPoint(x: 680 * scale, y: 724 * scale))
    arm.line(to: NSPoint(x: 523 * scale, y: 484 * scale))
    arm.lineCapStyle = .round
    arm.lineWidth = 28 * scale
    NSColor.white.withAlphaComponent(0.92).setStroke()
    arm.stroke()

    let stylus = NSBezierPath()
    stylus.move(to: NSPoint(x: 516 * scale, y: 472 * scale))
    stylus.line(to: NSPoint(x: 490 * scale, y: 410 * scale))
    stylus.lineCapStyle = .round
    stylus.lineWidth = 18 * scale
    NSColor(red: 0.72, green: 0.96, blue: 0.84, alpha: 1).setStroke()
    stylus.stroke()

    let head = NSBezierPath(
        roundedRect: NSRect(
            x: 646 * scale,
            y: 694 * scale,
            width: 108 * scale,
            height: 72 * scale
        ),
        xRadius: 24 * scale,
        yRadius: 24 * scale
    )
    NSColor.white.withAlphaComponent(0.88).setFill()
    head.fill()

    return image
}

private enum IconError: Error {
    case renderFailed(String)
    case iconutilFailed(Int32)
}
