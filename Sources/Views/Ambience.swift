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

    private(set) var clouds: [Cloud]
    private(set) var comets: [Comet] = []
    private(set) var flocks: [Flock] = []
    private var lastTime: Double?
    private var untilComet = Double.random(in: 6...15)
    private var untilFlock = Double.random(in: 3...10)

    init() {
        clouds = (0..<4).map { _ in Ambience.makeCloud(x: Double.random(in: -0.1...1.1)) }
    }

    /// `blasts` are explosion centers in the same normalized space; nearby flocks scatter.
    func update(time: Double, wind: Double, blasts: [Vec]) {
        let dt = lastTime.map { min(max(time - $0, 0), 0.1) } ?? 0
        lastTime = time
        guard dt > 0 else { return }

        let drift = 0.004 + wind / Game.maxWind * 0.02
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
