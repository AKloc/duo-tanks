import SwiftUI

/// How each world is painted.
struct ThemeLook {
    enum Celestial { case moon(tint: Color), sun, earth }
    enum Trees { case pines(snowy: Bool), cacti, none }
    enum Surface { case grass, snow, dust(rim: Color) }
    enum RidgeShape { case jagged, mesa, rounded }

    let sky: [Gradient.Stop]
    let starBrightness: Double
    let celestial: Celestial
    let ridges: [(base: Double, amplitude: Double, color: Color)]
    let ridgeShape: RidgeShape
    let haze: Color?
    let trees: Trees
    let surface: Surface
    let cloudColor: Color?
    let hasBirds: Bool

    static func `for`(_ theme: WorldTheme) -> ThemeLook {
        switch theme {
        case .hills:
            ThemeLook(
                sky: stops((0.03, 0.04, 0.14), (0.12, 0.1, 0.3), (0.42, 0.24, 0.4), (0.85, 0.5, 0.42)),
                starBrightness: 1,
                celestial: .moon(tint: Color(red: 1, green: 0.96, blue: 0.85)),
                ridges: [
                    (175, 140, Color(red: 0.36, green: 0.27, blue: 0.46)),
                    (120, 120, Color(red: 0.22, green: 0.16, blue: 0.32)),
                    (70, 95, Color(red: 0.11, green: 0.08, blue: 0.18)),
                ],
                ridgeShape: .jagged,
                haze: Color(red: 0.75, green: 0.45, blue: 0.5),
                trees: .pines(snowy: false),
                surface: .grass,
                cloudColor: Color(red: 0.8, green: 0.72, blue: 0.9),
                hasBirds: true
            )
        case .desert:
            ThemeLook(
                sky: stops((0.12, 0.08, 0.26), (0.5, 0.22, 0.38), (0.95, 0.5, 0.28), (1, 0.8, 0.48)),
                starBrightness: 0.35,
                celestial: .sun,
                ridges: [
                    (150, 120, Color(red: 0.62, green: 0.34, blue: 0.34)),
                    (105, 105, Color(red: 0.44, green: 0.22, blue: 0.26)),
                    (60, 80, Color(red: 0.24, green: 0.12, blue: 0.15)),
                ],
                ridgeShape: .mesa,
                haze: Color(red: 1, green: 0.6, blue: 0.35),
                trees: .cacti,
                surface: .dust(rim: Color(red: 0.98, green: 0.78, blue: 0.5)),
                cloudColor: Color(red: 1, green: 0.7, blue: 0.6),
                hasBirds: true
            )
        case .snow:
            ThemeLook(
                sky: stops((0.02, 0.03, 0.1), (0.07, 0.11, 0.27), (0.22, 0.32, 0.52), (0.5, 0.6, 0.76)),
                starBrightness: 1,
                celestial: .moon(tint: Color(red: 0.88, green: 0.94, blue: 1)),
                ridges: [
                    (185, 150, Color(red: 0.62, green: 0.7, blue: 0.84)),
                    (125, 125, Color(red: 0.38, green: 0.46, blue: 0.63)),
                    (70, 95, Color(red: 0.14, green: 0.19, blue: 0.3)),
                ],
                ridgeShape: .jagged,
                haze: Color(red: 0.7, green: 0.8, blue: 0.95),
                trees: .pines(snowy: true),
                surface: .snow,
                cloudColor: Color(red: 0.75, green: 0.82, blue: 0.95),
                hasBirds: true
            )
        case .moon:
            ThemeLook(
                sky: stops((0, 0, 0.01), (0.01, 0.01, 0.03), (0.03, 0.03, 0.06), (0.06, 0.06, 0.09)),
                starBrightness: 1.6,
                celestial: .earth,
                ridges: [
                    (150, 110, Color(red: 0.3, green: 0.3, blue: 0.33)),
                    (100, 95, Color(red: 0.2, green: 0.2, blue: 0.23)),
                    (55, 75, Color(red: 0.12, green: 0.12, blue: 0.14)),
                ],
                ridgeShape: .rounded,
                haze: nil,
                trees: .none,
                surface: .dust(rim: Color(red: 0.82, green: 0.82, blue: 0.86)),
                cloudColor: nil,
                hasBirds: false
            )
        }
    }

    private static func stops(_ colors: (Double, Double, Double)...) -> [Gradient.Stop] {
        let locations = [0, 0.45, 0.75, 1.0]
        return zip(colors, locations).map { color, location in
            Gradient.Stop(color: Color(red: color.0, green: color.1, blue: color.2), location: location)
        }
    }
}
