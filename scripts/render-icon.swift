// Renders the Hum app icon, sidebar logo and menu-bar template from vector shapes.
// usage: swift scripts/render-icon.swift <repo-root>
// Mark: three rounded sound bars that end in a thin text caret ("voice becomes text").
import AppKit
import CoreGraphics

let root = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let assets = "\(root)/speaktype/Assets.xcassets"

/// Mark geometry in bar-width units (owner reference, 2026-11-25): four straight bars with
/// fully round ends — short, tall reaching up, tall reaching down, short.
/// Each bar is (top, bottom) measured from the top of the mark; total height 6.4, width 5.35.
private let markBars: [(top: CGFloat, bottom: CGFloat)] = [(2.1, 4.3), (0, 4.3), (2.1, 6.4), (2.1, 4.3)]
private let markGap: CGFloat = 0.45
let markAspect: CGFloat = (4 + 3 * markGap) / 6.4  // width / height

/// Draws the mark into `rect` (the mark's bounding box, aspect `markAspect`) in `color`.
func drawMark(_ ctx: CGContext, in rect: CGRect, color: CGColor) {
    ctx.setFillColor(color)
    let u = rect.height / 6.4
    for (i, bar) in markBars.enumerated() {
        let x = rect.minX + CGFloat(i) * u * (1 + markGap)
        // CoreGraphics y grows upward, the design is measured from the top.
        let r = CGRect(x: x, y: rect.maxY - bar.bottom * u, width: u, height: (bar.bottom - bar.top) * u)
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: u / 2, cornerHeight: u / 2, transform: nil))
        ctx.fillPath()
    }
}

/// The largest mark rect of the right aspect, centered in `box`, filling `fraction` of its height.
func markRect(in box: CGRect, heightFraction fraction: CGFloat) -> CGRect {
    let h = box.height * fraction
    let w = h * markAspect
    return CGRect(x: box.midX - w / 2, y: box.midY - h / 2, width: w, height: h)
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
    drawMark(ctx, in: markRect(in: tile, heightFraction: 0.52), color: white)
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
    drawMark(ctx, in: markRect(in: CGRect(x: 0, y: 0, width: s, height: s), heightFraction: 0.56), color: white)
}, "\(assets)/AppLogo.imageset/logo.png")
// Template mark: black on transparent; the asset is marked as a template so views tint it.
write(png(size: 512) { ctx, s in
    drawMark(ctx, in: markRect(in: CGRect(x: 0, y: 0, width: s, height: s), heightFraction: 0.9),
             color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
}, "\(assets)/MenuBarWave.imageset/wave-sound.png")

// macOS 26 icon (Icon Composer format). Older-format icons get a grey frame on macOS 26,
// so the app ships this too: a solid ink fill with the white mark as one vector layer.
// The system draws the rounded shape, edge and shadow itself.
let iconDir = "\(root)/speaktype/AppIcon.icon"
try! FileManager.default.createDirectory(atPath: "\(iconDir)/Assets", withIntermediateDirectories: true)
let canvas: CGFloat = 1024
let mark = markRect(in: CGRect(x: 0, y: 0, width: canvas, height: canvas), heightFraction: 0.52)
let unit = mark.height / 6.4
var svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"1024\" height=\"1024\" viewBox=\"0 0 1024 1024\">\n"
for (i, bar) in markBars.enumerated() {
    let x = mark.minX + CGFloat(i) * unit * (1 + markGap)
    let y = mark.minY + bar.top * unit  // SVG y grows downward, like the design
    svg += String(format: "  <rect x=\"%.2f\" y=\"%.2f\" width=\"%.2f\" height=\"%.2f\" rx=\"%.2f\" fill=\"#FFFFFF\"/>\n",
                  x, y, unit, (bar.bottom - bar.top) * unit, unit / 2)
}
svg += "</svg>\n"
write(svg.data(using: .utf8)!, "\(iconDir)/Assets/mark.svg")
let iconJSON = """
{
  "fill" : {
    "solid" : "srgb:0.06700,0.06700,0.06700,1.00000"
  },
  "groups" : [
    {
      "layers" : [
        {
          "glass" : false,
          "image-name" : "mark.svg",
          "name" : "mark"
        }
      ],
      "shadow" : {
        "kind" : "neutral",
        "opacity" : 0.3
      },
      "translucency" : {
        "enabled" : false,
        "value" : 0
      }
    }
  ],
  "supported-platforms" : {
    "squares" : [
      "macOS"
    ]
  }
}

"""
write(iconJSON.data(using: .utf8)!, "\(iconDir)/icon.json")
print("icons written")
