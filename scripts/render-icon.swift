// Renders the Taly app icon, sidebar logo and menu-bar template from vector shapes.
// usage: swift scripts/render-icon.swift <repo-root>
// Mark: three rounded sound bars that end in a thin text caret ("voice becomes text").
import AppKit
import CoreGraphics

let root = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let assets = "\(root)/speaktype/Assets.xcassets"

/// Draws the mark into `rect` (the mark's bounding box) in `color`.
func drawMark(_ ctx: CGContext, in rect: CGRect, color: CGColor, caretWidthRatio: CGFloat = 0.28) {
    ctx.setFillColor(color)
    // Unit design: bar width 1, gap 0.62, caret gap 0.9; heights relative to rect height.
    let barW = rect.width / (3 + 2 * 0.62 + 0.9 + caretWidthRatio)
    let gap = barW * 0.62
    let caretGap = barW * 0.9
    let heights: [CGFloat] = [0.46, 0.84, 0.58]
    var x = rect.minX
    for h in heights {
        let bh = rect.height * h
        let r = CGRect(x: x, y: rect.midY - bh / 2, width: barW, height: bh)
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: barW / 2, cornerHeight: barW / 2, transform: nil))
        ctx.fillPath()
        x += barW + gap
    }
    x += caretGap - gap
    let cw = barW * caretWidthRatio
    let caret = CGRect(x: x, y: rect.minY, width: cw, height: rect.height)
    ctx.addPath(CGPath(roundedRect: caret, cornerWidth: cw / 2, cornerHeight: cw / 2, transform: nil))
    ctx.fillPath()
}

func png(size: Int, _ draw: (CGContext, CGFloat) -> Void) -> Data {
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    draw(ctx, CGFloat(size))
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    return rep.representation(using: .png, properties: [:])!
}

let ink = CGColor(srgbRed: 0.067, green: 0.067, blue: 0.067, alpha: 1)
let white = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)

/// macOS Big Sur+ icon grid: 824pt tile inside a 1024 canvas, ~185pt continuous corners.
func appIcon(_ ctx: CGContext, _ s: CGFloat) {
    let k = s / 1024
    let tile = CGRect(x: 100 * k, y: 100 * k, width: 824 * k, height: 824 * k)
    // Soft shadow like system icons.
    ctx.setShadow(offset: CGSize(width: 0, height: -10 * k), blur: 24 * k,
                  color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.28))
    ctx.setFillColor(ink)
    ctx.addPath(CGPath(roundedRect: tile, cornerWidth: 185 * k, cornerHeight: 185 * k, transform: nil))
    ctx.fillPath()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)
    let markH = 380 * k
    let markW = markH * 1.02
    drawMark(ctx, in: CGRect(x: tile.midX - markW / 2, y: tile.midY - markH / 2, width: markW, height: markH),
             color: white)
}

func write(_ data: Data, _ path: String) {
    try! data.write(to: URL(fileURLWithPath: path))
}

// App icon sizes referenced by AppIcon.appiconset/Contents.json.
for s in [16, 32, 64, 128, 256, 512, 1024] {
    write(png(size: s, appIcon), "\(assets)/AppIcon.appiconset/icon_\(s)x\(s).png")
}
// Sidebar / onboarding logo: full-bleed square (the views clip their own corners).
write(png(size: 512) { ctx, s in
    ctx.setFillColor(ink)
    ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))
    let markH = s * 0.46
    let markW = markH * 1.02
    drawMark(ctx, in: CGRect(x: (s - markW) / 2, y: (s - markH) / 2, width: markW, height: markH), color: white)
}, "\(assets)/AppLogo.imageset/logo.png")
// Template mark: black on transparent; the asset is marked as a template so views tint it.
write(png(size: 512) { ctx, s in
    drawMark(ctx, in: CGRect(x: s * 0.08, y: s * 0.17, width: s * 0.84, height: s * 0.66),
             color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
}, "\(assets)/MenuBarWave.imageset/wave-sound.png")
print("icons written")
