import Foundation

/// A coarse land map of Earth for the moon level's sky.
enum EarthMap {
    enum Surface { case land, ice }

    /// Rough continent outlines as (longitude, latitude) in degrees.
    static let continents: [[(Double, Double)]] = [
        // North America
        [(-168, 66), (-140, 70), (-95, 72), (-80, 63), (-62, 58), (-55, 50), (-66, 44), (-76, 35), (-81, 25), (-97, 26),
         (-97, 18), (-87, 15), (-80, 8), (-90, 14), (-105, 20), (-115, 30), (-124, 40), (-124, 48), (-135, 58), (-150, 60), (-165, 60)],
        // Greenland
        [(-55, 60), (-45, 60), (-20, 70), (-20, 80), (-45, 83), (-60, 78), (-55, 70)],
        // South America
        [(-80, 8), (-62, 10), (-50, 0), (-35, -6), (-40, -22), (-48, -27), (-58, -38), (-65, -55), (-72, -50), (-72, -30), (-70, -18), (-81, -5)],
        // Europe
        [(-10, 36), (-9, 44), (-2, 48), (-5, 58), (5, 62), (10, 70), (30, 71), (40, 66), (40, 45), (28, 40), (20, 38), (12, 38), (3, 42)],
        // Africa
        [(-17, 21), (-10, 30), (-5, 36), (10, 37), (32, 31), (35, 28), (43, 12), (51, 12), (40, -5), (40, -16), (33, -27), (20, -35),
         (15, -28), (12, -15), (9, 4), (-8, 4), (-17, 14)],
        // Asia
        [(40, 45), (40, 66), (70, 73), (110, 77), (140, 72), (180, 68), (170, 60), (155, 58), (140, 50), (130, 42), (122, 30), (110, 20),
         (105, 10), (100, 5), (95, 15), (90, 22), (80, 15), (77, 8), (72, 20), (60, 25), (50, 28), (45, 12), (35, 28), (36, 36), (42, 42)],
        // Australia
        [(113, -22), (122, -17), (131, -12), (137, -12), (142, -11), (146, -19), (153, -27), (150, -37), (141, -38), (130, -32), (115, -34)],
        // Antarctica
        [(-180, -72), (-120, -74), (-60, -66), (0, -70), (60, -67), (120, -66), (180, -72), (180, -90), (-180, -90)],
    ]

    /// Land and ice on a 2° grid, built once from the outlines.
    private static let grid: [[Surface?]] = (0..<90).map { row in
        let lat = 89 - Double(row) * 2
        return (0..<180).map { column in
            let lon = -179 + Double(column) * 2
            for (index, outline) in continents.enumerated() where contains(outline, lon: lon, lat: lat) {
                return index == 1 || index == continents.count - 1 ? .ice : .land
            }
            return nil
        }
    }

    static func surface(lon: Double, lat: Double) -> Surface? {
        var wrapped = (lon + 180).truncatingRemainder(dividingBy: 360)
        if wrapped < 0 { wrapped += 360 }
        let column = min(Int(wrapped / 2), 179), row = min(max(Int((89 - lat) / 2 + 0.5), 0), 89)
        return grid[row][column]
    }

    private static func contains(_ outline: [(Double, Double)], lon: Double, lat: Double) -> Bool {
        var inside = false
        var j = outline.count - 1
        for i in outline.indices {
            let (xi, yi) = outline[i], (xj, yj) = outline[j]
            if (yi > lat) != (yj > lat), lon < (xj - xi) * (lat - yi) / (yj - yi) + xi { inside.toggle() }
            j = i
        }
        return inside
    }
}
