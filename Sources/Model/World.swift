import Foundation

enum WorldTheme: String, CaseIterable, Identifiable {
    case hills, desert, snow, moon, aerie, forge

    var id: Self { self }

    var name: String {
        switch self {
        case .hills: "Moonlit Hills"
        case .desert: "Desert Dusk"
        case .snow: "Snowy Night"
        case .moon: "The Moon"
        case .aerie: "Floating Isles"
        case .forge: "Volcanic Forge"
        }
    }

    var gravityScale: Double {
        switch self {
        case .moon: 0.4
        case .aerie: 0.5
        case .forge: 1.6
        default: 1
        }
    }

    /// No air on the Moon, so no wind; the isles get a gentle breeze.
    var windScale: Double {
        switch self {
        case .moon: 0
        case .aerie, .forge: 0.6
        default: 1
        }
    }
}

enum WorldChoice: String, CaseIterable, Identifiable {
    case random, hills, desert, snow, moon, aerie, forge

    var id: Self { self }

    var theme: WorldTheme? { WorldTheme(rawValue: rawValue) }
    var name: String { theme?.name ?? "Random" }
}

struct Weather: Equatable {
    enum Precipitation { case none, rain, snow }

    var precipitation = Precipitation.none
    var hasLightning = false

    static let clear = Weather()
}

enum WeatherSetting: String, CaseIterable, Identifiable {
    case auto, clear, rain, storm

    var id: Self { self }
    var name: String { rawValue.capitalized }

    func resolve(for theme: WorldTheme) -> Weather {
        guard theme != .moon else { return .clear }
        let falling: Weather.Precipitation = theme == .snow ? .snow : .rain
        switch self {
        case .clear: return theme == .snow ? Weather(precipitation: .snow) : .clear
        case .rain: return Weather(precipitation: falling)
        case .storm: return Weather(precipitation: falling, hasLightning: true)
        case .auto:
            if theme == .snow { return Weather(precipitation: .snow, hasLightning: Double.random(in: 0...1) < 0.1) }
            switch Double.random(in: 0...1) {
            case ..<0.6: return .clear
            case ..<0.85: return Weather(precipitation: .rain)
            default: return Weather(precipitation: .rain, hasLightning: true)
            }
        }
    }
}

enum WindSetting: String, CaseIterable, Identifiable {
    case off, light, normal, strong

    var id: Self { self }
    var name: String { rawValue.capitalized }

    var scale: Double {
        switch self {
        case .off: 0
        case .light: 0.5
        case .normal: 1
        case .strong: 1.6
        }
    }
}

enum Roughness: String, CaseIterable, Identifiable {
    case smooth, rolling, rugged

    var id: Self { self }
    var name: String { rawValue.capitalized }

    var scale: Double {
        switch self {
        case .smooth: 0.6
        case .rolling: 1
        case .rugged: 1.5
        }
    }
}
