// Writes placeholder tvOS brand art (PNGs) into the asset catalogue.
// Run from anywhere: swift scripts/make-placeholder-art.swift
// Contents.json files are committed by hand; this script only writes the images.
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
let root = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
let brand = root.appendingPathComponent("PerchApp/Resources/Assets.xcassets/AppIcon.brandassets")

let background = CGColor(srgbRed: 11 / 255, green: 11 / 255, blue: 15 / 255, alpha: 1)
let offWhite = CGColor(srgbRed: 0.93, green: 0.92, blue: 0.89, alpha: 1)

func render(width: Int, height: Int, opaque: Bool, fill: Bool, word: Bool, to url: URL) {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let info = opaque ? CGImageAlphaInfo.noneSkipLast.rawValue : CGImageAlphaInfo.premultipliedLast.rawValue
    guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                              bytesPerRow: 0, space: space, bitmapInfo: info) else {
        fatalError("context \(width)x\(height)")
    }
    if fill {
        ctx.setFillColor(background)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    }
    if word {
        let fontSize = CGFloat(min(Double(height) * 0.42, Double(width) * 0.2))
        let font = CTFontCreateWithName("HelveticaNeue-Bold" as CFString, fontSize, nil)
        let attrs: [CFString: Any] = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: offWhite]
        let text = CFAttributedStringCreate(nil, "Perch" as CFString, attrs as CFDictionary)!
        let line = CTLineCreateWithAttributedString(text)
        let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
        ctx.textPosition = CGPoint(x: (CGFloat(width) - bounds.width) / 2 - bounds.minX,
                                   y: (CGFloat(height) - bounds.height) / 2 - bounds.minY)
        CTLineDraw(line, ctx)
    }
    guard let image = ctx.makeImage(),
          let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { fatalError("destination \(url.path)") }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("write \(url.path)") }
    print("wrote \(url.path.replacingOccurrences(of: root.path + "/", with: ""))")
}

func layer(stack: String, name: String, width: Int, height: Int, scale: Int, file: String) {
    let dir = brand.appendingPathComponent("\(stack).imagestack/\(name).imagestacklayer/Content.imageset")
    let isBack = name == "Back"
    render(width: width * scale, height: height * scale, opaque: isBack, fill: isBack, word: !isBack,
           to: dir.appendingPathComponent(file))
}

for (stack, w, h, scales) in [("App Icon", 400, 240, [1, 2]), ("App Icon - App Store", 1280, 768, [1])] {
    for name in ["Back", "Front"] {
        for s in scales {
            let suffix = s == 1 ? "" : "@2x"
            layer(stack: stack, name: name, width: w, height: h, scale: s, file: "\(name.lowercased())\(suffix).png")
        }
    }
}

for (set, w, h, prefix) in [("Top Shelf Image", 1920, 720, "top-shelf"), ("Top Shelf Image Wide", 2320, 720, "top-shelf-wide")] {
    for s in [1, 2] {
        let suffix = s == 1 ? "" : "@2x"
        render(width: w * s, height: h * s, opaque: true, fill: true, word: true,
               to: brand.appendingPathComponent("\(set).imageset/\(prefix)\(suffix).png"))
    }
}
