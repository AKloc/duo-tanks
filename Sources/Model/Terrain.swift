import Foundation

/// A floating island: one solid span of rock per column, in its own coordinates, placed at `offset`.
/// Islands sway around `home` between turns.
struct Island: Identifiable, Sendable {
    let id: Int
    var offset: Vec
    var bottoms: [Double]
    var tops: [Double]
    var grass: [Double]
    let home: Vec
    let sway: Vec
    var phase: Double

    var width: Int { tops.count }
    var hasRock: Bool { zip(bottoms, tops).contains { $1 > $0 } }
    var centerX: Double { offset.x + Double(width) / 2 }

    func column(at x: Double) -> Int? {
        let i = Int((x - offset.x).rounded())
        return (0..<width).contains(i) ? i : nil
    }

    /// The rock in the column at world `x`, in world coordinates.
    func span(at x: Double) -> (bottom: Double, top: Double)? {
        guard let i = column(at: x), tops[i] > bottoms[i] else { return nil }
        return (offset.y + bottoms[i], offset.y + tops[i])
    }

    /// Where the island sits for a given sway phase.
    func position(atPhase phase: Double) -> Vec {
        home + Vec(sin(phase) * sway.x, sin(phase * 0.7 + 1.3) * sway.y)
    }
}

/// A column of rising air that pushes shells upward.
struct Updraft: Sendable {
    let x: ClosedRange<Double>
    let strength: Double
}

/// A point of intense gravity that bends shots toward it and swallows anything that gets too close.
struct GravityWell: Sendable {
    static let coreRadius = 14.0

    let center: Vec
    let strength: Double
    /// Turns until it collapses; `nil` lasts forever.
    var turnsLeft: Int?

    func pull(on p: Vec) -> Vec {
        let offset = center - p
        let distance = max(offset.length, 1)
        return offset / distance * strength * 1_000 / max(distance * distance, 900)
    }
}

/// The ground, stored as one height per world-unit column measured up from the bottom, plus any floating islands.
struct Terrain: Sendable {
    static let maxScorchMarks = 40

    private(set) var heights: [Double]
    /// 0...1 grass cover per column; blasts burn it away and fresh dirt has none.
    private(set) var grass: [Double]
    private(set) var scorchMarks: [(center: Vec, radius: Double)] = []
    private(set) var islands: [Island] = []
    private(set) var updrafts: [Updraft] = []
    /// The ground is a bottomless sea of clouds rather than solid earth.
    private(set) var hasAbyss = false
    private(set) var wells: [GravityWell] = []
    /// Ground lower than this is a pool of lava.
    private(set) var lavaLevel: Double?
    /// Where volcanic vents sit; they erupt every few turns.
    private(set) var vents: [Double] = []
    /// Ice: hit tanks slide, and big blasts on slopes set off avalanches.
    private(set) var isIcy = false
    /// The wind keeps shifting while shells are in the air.
    private(set) var hasGusts = false
    let maxHeight: Double

    var width: Int { heights.count }

