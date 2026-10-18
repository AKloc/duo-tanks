import SwiftUI

struct Particle {
    enum Kind { case spark, debris, smoke, fire }

    let kind: Kind
    var position: Vec
    var velocity: Vec
    var age = 0.0
    let lifetime: Double
    let size: Double
    let color: Color

    var progress: Double { min(age / lifetime, 1) }
}

struct FloatingText: Identifiable {
    static let lifetime = 1.3

    let id = UUID()
    let position: Vec
    let text: String
    let color: Color
    var age = 0.0

    var progress: Double { min(age / FloatingText.lifetime, 1) }
}

enum ParticleFactory {
    static func explosion(at center: Vec, radius: Double) -> [Particle] {
        let sparks = (0..<Int(10 + radius * 0.8)).map { _ in
            Particle(
                kind: .spark,
                position: center,
                velocity: randomDirection(upward: false) * Double.random(in: 60...(160 + radius * 4)),
                lifetime: Double.random(in: 0.25...0.7),
                size: Double.random(in: 1.2...2.6),
                color: [.yellow, .orange, .white].randomElement()!
            )
        }
        let debris = (0..<Int(6 + radius * 0.5)).map { _ in
            Particle(
                kind: .debris,
                position: center + Vec(0, 2),
                velocity: randomDirection(upward: true) * Double.random(in: 80...(140 + radius * 3)),
                lifetime: Double.random(in: 0.8...1.6),
                size: Double.random(in: 1.5...3.5),
                color: Color(red: Double.random(in: 0.3...0.45), green: Double.random(in: 0.2...0.3), blue: 0.1)
            )
        }
        let fire = (0..<Int(8 + radius / 3)).map { _ in
            let direction = randomDirection(upward: false)
            return Particle(
                kind: .fire,
                position: center + direction * Double.random(in: 0...(radius * 0.35)),
                velocity: direction * Double.random(in: 20...(60 + radius * 1.5)) + Vec(0, 20),
                lifetime: Double.random(in: 0.6...1.1),
                size: Double.random(in: (radius * 0.22)...(radius * 0.45)),
                color: .orange
            )
        }
        let smoke = (0..<Int(4 + radius / 6)).map { _ in
            Particle(
                kind: .smoke,
                position: center + randomDirection(upward: false) * Double.random(in: 0...(radius * 0.5)),
                velocity: Vec(Double.random(in: -10...10), Double.random(in: 20...45)),
                lifetime: Double.random(in: 1.8...3.2),
                size: Double.random(in: (radius * 0.35)...(radius * 0.7)),
                color: Color(white: 0.22)
            )
        }
        return sparks + debris + fire + smoke
    }

    static func shellSmoke(at point: Vec) -> Particle {
        Particle(
            kind: .smoke,
            position: point,
            velocity: Vec(Double.random(in: -4...4), Double.random(in: 4...10)),
            lifetime: Double.random(in: 0.9...1.6),
            size: Double.random(in: 1.6...3),
            color: Color(white: 0.7)
        )
    }

    static func dirt(at center: Vec, radius: Double) -> [Particle] {
        (0..<Int(10 + radius * 0.6)).map { _ in
            Particle(
                kind: .debris,
                position: center,
                velocity: randomDirection(upward: true) * Double.random(in: 40...140),
                lifetime: Double.random(in: 0.6...1.2),
                size: Double.random(in: 1.5...3.5),
                color: Color(red: 0.42, green: 0.28, blue: 0.13)
            )
        }
    }

    static func muzzle(at point: Vec, direction: Vec) -> [Particle] {
        let flash = (0..<14).map { _ in
            Particle(
                kind: .spark,
                position: point,
                velocity: (direction + randomDirection(upward: false) * 0.45) * Double.random(in: 60...180),
                lifetime: Double.random(in: 0.12...0.3),
                size: Double.random(in: 1.2...2.4),
                color: [.yellow, .orange, .white].randomElement()!
            )
        }
        let puff = (0..<4).map { _ in
            Particle(
                kind: .smoke,
                position: point,
                velocity: direction * Double.random(in: 15...35) + Vec(0, 12),
                lifetime: Double.random(in: 0.8...1.4),
                size: Double.random(in: 5...9),
                color: .gray
            )
        }
        return flash + puff
    }

    private static func randomDirection(upward: Bool) -> Vec {
        let angle = upward ? Double.random(in: 0.2...(.pi - 0.2)) : Double.random(in: 0...(2 * .pi))
        return Vec(cos(angle), sin(angle))
    }
}
