import Foundation

/// Ground stored as one height per world-unit column, measured up from the bottom.
struct Terrain {
    static let maxScorchMarks = 40

    private(set) var heights: [Double]
    /// 0...1 grass cover per column; blasts burn it away and fresh dirt has none.
    private(set) var grass: [Double]
    private(set) var scorchMarks: [(center: Vec, radius: Double)] = []
    let maxHeight: Double

    var width: Int { heights.count }

    init(width: Int, maxHeight: Double, theme: WorldTheme = .hills, roughness: Double = 1) {
        self.maxHeight = maxHeight
        let base = maxHeight * Double.random(in: 0.25...0.4)
        let waviness = theme == .desert ? 0.7 : 1
        let layers = (1...4).map { i in
            (
                amplitude: maxHeight * 0.2 / Double(i) * roughness,
                frequency: Double(i) * Double.random(in: 0.8...1.8) * waviness,
                phase: Double.random(in: 0...(2 * .pi))
            )
        }
        heights = (0..<width).map { x in
            let t = Double(x) / Double(width) * 2 * .pi
            let h = layers.reduce(base) { $0 + $1.amplitude * sin(t * $1.frequency + $1.phase) }
            return min(max(h, maxHeight * 0.06), maxHeight * 0.75)
        }
        grass = Array(repeating: 1, count: width)
        if theme == .moon {
            for _ in 0..<Int.random(in: 5...8) {
                let x = Double.random(in: 40...960)
                carve(center: Vec(x, height(at: x) + Double.random(in: 2...10)), radius: Double.random(in: 18...45), leavesScorch: false)
            }
        }
    }

    func height(at x: Double) -> Double {
        let i = Int(x.rounded())
        guard heights.indices.contains(i) else { return 0 }
        return heights[i]
    }

    /// Removes a circle of ground; anything above the hole drops into it.
    mutating func carve(center: Vec, radius: Double, leavesScorch: Bool = true) {
        for span in spans(center: center, radius: radius) {
            let h = heights[span.column]
            guard h > span.bottom else { continue }
            heights[span.column] = span.bottom + max(0, h - span.top)
        }
        guard leavesScorch else { return }
        burnGrass(around: center.x, radius: radius * 1.5)
        scorchMarks.append((center, radius))
        if scorchMarks.count > Terrain.maxScorchMarks { scorchMarks.removeFirst() }
    }

    /// Burns grass away, fully near `x` and fading out toward `radius`.
    mutating func burnGrass(around x: Double, radius: Double) {
        let lo = max(0, Int(x - radius)), hi = min(width - 1, Int(x + radius))
        guard lo <= hi else { return }
        for i in lo...hi {
            let distance = abs(Double(i) - x) / radius
            grass[i] = min(grass[i], max(0, (distance - 0.75) / 0.25))
        }
    }

    /// Drops a circle's worth of dirt onto each column it covers.
    mutating func addDirt(center: Vec, radius: Double) {
        for span in spans(center: center, radius: radius) {
            heights[span.column] = min(heights[span.column] + span.top - span.bottom, maxHeight * 0.95)
            grass[span.column] = 0
        }
    }

    mutating func flatten(around x: Double, halfWidth: Int) {
        let center = Int(x.rounded())
        let range = max(0, center - halfWidth)...min(width - 1, center + halfWidth)
        let level = range.map { heights[$0] }.reduce(0, +) / Double(range.count)
        for i in range { heights[i] = level }
    }

    private func spans(center: Vec, radius: Double) -> [(column: Int, bottom: Double, top: Double)] {
        let lo = max(0, Int((center.x - radius).rounded(.down)))
        let hi = min(width - 1, Int((center.x + radius).rounded(.up)))
        guard lo <= hi else { return [] }
        return (lo...hi).compactMap { i in
            let dx = Double(i) - center.x
            guard dx * dx <= radius * radius else { return nil }
            let dy = (radius * radius - dx * dx).squareRoot()
            return (i, max(0, center.y - dy), center.y + dy)
        }
    }
}
