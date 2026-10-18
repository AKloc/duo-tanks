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

    /// Level ground, mostly for tests.
    init(flatHeight: Double, width: Int = Int(Game.worldSize.x), maxHeight: Double = Game.worldSize.y) {
        self.init(heights: Array(repeating: flatHeight, count: width), maxHeight: maxHeight)
    }

    init(heights: [Double], maxHeight: Double = Game.worldSize.y) {
        self.heights = heights
        self.maxHeight = maxHeight
        grass = Array(repeating: 1, count: heights.count)
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

    /// Drops a circle's worth of dirt onto each column it covers, then lets it slump into a mound.
    mutating func addDirt(center: Vec, radius: Double) {
        for span in spans(center: center, radius: radius) {
            heights[span.column] = min(heights[span.column] + span.top - span.bottom, maxHeight * 0.95)
            grass[span.column] = 0
        }
        slump(around: center.x, reach: Int(radius * 3))
    }

    /// Loose dirt steeper than `maxSlope` (rise per column) slides downhill until it's stable. Mass is conserved.
    mutating func slump(around x: Double, reach: Int, maxSlope: Double = 1.1) {
        let lo = max(0, Int(x) - reach), hi = min(width - 1, Int(x) + reach)
        guard lo < hi else { return }
        for _ in 0..<4_000 {
            var moved = false
            for i in lo..<hi {
                let difference = heights[i] - heights[i + 1]
                guard abs(difference) > maxSlope + 0.002 else { continue }
                let shift = (abs(difference) - maxSlope) / 2 * (difference > 0 ? 1 : -1)
                heights[i] -= shift
                heights[i + 1] += shift
                if shift > 0 { grass[i + 1] = 0 } else { grass[i] = 0 }
                moved = true
            }
            if !moved { break }
        }
    }

    /// Pours dirt that runs downhill from `x` and settles level in the basin it reaches.
    mutating func pourLiquid(at x: Double, volume: Double, reach: Int = 180) {
        var bottom = min(max(Int(x.rounded()), 0), width - 1)
        for _ in 0..<reach {
            let left = bottom > 0 ? heights[bottom - 1] : .infinity
            let right = bottom < width - 1 ? heights[bottom + 1] : .infinity
            guard min(left, right) < heights[bottom] else { break }
            bottom += left < right ? -1 : 1
        }
        let lo = max(0, bottom - reach), hi = min(width - 1, bottom + reach)

        func basin(below level: Double) -> ClosedRange<Int> {
            var start = bottom, end = bottom
            while start > lo, heights[start - 1] < level { start -= 1 }
            while end < hi, heights[end + 1] < level { end += 1 }
            return start...end
        }
        func filled(to level: Double) -> Double {
            basin(below: level).reduce(0) { $0 + max(0, level - heights[$1]) }
        }

        var low = heights[bottom], high = heights[bottom] + volume
        for _ in 0..<40 {
            let mid = (low + high) / 2
            if filled(to: mid) < volume { low = mid } else { high = mid }
        }
        let level = min(low, maxHeight * 0.95)
        for i in basin(below: level) where heights[i] < level {
            heights[i] = level
            grass[i] = 0
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
