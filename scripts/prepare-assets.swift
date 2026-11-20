import AppKit
import Foundation

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let destination = root.appendingPathComponent("App/Resources/Assets.xcassets")
let fm = FileManager.default
func json(_ object: Any, at url: URL) throws { try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]).write(to: url) }
func copy(_ source: URL, to target: URL) throws { if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }; try fm.copyItem(at: source, to: target) }
func imageSet(_ name: String, source: String, points: Int? = nil) throws {
    let folder = destination.appendingPathComponent(name + ".imageset"); try fm.createDirectory(at: folder, withIntermediateDirectories: true)
    // Each generated image set has exactly one source. Remove earlier generated PNG variants.
    for old in try fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) where old.pathExtension == "png" && old.lastPathComponent != source { try fm.removeItem(at: old) }
    let input = root.appendingPathComponent("assets/images/" + source), output = folder.appendingPathComponent(source)
    if let points {
        let original = NSImage(contentsOf: input)!.cgImage(forProposedRect: nil, context: nil, hints: nil)!
        let size = points * 2
        let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let sourceContext = CGContext(data: nil, width: original.width, height: original.height, bitsPerComponent: 8, bytesPerRow: original.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        sourceContext.draw(original, in: CGRect(x: 0, y: 0, width: original.width, height: original.height))
        let pixels = sourceContext.data!.assumingMemoryBound(to: UInt8.self)
        var left = original.width, right = 0, top = original.height, bottom = 0
        for y in 0..<original.height { for x in 0..<original.width { if pixels[(y * original.width + x) * 4 + 3] > 16 { left = min(left, x); right = max(right, x); top = min(top, y); bottom = max(bottom, y) } } }
        let tight = sourceContext.makeImage()!.cropping(to: CGRect(x: left, y: top, width: right - left + 1, height: bottom - top + 1))!
        let scale = Double(size - 8) / Double(max(tight.width, tight.height))
        let width = Double(tight.width) * scale, height = Double(tight.height) * scale
        context.interpolationQuality = .none
        context.draw(tight, in: CGRect(x: (Double(size) - width) / 2, y: (Double(size) - height) / 2, width: width, height: height))
        try NSBitmapImageRep(cgImage: context.makeImage()!).representation(using: .png, properties: [:])!.write(to: output)
    } else { try copy(input, to: output) }
    try json(["images": [["filename": source, "idiom": "universal", "scale": points == nil ? "1x" : "2x"]], "info": ["author": "xcode", "version": 1]], at: folder.appendingPathComponent("Contents.json"))
}
try imageSet("Sword", source: "enhanced-sword.png")
try imageSet("SwordIcon", source: "enhanced-sword.png", points: 26)
try imageSet("PlainSword", source: "plain-sword.png")
try imageSet("Journal", source: "magic-journal.png")
try imageSet("JournalIcon", source: "magic-journal.png", points: 26)
// Rasterize the same shaded SVG used by native Canvas and the offline preview.
for (name, source) in [("SettingsIcon", "settings")] {
    let svg = try String(contentsOf: root.appendingPathComponent("assets/icons/" + source + ".svg"), encoding: .utf8)
    let expression = try NSRegularExpression(pattern: #"<rect x="([0-9]+)" y="([0-9]+)" width="([0-9]+)" height="([0-9]+)" fill="(#[0-9a-fA-F]{6})""#)
    let context = CGContext(data: nil, width: 52, height: 52, bitsPerComponent: 8, bytesPerRow: 52 * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setShouldAntialias(false)
    for match in expression.matches(in: svg, range: NSRange(svg.startIndex..., in: svg)) {
        let v = (1...4).map { Double(svg[Range(match.range(at: $0), in: svg)!])! * 2.75 }
        let hex = String(svg[Range(match.range(at: 5), in: svg)!].dropFirst()), rgb = UInt32(hex, radix: 16)!
        context.setFillColor(red: CGFloat((rgb >> 16) & 255) / 255, green: CGFloat((rgb >> 8) & 255) / 255, blue: CGFloat(rgb & 255) / 255, alpha: 1)
        context.fill(CGRect(x: 4 + v[0], y: 48 - v[1] - v[3], width: v[2], height: v[3]))
    }
    let folder = destination.appendingPathComponent(name + ".imageset"); try fm.createDirectory(at: folder, withIntermediateDirectories: true)
    try NSBitmapImageRep(cgImage: context.makeImage()!).representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent("icon.png"))
    try json(["images": [["filename": "icon.png", "idiom": "universal", "scale": "2x"]], "properties": ["template-rendering-intent": "original"], "info": ["author": "xcode", "version": 1]], at: folder.appendingPathComponent("Contents.json"))
}
// App Store icon: exactly 1024 square, opaque sRGB; OS applies the outer mask.
let logo = NSImage(contentsOf: root.appendingPathComponent("assets/images/enhanced-app-icon.png"))!.cgImage(forProposedRect: nil, context: nil, hints: nil)!
let iconContext = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 1024 * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
iconContext.interpolationQuality = .none
iconContext.draw(logo, in: CGRect(x: 0, y: 0, width: 1024, height: 1024))
try NSBitmapImageRep(cgImage: iconContext.makeImage()!).representation(using: .png, properties: [:])!.write(to: destination.appendingPathComponent("AppIcon.appiconset/app-icon.png"))
for source in try fm.contentsOfDirectory(at: root.appendingPathComponent("assets/fonts"), includingPropertiesForKeys: nil) { try copy(source, to: root.appendingPathComponent("App/Resources/" + source.lastPathComponent)) }
print("Prepared native illustrations, original pixel icons and licensed fonts")
