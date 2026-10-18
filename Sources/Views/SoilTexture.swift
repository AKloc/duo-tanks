import CoreGraphics
import Foundation

/// A world-sized soil texture: rich topsoil up high, layered clay and rock deeper down.
/// Fixed in world space, so carving a crater reveals the layers inside the hill.
enum SoilTexture {
    struct Rendered: @unchecked Sendable {
        let image: CGImage
    }

    struct Palette: Sendable {
        let deep: (r: Double, g: Double, b: Double)
        let top: (r: Double, g: Double, b: Double)

        static func `for`(_ theme: WorldTheme) -> Palette {
            switch theme {
            case .hills: Palette(deep: (0.2, 0.16, 0.14), top: (0.46, 0.31, 0.18))
            case .desert: Palette(deep: (0.42, 0.24, 0.13), top: (0.86, 0.6, 0.36))
            case .snow: Palette(deep: (0.17, 0.16, 0.19), top: (0.36, 0.31, 0.3))
            case .moon: Palette(deep: (0.2, 0.2, 0.22), top: (0.56, 0.56, 0.58))
            case .aerie: Palette(deep: (0.2, 0.17, 0.26), top: (0.5, 0.4, 0.34))
            case .forge: Palette(deep: (0.1, 0.08, 0.08), top: (0.32, 0.2, 0.17))
            }
        }
    }

    static let pixelsPerUnit = 2

    nonisolated static func make(palette: Palette, seed: UInt64 = 42) -> Rendered? {
        let worldWidth = Int(Game.worldSize.x), worldHeight = Int(Game.worldSize.y)
        let width = worldWidth * pixelsPerUnit, height = worldHeight * pixelsPerUnit
        let noise = ValueNoise(seed: seed)
        var pixels = [UInt8](repeating: 255, count: width * height * 4)

        for row in 0..<height {
            let y = Double(height - 1 - row) / Double(pixelsPerUnit)
            let depth = pow(y / Double(worldHeight), 0.7)
            for column in 0..<width {
                let x = Double(column) / Double(pixelsPerUnit)
                let warp = noise.fbm(x * 0.012, y * 0.012, octaves: 3) * 34
                let strata = 0.5 + 0.5 * sin((y + warp) / 8.5)
                let grain = noise.fbm(x * 0.18, y * 0.18, octaves: 3)
                let speck = noise.value(x * 0.85 + 500, y * 0.85)

                var r = mix(palette.deep.r, palette.top.r, depth), g = mix(palette.deep.g, palette.top.g, depth), b = mix(palette.deep.b, palette.top.b, depth)
                let layer = 0.82 + 0.18 * strata
                r *= layer + 0.05 * strata
                g *= layer
                b *= layer - 0.03 * strata
                let shade = 0.82 + 0.36 * grain
                r *= shade; g *= shade; b *= shade
                if speck > 0.86 {
                    r = r * 0.5 + 0.28; g = g * 0.5 + 0.26; b = b * 0.5 + 0.24
                } else if speck < 0.1 {
                    r *= 0.65; g *= 0.65; b *= 0.65
                }

                let i = (row * width + column) * 4
                pixels[i] = byte(r)
                pixels[i + 1] = byte(g)
                pixels[i + 2] = byte(b)
            }
        }

        let image = pixels.withUnsafeMutableBytes { buffer -> CGImage? in
            CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            )?.makeImage()
        }
        return image.map(Rendered.init)
    }

    private nonisolated static func mix(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
    private nonisolated static func byte(_ v: Double) -> UInt8 { UInt8(min(max(v, 0), 1) * 255) }
}