    init(width: Int, maxHeight: Double, theme: WorldTheme = .hills, roughness: Double = 1) {
        self.maxHeight = maxHeight
        if theme == .aerie {
            heights = Array(repeating: 0, count: width)
            grass = Array(repeating: 0, count: width)
            hasAbyss = true
            var generator = SystemRandomNumberGenerator()
            (islands, updrafts) = Terrain.makeArchipelago(width: width, roughness: roughness, using: &generator)
            return
        }
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
        if theme == .forge {
            grass = Array(repeating: 0, count: width)
            let low = heights.min() ?? 60
            lavaLevel = low + 28
            vents = [Double.random(in: 380...460), Double.random(in: 540...620)]
        }
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

    /// Islands over a cloud sea, built from explicit pieces (for missions and tests).
    init(islands: [Island], updrafts: [Updraft] = [], width: Int = Int(Game.worldSize.x), maxHeight: Double = Game.worldSize.y) {
        self.init(heights: Array(repeating: 0, count: width), maxHeight: maxHeight)
        grass = Array(repeating: 0, count: width)
        self.islands = islands
        self.updrafts = updrafts
        hasAbyss = true
    }

    // MARK: Queries

    /// Height of the ground (not islands) at `x`.
    func height(at x: Double) -> Double {
        let i = Int(x.rounded())
        guard heights.indices.contains(i) else { return 0 }
        return heights[i]
    }

    /// What something at height `y` in column `x` rests on: the highest top of any rock that starts at or below it.
    /// If the point is inside rock, that rock's top (so buried things stay buried).
    func support(at x: Double, y: Double) -> Double {
        var best = height(at: x)
        for island in islands {
            guard let span = island.span(at: x), span.bottom <= y + 0.5, span.top > best else { continue }
            best = span.top
        }
        return best
    }

    /// The island something at (`x`, `y`) is resting on, if any.
    func supportingIsland(at x: Double, y: Double) -> Int? {
        var best = height(at: x)
        var id: Int?
        for island in islands {
            guard let span = island.span(at: x), span.bottom <= y + 0.5, span.top > best else { continue }
            best = span.top
            id = island.id
        }
        return id
    }

    func isSolid(_ p: Vec) -> Bool {
        if p.y <= height(at: p.x) { return true }
        return islands.contains { island in
            guard let span = island.span(at: p.x) else { return false }
            return p.y >= span.bottom && p.y <= span.top
        }
    }

    /// Whether a point is down in the cloud sea, below every island.
    func isInAbyss(_ p: Vec) -> Bool {
        hasAbyss && p.y <= height(at: p.x) + 1
    }

    func updraft(at x: Double) -> Double {
        updrafts.first { $0.x.contains(x) }?.strength ?? 0
    }

    /// Everything besides ordinary gravity and wind that pushes a shell around.
    func force(at p: Vec) -> Vec {
        wells.reduce(Vec(0, updraft(at: p.x))) { $0 + $1.pull(on: p) }
    }

    /// Whether a point has fallen into a gravity well's core.
    func isSwallowed(_ p: Vec) -> Bool {
        wells.contains { ($0.center - p).length < GravityWell.coreRadius }
    }

    /// Whether something standing at (`x`, `y`) is in lava.
    func isInLava(x: Double, y: Double) -> Bool {
        guard let lavaLevel else { return false }
        return y < lavaLevel && height(at: x) < lavaLevel
    }

    mutating func addWell(_ well: GravityWell) {
        wells.append(well)
    }

    /// Counts temporary wells down a turn and lets the spent ones collapse.
    mutating func ageWells() {
        for i in wells.indices { wells[i].turnsLeft? -= 1 }
        wells.removeAll { ($0.turnsLeft ?? 1) <= 0 }
    }

    mutating func addHazards(wells: [GravityWell] = [], lavaLevel: Double? = nil, vents: [Double] = [], isIcy: Bool = false, hasGusts: Bool = false) {
        self.wells += wells
        if let lavaLevel { self.lavaLevel = lavaLevel }
        self.vents += vents
        if isIcy {
            self.isIcy = true
            grass = Array(repeating: 0, count: width)
        }
        if hasGusts { self.hasGusts = true }
    }

    /// A good place to put a tank near `x`: on the ground, or on the nearest island when there's no ground.
    func spawnPoint(near x: Double) -> Vec {
        guard hasAbyss, !islands.isEmpty else { return Vec(x, height(at: x)) }
        let island = islands.filter(\.hasRock).min { abs($0.centerX - x) < abs($1.centerX - x) } ?? islands[0]
        let inset = Double(island.width) * 0.25
        let spawnX = min(max(x, island.offset.x + inset), island.offset.x + Double(island.width) - inset)
        return Vec(spawnX, support(at: spawnX, y: island.offset.y + 200))
    }

    // MARK: Changes

    /// Removes a circle of rock. On the ground, anything above the hole drops into it; islands are carved the same way.
    mutating func carve(center: Vec, radius: Double, leavesScorch: Bool = true) {
        for span in spans(center: center, radius: radius) {
            let h = heights[span.column]
            guard h > span.bottom else { continue }
            heights[span.column] = span.bottom + max(0, h - span.top)
        }
        for index in islands.indices {
            carveIsland(index, center: center, radius: radius)
        }
        islands.removeAll { !$0.hasRock }
        guard leavesScorch else { return }
        burnGrass(around: center.x, radius: radius * 1.5)
        scorchMarks.append((center, radius))
        if scorchMarks.count > Terrain.maxScorchMarks { scorchMarks.removeFirst() }
    }

    private mutating func carveIsland(_ index: Int, center: Vec, radius: Double) {
        var island = islands[index]
        for column in 0..<island.width {
            let x = island.offset.x + Double(column)
            let dx = x - center.x
            guard dx * dx <= radius * radius else { continue }
            let dy = (radius * radius - dx * dx).squareRoot()
            let holeBottom = center.y - dy - island.offset.y, holeTop = center.y + dy - island.offset.y
            let bottom = island.bottoms[column], top = island.tops[column]
            guard top > bottom, holeTop > bottom, holeBottom < top else { continue }
            if holeBottom <= bottom && holeTop >= top {
                island.tops[column] = bottom
            } else if holeBottom <= bottom {
                island.bottoms[column] = holeTop
            } else if holeTop >= top {
                island.tops[column] = holeBottom
            } else {
                island.tops[column] = top - (holeTop - holeBottom)
            }
        }
        islands[index] = island
    }

    /// Burns grass away, fully near `x` and fading out toward `radius`.
    mutating func burnGrass(around x: Double, radius: Double) {
        func burnt(_ cover: Double, at column: Double) -> Double {
            min(cover, max(0, (abs(column - x) / radius - 0.75) / 0.25))
        }
        let lo = max(0, Int(x - radius)), hi = min(width - 1, Int(x + radius))
        if lo <= hi {
            for i in lo...hi { grass[i] = burnt(grass[i], at: Double(i)) }
        }
        for index in islands.indices {
            for column in 0..<islands[index].width {
                let worldX = islands[index].offset.x + Double(column)
                guard abs(worldX - x) < radius else { continue }
                islands[index].grass[column] = burnt(islands[index].grass[column], at: worldX)
            }
        }
    }

    /// Drops a circle's worth of dirt onto each column it covers, then lets it slump into a mound.
    /// Dirt over an island lands on the island; dirt over the cloud sea is lost.
    mutating func addDirt(center: Vec, radius: Double) {
        for span in spans(center: center, radius: radius) {
            let amount = span.top - span.bottom
            let x = Double(span.column)
            if let id = supportingIsland(at: x, y: center.y + radius), let index = islands.firstIndex(where: { $0.id == id }),
               let column = islands[index].column(at: x) {
                islands[index].tops[column] += amount
                islands[index].grass[column] = 0
            } else if !hasAbyss {
                heights[span.column] = min(heights[span.column] + amount, maxHeight * 0.95)
                grass[span.column] = 0
            }
        }
        if !hasAbyss { slump(around: center.x, reach: Int(radius * 3)) }
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
    /// On an island it just piles up where it lands.
    mutating func pourLiquid(at x: Double, y: Double = .infinity, volume: Double, reach: Int = 180) {
        if supportingIsland(at: x, y: y) != nil {
            addDirt(center: Vec(x, support(at: x, y: y)), radius: 20)
            return
        }
        guard !hasAbyss else { return }
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

    /// Levels the surface under `x`, on whatever ground or island something at height `y` stands on.
    mutating func flatten(around x: Double, halfWidth: Int, y: Double = .infinity) {
        if let id = supportingIsland(at: x, y: y), let index = islands.firstIndex(where: { $0.id == id }),
           let center = islands[index].column(at: x) {
            let range = max(0, center - halfWidth)...min(islands[index].width - 1, center + halfWidth)
            let level = range.map { islands[index].tops[$0] }.reduce(0, +) / Double(range.count)
            for i in range where islands[index].tops[i] > islands[index].bottoms[i] { islands[index].tops[i] = level }
            return
        }
        let center = Int(x.rounded())
        let range = max(0, center - halfWidth)...min(width - 1, center + halfWidth)
        let level = range.map { heights[$0] }.reduce(0, +) / Double(range.count)
        for i in range { heights[i] = level }
    }

    mutating func moveIsland(id: Int, to offset: Vec) {
        guard let index = islands.firstIndex(where: { $0.id == id }) else { return }
        islands[index].offset = offset
    }

    mutating func setIslandPhase(id: Int, _ phase: Double) {
        guard let index = islands.firstIndex(where: { $0.id == id }) else { return }
        islands[index].phase = phase
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

    // MARK: Building islands

    /// A rounded slab with a gently hilly top and a tapering, rocky underside.
    static func makeIsland(id: Int, x: Double, y: Double, width: Int, thickness: Double, hilliness: Double = 12,
                           sway: Vec = .zero, seed: UInt64) -> Island {
        let noise = ValueNoise(seed: seed)
        let tops = (0..<width).map { i -> Double in
            let u = Double(i) / Double(max(width - 1, 1))
            let edge = pow(sin(.pi * u), 0.35)
            return (noise.fbm(Double(i) * 0.03, 3, octaves: 3) - 0.5) * hilliness * 2 * edge + 4 * edge
        }
        let bottoms = (0..<width).map { i -> Double in
            let u = Double(i) / Double(max(width - 1, 1))
            let taper = pow(sin(.pi * u), 0.6)
            let jag = (noise.value(Double(i) * 0.25, 9) - 0.5) * 8
            return -thickness * taper + jag * taper
        }
        let fixedBottoms = zip(bottoms, tops).map { min($0, $1 - 2) }
        let home = Vec(x, y)
        return Island(id: id, offset: home, bottoms: fixedBottoms, tops: tops, grass: Array(repeating: 1, count: width),
                      home: home, sway: sway, phase: 0)
    }

    private static func makeArchipelago(width: Int, roughness: Double,
                                        using generator: inout some RandomNumberGenerator) -> ([Island], [Updraft]) {
        var islands: [Island] = []
        var updrafts: [Updraft] = []
        var x = Double.random(in: 10...40, using: &generator)
        var id = 0
        while x < Double(width) - 80 {
            let islandWidth = Int(Double.random(in: 110...180, using: &generator))
            let fits = min(islandWidth, width - Int(x) - 10)
            guard fits > 60 else { break }
            islands.append(makeIsland(
                id: id, x: x, y: Double.random(in: 110...250, using: &generator), width: fits,
                thickness: Double.random(in: 40...70, using: &generator), hilliness: 10 * roughness,
                sway: Vec(Double.random(in: 8...22, using: &generator), Double.random(in: 5...14, using: &generator)),
                seed: UInt64.random(in: 1...UInt64.max, using: &generator)
            ))
            id += 1
            let gap = Double.random(in: 50...130, using: &generator)
            if gap > 80, Bool.random(using: &generator) {
                let mid = x + Double(fits) + gap / 2
                updrafts.append(Updraft(x: (mid - 14)...(mid + 14), strength: 230))
            }
            x += Double(fits) + gap
        }
        return (islands, updrafts)
    }
}
