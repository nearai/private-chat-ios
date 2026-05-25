import AppKit
import Foundation

guard CommandLine.arguments.count == 6 else {
    fputs("Usage: render-scene-frame.swift <input.png> <output.png> <title.txt> <caption.txt> <scene-id>\n", stderr)
    exit(2)
}

let inputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
let titleURL = URL(fileURLWithPath: CommandLine.arguments[3])
let captionURL = URL(fileURLWithPath: CommandLine.arguments[4])
let sceneID = CommandLine.arguments[5]

let title = (try? String(contentsOf: titleURL, encoding: .utf8))?
    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
let caption = (try? String(contentsOf: captionURL, encoding: .utf8))?
    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

guard let screenshot = NSImage(contentsOf: inputURL) else {
    fputs("Could not load image: \(inputURL.path)\n", stderr)
    exit(1)
}

let canvasWidth = 1920
let canvasHeight = 1080
let canvas = NSRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight)

guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: canvasWidth,
    pixelsHigh: canvasHeight,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fputs("Could not allocate frame bitmap.\n", stderr)
    exit(1)
}

func aspectFillRect(imageSize: NSSize, target: NSRect) -> NSRect {
    let scale = max(target.width / imageSize.width, target.height / imageSize.height)
    let width = imageSize.width * scale
    let height = imageSize.height * scale
    return NSRect(
        x: target.midX - width / 2,
        y: target.midY - height / 2,
        width: width,
        height: height
    )
}

func aspectFitRect(imageSize: NSSize, target: NSRect) -> NSRect {
    let scale = min(target.width / imageSize.width, target.height / imageSize.height)
    let width = imageSize.width * scale
    let height = imageSize.height * scale
    return NSRect(
        x: target.midX - width / 2,
        y: target.midY - height / 2,
        width: width,
        height: height
    )
}

guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fputs("Could not create graphics context.\n", stderr)
    exit(1)
}
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
context.cgContext.setShouldAntialias(true)
context.cgContext.setAllowsAntialiasing(true)

NSColor(calibratedRed: 0.027, green: 0.067, blue: 0.122, alpha: 1.0).setFill()
canvas.fill()

let bgRect = aspectFillRect(imageSize: screenshot.size, target: canvas)
screenshot.draw(in: bgRect, from: .zero, operation: .sourceOver, fraction: 0.18)
NSColor(calibratedRed: 0.027, green: 0.067, blue: 0.122, alpha: 0.72).setFill()
canvas.fill()

let panelRect = NSRect(x: 0, y: 0, width: 850, height: canvasHeight)
NSColor(calibratedRed: 0.027, green: 0.067, blue: 0.122, alpha: 0.96).setFill()
panelRect.fill()

let phoneTarget = NSRect(x: 1188, y: 48, width: 600, height: 984)
let phoneRect = aspectFitRect(imageSize: screenshot.size, target: phoneTarget)
let shadow = NSShadow()
shadow.shadowBlurRadius = 36
shadow.shadowOffset = NSSize(width: 0, height: -12)
shadow.shadowColor = NSColor.black.withAlphaComponent(0.42)
shadow.set()

let rounded = NSBezierPath(roundedRect: phoneRect, xRadius: 38, yRadius: 38)
NSColor.black.withAlphaComponent(0.18).setFill()
rounded.fill()

NSGraphicsContext.saveGraphicsState()
rounded.addClip()
screenshot.draw(in: phoneRect, from: .zero, operation: .sourceOver, fraction: 1.0)
NSGraphicsContext.restoreGraphicsState()

NSShadow().set()
NSColor.white.withAlphaComponent(0.16).setStroke()
rounded.lineWidth = 2
rounded.stroke()

let titleParagraph = NSMutableParagraphStyle()
titleParagraph.lineSpacing = 4
titleParagraph.alignment = .left
let captionParagraph = NSMutableParagraphStyle()
captionParagraph.lineSpacing = 8
captionParagraph.alignment = .left

let titleAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 54, weight: .bold),
    .foregroundColor: NSColor.white,
    .paragraphStyle: titleParagraph
]
let captionAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 32, weight: .regular),
    .foregroundColor: NSColor(calibratedRed: 0.847, green: 0.890, blue: 0.941, alpha: 1.0),
    .paragraphStyle: captionParagraph
]
let footerAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 24, weight: .semibold),
    .foregroundColor: NSColor(calibratedRed: 0.514, green: 0.863, blue: 1.0, alpha: 1.0)
]
let sceneAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.monospacedSystemFont(ofSize: 18, weight: .semibold),
    .foregroundColor: NSColor(calibratedRed: 0.541, green: 0.592, blue: 0.655, alpha: 1.0)
]

(title as NSString).draw(
    with: NSRect(x: 72, y: 850, width: 710, height: 150),
    options: [.usesLineFragmentOrigin, .usesFontLeading],
    attributes: titleAttributes
)
(caption as NSString).draw(
    with: NSRect(x: 74, y: 560, width: 720, height: 260),
    options: [.usesLineFragmentOrigin, .usesFontLeading],
    attributes: captionAttributes
)
("NEAR Private Chat for iOS" as NSString).draw(
    with: NSRect(x: 74, y: 92, width: 520, height: 40),
    options: [.usesLineFragmentOrigin],
    attributes: footerAttributes
)
(sceneID as NSString).draw(
    with: NSRect(x: 74, y: 60, width: 120, height: 28),
    options: [.usesLineFragmentOrigin],
    attributes: sceneAttributes
)

NSGraphicsContext.restoreGraphicsState()

guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
    fputs("Could not encode PNG.\n", stderr)
    exit(1)
}

do {
    try FileManager.default.createDirectory(
        at: outputURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try pngData.write(to: outputURL)
} catch {
    fputs("Could not write \(outputURL.path): \(error)\n", stderr)
    exit(1)
}
