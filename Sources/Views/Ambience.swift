import Foundation

/// Cosmetic sky life: wind-blown clouds, the odd comet and passing flocks.
/// Positions are normalized to the view: x and y run 0...1, with y pointing down.
final class Ambience {
    struct Cloud {
        var x: Double
        let y: Double
        let puffs: [(dx: Double, dy: Double, radius: Double)]
    }

    struct Comet {
        var position: Vec
        let velocity: Vec
        var age = 0.0
        let lifetime: Double

        /// Fades in and out over its life.
        var brightness: Double { sin(.pi * min(age / lifetime, 1)) }
    }

    struct Flock {
        var position: Vec
        var velocity: Vec
        let offsets: [Vec]
        var flap = Double.random(in: 0...(2 * .pi))
        var isSpooked = false
    }

    struct Drop {
        var position: Vec
        let speed: Double
        let size: Double
    }

    struct Bolt {
        let trunk: [Vec]
        let branches: [[Vec]]
        var age = 0.0

        static let lifetime = 0.45
    }

    private(set) var clouds: [Cloud]
    private(set) var drops: [Drop] = []
    private(set) var precipitation = Weather.Precipitation.none
    private(set) var bolt: Bolt?
    private(set) var lightningFlash = 0.0
    private var untilStrike = Double.random(in: 4...9)
    private(set) var comets: [Comet] = []
    private(set) var flocks: [Flock] = []
    private var lastTime: Double?
    private var untilComet = Double.random(in: 6...15)
    private var untilFlock = Double.random(in: 3...10)

    init() {
        clouds = (0..<4).map { _ in Ambience.makeCloud(x: Double.random(in: -0.1...1.1)) }
    }

    /// `blasts` are explosion centers in the same normalized space; nearby flocks scatter.
    func update(time: Double, wind: Double, blasts: [Vec], weather: Weather, onStrike: () -> Void) {
        let dt = lastTime.map { min(max(time - $0, 0), 0.1) } ?? 0
        lastTime = time
        guard dt > 0 else { return }

        updateWeather(dt, wind: wind, weather: weather, onStrike: onStrike)

        let drift = 0.004 + wind / Game.windReference * 0.02
        for i in clouds.indices {
            clouds[i].x += drift * dt
            if clouds[i].x > 1.3 { clouds[i] = Ambience.makeCloud(x: -0.3) }
            if clouds[i].x < -0.3 { clouds[i] = Ambience.makeCloud(x: 1.3) }
        }

        untilComet -= dt
        if untilComet <= 0 {
            comets.append(Ambience.makeComet())
            untilComet = Double.random(in: 20...40)
        }
        for i in comets.indices {
            comets[i].age += dt
            comets[i].position += comets[i].velocity * dt
        }
        comets.removeAll { $0.age >= $0.lifetime }

        untilFlock -= dt
        if untilFlock <= 0 {
            flocks.append(Ambience.makeFlock())
            untilFlock = Double.random(in: 20...45)
        }
        for i in flocks.indices {
            if !flocks[i].isSpooked, blasts.contains(where: { ($0 - flocks[i].position).length < 0.22 }) {
                flocks[i].isSpooked = true
                flocks[i].velocity = Vec(flocks[i].velocity.x * 3, -0.12)
            }
            flocks[i].flap += dt * (flocks[i].isSpooked ? 24 : 10)
            flocks[i].position += flocks[i].velocity * dt
        }
        flocks.removeAll { $0.position.x < -0.3 || $0.position.x > 1.3 || $0.position.y < -0.3 }
    }

    private func updateWeather(_ dt: Double, wind: Double, weather: Weather, onStrike: () -> Void) {
        if weather.precipitation != precipitation {
            precipitation = weather.precipitation
            switch precipitation {
            case .none: drops = []
            case .rain: drops = (0..<170).map { _ in Drop(position: Vec(Double.random(in: 0...1), Double.random(in: 0...1)), speed: Double.random(in: 1.3...1.9), size: Double.random(in: 0.025...0.045)) }
            case .snow: drops = (0..<140).map { _ in Drop(position: Vec(Double.random(in: 0...1), Double.random(in: 0...1)), speed: Double.random(in: 0.04...0.11), size: Double.random(in: 1...2.6)) }
            }
        }
        let drift = wind / Game.windReference * (precipitation == .rain ? 0.3 : 0.08)
        for i in drops.indices {
            drops[i].position += Vec(drift, drops[i].speed) * dt
            if drops[i].position.y > 1.05 {
                drops[i].position = Vec(Double.random(in: -0.1...1.1), -0.05)
            }
            if drops[i].position.x > 1.1 { drops[i].position.x -= 1.2 }
            if drops[i].position.x < -0.1 { drops[i].position.x += 1.2 }
        }

        if weather.hasLightning {
            untilStrike -= dt
            if untilStrike <= 0 {
                bolt = Ambience.makeBolt()
                lightningFlash = 1
                untilStrike = Double.random(in: 5...13)
                onStrike()
            }
        }
        bolt?.age += dt
        if let age = bolt?.age, age > Bolt.lifetime { bolt = nil }
        lightningFlash *= exp(-7 * dt)
    }

    private static func makeBolt() -> Bolt {
        var trunk = [Vec(Double.random(in: 0.15...0.85), -0.02)]
        let bottom = Double.random(in: 0.55...0.8)
        while trunk.last!.y < bottom {
            let last = trunk.last!
            trunk.append(Vec(last.x + Double.random(in: -0.03...0.03), last.y + Double.random(in: 0.03...0.06)))
        }
        let branches = (0..<2).map { _ in
            var branch = [trunk[Int.random(in: 1..<max(2, trunk.count - 2))]]
            let lean = Bool.random() ? 1.0 : -1.0
            for _ in 0..<Int.random(in: 3...5) {
                let last = branch.last!
                branch.append(Vec(last.x + lean * Double.random(in: 0.01...0.035), last.y + Double.random(in: 0.025...0.05)))
            }
            return branch
        }
        return Bolt(trunk: trunk, branches: branches)
    }

    private static func makeCloud(x: Double) -> Cloud {
        Cloud(
            x: x,
            y: Double.random(in: 0.08...0.3),
            puffs: (0..<Int.random(in: 4...6)).map { _ in
                (Double.random(in: -0.06...0.06), Double.random(in: -0.015...0.015), Double.random(in: 0.025...0.05))
            }
        )
    }

    private static func makeComet() -> Comet {
        let direction = Bool.random() ? 1.0 : -1.0
        return Comet(
            position: Vec(direction > 0 ? Double.random(in: 0...0.5) : Double.random(in: 0.5...1), Double.random(in: -0.05...0.1)),
            velocity: Vec(direction * Double.random(in: 0.25...0.4), Double.random(in: 0.05...0.12)),
            lifetime: Double.random(in: 2.5...3.5)
        )
    }

    private static func makeFlock() -> Flock {
        let direction = Bool.random() ? 1.0 : -1.0
        let count = Int.random(in: 3...6)
        let offsets = (0..<count).map { i in
            let rank = Double((i + 1) / 2)
            let side = i % 2 == 0 ? 1.0 : -1.0
            return Vec(-direction * rank * 0.022, side * rank * 0.016)
        }
        return Flock(
            position: Vec(direction > 0 ? -0.1 : 1.1, Double.random(in: 0.12...0.38)),
            velocity: Vec(direction * Double.random(in: 0.035...0.06), 0),
            offsets: offsets
        )
    }
}
