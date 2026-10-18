import Foundation

/// A snapshot of the battlefield that can predict where a shot lands, off the main thread.
/// Uses the same physics as `Game`, so the computer aims at the world it actually plays in.
struct Ballistics: Sendable {
    struct Target: Sendable {
        let id: Int
        let center: Vec
        var radius = Tank.standardRadius
    }

    struct Aim: Sendable {
        let angle: Double
        let power: Double
        let impact: Vec
        let miss: Double
    }

    let terrain: Terrain
    let wind: Double
    let gravity: Double
    /// World units per second of launch speed for each point of power.
    let speedPerPower: Double
    let origin: Vec
    let ownerID: Int
    let tanks: [Target]

    /// Where a shot with this angle and power stops: the ground, a tank, or `nil` if it leaves the world.
    func impact(angle: Double, power: Double) -> Vec? {
        let radians = angle * .pi / 180
        let direction = Vec(cos(radians), sin(radians))
        var position = origin + direction * Tank.barrelLength
        var velocity = direction * power * speedPerPower
        let dt = 1.0 / 240
        var age = 0.0
        while age < 14 {
            velocity += (Vec(wind, -gravity) + terrain.force(at: position)) * dt
            position += velocity * dt
            age += dt
            guard position.x >= 0, position.x <= Game.worldSize.x else { return nil }
            if terrain.isSwallowed(position) { return position }
            for tank in tanks where (tank.id != ownerID || age > 0.3) && (tank.center - position).length < tank.radius {
                return position
            }
            if terrain.isSolid(position) { return position }
        }
        return nil
    }

    /// Points along a shot's flight, about every 30 ms, ending where it lands.
    func trajectory(angle: Double, power: Double) -> [Vec] {
        let radians = angle * .pi / 180
        let direction = Vec(cos(radians), sin(radians))
        var position = origin + direction * Tank.barrelLength
        var velocity = direction * power * speedPerPower
        var points = [position]
        let dt = 1.0 / 240
        var age = 0.0
        var step = 0
        while age < 14 {
            velocity += (Vec(wind, -gravity) + terrain.force(at: position)) * dt
            position += velocity * dt
            age += dt
            step += 1
            if terrain.isSwallowed(position) {
                points.append(position)
                break
            }
            guard position.x >= 0, position.x <= Game.worldSize.x else { break }
            if step % 7 == 0 { points.append(position) }
            if terrain.isSolid(position) || tanks.contains(where: { ($0.id != ownerID || age > 0.3) && ($0.center - position).length < $0.radius }) {
                points.append(position)
                break
            }
        }
        return points
    }

    /// The angle and power that land closest to `target`, searching coarsely then refining.
    /// Shots landing within `safeRadius` of the shooter are never chosen.
    func bestAim(at target: Vec, safeRadius: Double = 0) -> Aim? {
        let facingRight = target.x >= origin.x
        func mirrored(_ elevation: Double) -> Double { facingRight ? elevation : 180 - elevation }

        var best: Aim?
        func consider(_ elevation: Double, _ power: Double) {
            guard (0...100).contains(power), (2...88).contains(elevation) else { return }
            let angle = mirrored(elevation)
            guard let hit = impact(angle: angle, power: power), (hit - origin).length >= safeRadius else { return }
            let miss = (hit - target).length
            if miss < best?.miss ?? .infinity {
                best = Aim(angle: angle, power: power, impact: hit, miss: miss)
            }
        }

        for elevation in stride(from: 5.0, through: 85, by: 3) {
            for power in stride(from: 10.0, through: 100, by: 3) {
                consider(elevation, power)
            }
        }
        guard let coarse = best else { return nil }
        let coarseElevation = facingRight ? coarse.angle : 180 - coarse.angle
        for elevation in stride(from: coarseElevation - 3, through: coarseElevation + 3, by: 0.5) {
            for power in stride(from: coarse.power - 4, through: coarse.power + 4, by: 0.5) {
                consider(elevation, power)
            }
        }
        return best
    }
}
