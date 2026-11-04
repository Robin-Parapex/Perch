import CoreGraphics
import SwiftUI
import Testing
@testable import PerchDesign

private func makeImage(width: Int = 16, height: Int = 16, _ pixel: (Int, Int) -> (UInt8, UInt8, UInt8)) -> CGImage {
    var data = [UInt8](repeating: 255, count: width * height * 4)
    for y in 0..<height {
        for x in 0..<width {
            let (r, g, b) = pixel(x, y)
            let i = (y * width + x) * 4
            data[i] = r; data[i + 1] = g; data[i + 2] = b
        }
    }
    let provider = CGDataProvider(data: Data(data) as CFData)!
    return CGImage(
        width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
    )!
}

@Suite struct ArtworkTintTests {
    @Test func averageOfSolidRed() throws {
        let avg = try #require(ArtworkTint.average(of: makeImage { _, _ in (255, 0, 0) }))
        #expect(abs(avg.red - 1) < 0.02 && avg.green < 0.02 && avg.blue < 0.02)
    }

    @Test func averageOfBlackWhiteHalves() throws {
        // CIAreaAverage runs in the sRGB-encoded working space, so the mean of 0 and 1 is 0.5
        // (a linear-light average would read about 0.73 once re-encoded).
        let img = makeImage { x, _ in x < 8 ? (0, 0, 0) : (255, 255, 255) }
        let avg = try #require(ArtworkTint.average(of: img))
        for c in [avg.red, avg.green, avg.blue] { #expect(abs(c - 0.5) < 0.03) }
    }

    @Test func saturatedInputKeepsHueWithinClamps() {
        let out = ArtworkTint.tint(from: ArtworkRGB(red: 0.9, green: 0.2, blue: 0.1))
        let a = ArtworkTint.hsb(of: ArtworkRGB(red: 0.9, green: 0.2, blue: 0.1))
        let b = ArtworkTint.hsb(of: out)
        #expect(abs(a.h - b.h) < 0.01)
        #expect((0.35...0.75).contains(b.s + 1e-9) || abs(b.s - 0.75) < 1e-6)
        #expect(b.s <= 0.75 + 1e-9 && b.s >= 0.35 - 1e-9)
        #expect(b.v <= 0.80 + 1e-9 && b.v >= 0.45 - 1e-9)
    }

    @Test func darkNavyIsBrightened() {
        let out = ArtworkTint.tint(from: ArtworkRGB(red: 0.02, green: 0.04, blue: 0.15))
        #expect(ArtworkTint.hsb(of: out).v >= 0.45 - 1e-9)
        #expect(out.blue > out.red)
    }

    @Test func nearWhiteIsBroughtDown() {
        let out = ArtworkTint.tint(from: ArtworkRGB(red: 1, green: 0.9, blue: 0.8))
        #expect(ArtworkTint.hsb(of: out).v <= 0.80 + 1e-9)
    }

    @Test func nearGreyReturnsNeutral() {
        #expect(ArtworkTint.tint(from: ArtworkRGB(red: 0.5, green: 0.51, blue: 0.5)) == ArtworkTint.neutral)
    }

    @Test func pageColorNilIsBase() {
        #expect(ArtworkTint.mixed(tint: nil, strength: 0.1) == ArtworkTint.baseRGB)
        #expect(ArtworkTint.pageColor(tint: nil) == PerchColor.base)
    }

    @Test func strengthIsClamped() {
        let t = ArtworkRGB(red: 1, green: 1, blue: 1)
        let hi = ArtworkTint.mixed(tint: t, strength: 0.9)
        let lo = ArtworkTint.mixed(tint: t, strength: 0.0)
        #expect(abs(hi.red - (ArtworkTint.baseRGB.red * 0.88 + 0.12)) < 1e-9)
        #expect(abs(lo.red - (ArtworkTint.baseRGB.red * 0.92 + 0.08)) < 1e-9)
    }

    @MainActor @Test func placeholderBuilds() {
        let img = makeImage { _, _ in (10, 80, 200) }
        _ = ArtworkPlaceholder(image: img, tint: nil).body
        _ = ArtworkPlaceholder(image: nil, tint: ArtworkRGB(red: 0.5, green: 0.3, blue: 0.2)).body
        _ = ArtworkPlaceholder(image: nil, tint: nil).body
    }
}
