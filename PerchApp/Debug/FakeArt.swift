#if DEBUG
import SwiftUI
import UIKit

/// Sample backdrop art for the fake household, drawn at run time: a sky, a sun and layered hills,
/// so the blurred backdrops have real colour blocks to work with. Nothing here is a real image.
enum FakeArt {
    @MainActor
    private static func render(index: Int) -> Data {
        let renderer = ImageRenderer(content: FakeArtView(index: index))
        renderer.scale = 1
        guard let image = renderer.cgImage else { return Data() }
        return UIImage(cgImage: image).pngData() ?? Data()
    }

    static func png(index: Int) async -> Data {
        await MainActor.run { render(index: index) }
    }
}

private struct FakeArtView: View {
    let index: Int

    private struct Palette {
        let skyTop: Color
        let skyBottom: Color
        let sun: Color
        let far: Color
        let mid: Color
        let near: Color
        let sunX: CGFloat
    }

    private static func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color {
        Color(red: r / 255, green: g / 255, blue: b / 255)
    }

    private static let palettes: [Palette] = [
        Palette(  // dusk
            skyTop: rgb(52, 40, 96), skyBottom: rgb(232, 128, 92), sun: rgb(255, 214, 150),
            far: rgb(112, 74, 120), mid: rgb(70, 48, 96), near: rgb(30, 24, 52), sunX: -260),
        Palette(  // morning mist
            skyTop: rgb(120, 170, 200), skyBottom: rgb(236, 226, 200), sun: rgb(255, 246, 220),
            far: rgb(120, 156, 150), mid: rgb(70, 112, 110), near: rgb(30, 62, 66), sunX: 220),
        Palette(  // desert
            skyTop: rgb(210, 120, 70), skyBottom: rgb(250, 196, 120), sun: rgb(255, 238, 190),
            far: rgb(184, 104, 62), mid: rgb(140, 74, 48), near: rgb(80, 42, 36), sunX: 40),
        Palette(  // night sea
            skyTop: rgb(10, 20, 48), skyBottom: rgb(40, 70, 120), sun: rgb(220, 230, 255),
            far: rgb(28, 54, 96), mid: rgb(18, 36, 70), near: rgb(8, 16, 34), sunX: 300),
        Palette(  // forest
            skyTop: rgb(90, 140, 120), skyBottom: rgb(200, 220, 160), sun: rgb(255, 250, 200),
            far: rgb(80, 130, 90), mid: rgb(46, 92, 62), near: rgb(20, 52, 38), sunX: -120),
        Palette(  // rose
            skyTop: rgb(150, 70, 110), skyBottom: rgb(250, 170, 160), sun: rgb(255, 230, 220),
            far: rgb(170, 90, 120), mid: rgb(110, 56, 92), near: rgb(52, 30, 64), sunX: 140),
    ]

    var body: some View {
        let p = Self.palettes[abs(index) % Self.palettes.count]
        ZStack {
            LinearGradient(colors: [p.skyTop, p.skyBottom], startPoint: .top, endPoint: .bottom)
            Circle().fill(p.sun).frame(width: 240, height: 240).blur(radius: 4).offset(x: p.sunX, y: -60)
            Ellipse().fill(p.far).frame(width: 1700, height: 520).offset(x: -300, y: 290)
            Ellipse().fill(p.mid).frame(width: 1500, height: 520).offset(x: 380, y: 340)
            skyline(p).offset(y: 250)
            Ellipse().fill(p.near).frame(width: 1900, height: 460).offset(x: -100, y: 450)
        }
        .frame(width: 1280, height: 720)
        .clipped()
    }

    /// A row of blocks of different heights, like far-off buildings or trees.
    private func skyline(_ p: Palette) -> some View {
        HStack(alignment: .bottom, spacing: 10) {
            ForEach(0..<14, id: \.self) { i in
                RoundedRectangle(cornerRadius: 6)
                    .fill(p.mid.opacity(0.9))
                    .frame(width: 70, height: CGFloat(60 + ((i * 37 + abs(index) * 53) % 130)))
            }
        }
        .frame(width: 1280, alignment: .center)
    }
}
#endif
