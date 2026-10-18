import Foundation

/// Smooth, repeatable 2D value noise for procedural textures and scenery.
struct ValueNoise: Sendable {
    let seed: UInt64

    /// 0..<1, smooth.
    func value(_ x: Double, _ y: Double) -> Double {
        let x0 = x.rounded(.down), y0 = y.rounded(.down)
        let fx = smooth(x - x0), fy = smooth(y - y0)
        let ix = Int(x0), iy = Int(y0)
        let top = lerp(hash(ix, iy), hash(ix + 1, iy), fx)
        let bottom = lerp(hash(ix, iy + 1), hash(ix + 1, iy + 1), fx)
        return lerp(top, bottom, fy)
    }

    /// Fractal sum of `octaves` layers of noise, normalized to 0..<1.
    func fbm(_ x: Double, _ y: Double, octaves: Int) -> Double {
        var sum = 0.0, amplitude = 0.5, frequency = 1.0, total = 0.0
        for _ in 0..<octaves {
            sum += value(x * frequency, y * frequency) * amplitude
            total += amplitude
            amplitude *= 0.5
            frequency *= 2
        }
        return sum / total
    }

    private func hash(_ x: Int, _ y: Int) -> Double {
        var h = (UInt64(bitPattern: Int64(x)) &* 0x9E37_79B9_7F4A_7C15) ^ (UInt64(bitPattern: Int64(y)) &* 0xC2B2_AE3D_27D4_EB4F) ^ seed
        h ^= h >> 31
        h = h &* 0xBF58_476D_1CE4_E5B9
        h ^= h >> 29
        return Double(h & 0xFF_FFFF) / Double(0x100_0000)
    }

    private func smooth(_ t: Double) -> Double { t * t * (3 - 2 * t) }
    private func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
}
