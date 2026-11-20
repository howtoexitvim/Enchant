import AppKit
import Foundation

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let data = try Data(contentsOf: root.appendingPathComponent("source/sword-pixels.json"))
let map = try JSONSerialization.jsonObject(with: data) as! [String: Any]
let grid = map["grid"] as! Int
let palette = map["palette"] as! [String]
let runs = map["runs"] as! [[Int]]
let size = 1024
for name in ["app-icon", "enchanted-sword"] {
    let opaque = name == "app-icon"
    let info = opaque ? CGImageAlphaInfo.noneSkipLast.rawValue : CGImageAlphaInfo.premultipliedLast.rawValue
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4, space: space, bitmapInfo: info)!
    context.setShouldAntialias(false)
    for run in runs {
        if !opaque && run[4] == 0 { continue }
        let x = run[0], y = run[1], width = run[2]
        let hex = palette[run[3]]
        let color = UInt32(hex.dropFirst(), radix: 16)!
        context.setFillColor(red: CGFloat((color >> 16) & 255) / 255, green: CGFloat((color >> 8) & 255) / 255, blue: CGFloat(color & 255) / 255, alpha: 1)
        let x0 = x * size / grid, x1 = (x + width) * size / grid
        let y0 = y * size / grid, y1 = (y + 1) * size / grid
        context.fill(CGRect(x: x0, y: size - y1, width: x1 - x0, height: y1 - y0))
    }
    let rep = NSBitmapImageRep(cgImage: context.makeImage()!)
    let png = rep.representation(using: .png, properties: [:])!
    try png.write(to: root.appendingPathComponent("images/\(name).png"))
    print("Exported \(name).png 1024x1024")
}
