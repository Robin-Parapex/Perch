import CoreImage
import CoreGraphics
import SwiftUI

/// An sRGB colour with components in 0...1. Plain value type so it can cross actors.
public struct ArtworkRGB: Sendable, Equatable, Hashable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public var color: Color { Color(red: red, green: green, blue: blue) }
}

/// Artwork colour maths for the page tint (docs/DESIGN.md: tint the page 8-12% from the focused backdrop).
public enum ArtworkTint {
    /// Neutral cool grey used for near-greyscale art.
    public static let neutral = ArtworkRGB(red: 0.45, green: 0.47, blue: 0.52)
    /// Base page colour #0b0b0f as components.
    static let baseRGB = ArtworkRGB(red: 11.0 / 255, green: 11.0 / 255, blue: 15.0 / 255)

    // CIContext is documented as thread-safe; it is created once and never mutated.
    nonisolated(unsafe) private static let context: CIContext = {
        let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
        return CIContext(options: [
            .workingColorSpace: srgb,
            .cacheIntermediates: false,
        ])
    }()

    /// Average colour of the whole image (CIAreaAverage over the full extent), in sRGB.
    /// Averaging happens in the sRGB-encoded working space, so black/white halves give 0.5.
    public static func average(of image: CGImage) -> ArtworkRGB? {
        let input = CIImage(cgImage: image)
        let extent = input.extent
        guard extent.width > 0, extent.height > 0, extent.isInfinite == false else { return nil }
        guard let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: input,
            kCIInputExtentKey: CIVector(cgRect: extent),
        ]), let output = filter.outputImage else { return nil }

        var pixel = [UInt8](repeating: 0, count: 4)
        let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
        context.render(
            output,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: srgb
        )
        let alpha = Double(pixel[3]) / 255
        guard alpha > 0 else { return nil }
        // Output is premultiplied; undo it.
        func channel(_ v: UInt8) -> Double { min(1, Double(v) / 255 / alpha) }
        return ArtworkRGB(red: channel(pixel[0]), green: channel(pixel[1]), blue: channel(pixel[2]))
    }

    /// Turns a raw average into a usable tint: saturation 0.35...0.75, brightness 0.45...0.80.
    /// Near-greyscale input (saturation < 0.08) returns `neutral`. Yellow-green to green hues (`greenHues`) are held
    /// to the low end of both ranges: mixed into the near-black base at full strength they read as a muddy green.
    public static func tint(from average: ArtworkRGB) -> ArtworkRGB {
        var (h, s, v) = hsb(of: average)
        if s < 0.08 { return neutral }
        let green = greenHues.contains(h)
        s = min(max(s, 0.35), green ? 0.45 : 0.75)
        v = min(max(v, 0.45), green ? 0.55 : 0.80)
        return rgb(h: h, s: s, v: v)
    }

    /// Hue band (0...1) from yellow-green to green-cyan.
    static let greenHues: ClosedRange<Double> = 0.15...0.45

    /// Base #0b0b0f mixed with `tint` at `strength` (clamped 0.08...0.12); the base when `tint` is nil.
    public static func pageColor(tint: ArtworkRGB?, strength: Double = 0.10) -> Color {
        mixed(tint: tint, strength: strength).color
    }

    static func mixed(tint: ArtworkRGB?, strength: Double) -> ArtworkRGB {
        guard let tint else { return baseRGB }
        let k = min(max(strength, 0.08), 0.12)
        return ArtworkRGB(
            red: baseRGB.red * (1 - k) + tint.red * k,
            green: baseRGB.green * (1 - k) + tint.green * k,
            blue: baseRGB.blue * (1 - k) + tint.blue * k
        )
    }

    // MARK: HSB

    static func hsb(of c: ArtworkRGB) -> (h: Double, s: Double, v: Double) {
        let maxC = max(c.red, c.green, c.blue)
        let minC = min(c.red, c.green, c.blue)
        let d = maxC - minC
        var h = 0.0
        if d > 0 {
            if maxC == c.red {
                h = ((c.green - c.blue) / d).truncatingRemainder(dividingBy: 6)
            } else if maxC == c.green {
                h = (c.blue - c.red) / d + 2
            } else {
                h = (c.red - c.green) / d + 4
            }
            h /= 6
            if h < 0 { h += 1 }
        }
        return (h, maxC == 0 ? 0 : d / maxC, maxC)
    }

    static func rgb(h: Double, s: Double, v: Double) -> ArtworkRGB {
        let hh = (h - h.rounded(.down)) * 6
        let i = Int(hh) % 6
        let f = hh - Double(Int(hh))
        let p = v * (1 - s)
        let q = v * (1 - s * f)
        let t = v * (1 - s * (1 - f))
        switch i {
        case 0: return ArtworkRGB(red: v, green: t, blue: p)
        case 1: return ArtworkRGB(red: q, green: v, blue: p)
        case 2: return ArtworkRGB(red: p, green: v, blue: t)
        case 3: return ArtworkRGB(red: p, green: q, blue: v)
        case 4: return ArtworkRGB(red: t, green: p, blue: v)
        default: return ArtworkRGB(red: v, green: p, blue: q)
        }
    }
}
