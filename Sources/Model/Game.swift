import Observation
import SwiftUI

typealias Vec = SIMD2<Double>

extension SIMD2 where Scalar == Double {
    var length: Double { (x * x + y * y).squareRoot() }
}

struct Tank: Identifiable {
    static let bodyHeight = 7.0
    static let hitRadius = 12.0
    static let barrelLength = 16.0

    let id: Int
    let name: String
    let color: Color
    var position: Vec
    var health = 100.0
    var angle: Double
    var power = 55.0
    var ammo: [Weapon: Int]
    var selectedWeapon = Weapon.babyMissile
    var fallDistance = 0.0

    var isAlive: Bool { health > 0 }
    var turretCenter: Vec { position + Vec(0, Tank.bodyHeight) }
    var barrelDirection: Vec {
        let radians = angle * .pi / 180
        return Vec(cos(radians), sin(radians))
    }

    /// `nil` means unlimited.
    func ammoCount(_ weapon: Weapon) -> Int? {
        weapon.startingAmmo == nil ? nil : ammo[weapon, default: 0]
    }
}

struct Projectile {
    var position: Vec
    var velocity: Vec
    let weapon: Weapon
    let ownerID: Int
    var age = 0.0
    var trail: [Vec] = []
}

struct Explosion: Identifiable {
    static let duration = 0.6

    let id = UUID()
    let center: Vec
    let radius: Double
    let isDirt: Bool
    var age = 0.0

    var progress: Double { min(age / Explosion.duration, 1) }
}

enum Phase: Equatable {
    case aiming
    case firing
    case gameOver(winnerID: Int?)
}

@MainActor
@Observable
final class Game {
    nonisolated static let worldSize = Vec(1000, 400)
    nonisolated static let gravity = 200.0
    nonisolated static let maxWind = 45.0
    nonisolated static let speedPerPower = 6.0
    nonisolated static let fallSpeed = 160.0

    private(set) var terrain: Terrain
    private(set) var tanks: [Tank] = []
    private(set) var projectiles: [Projectile] = []
    private(set) var explosions: [Explosion] = []
    private(set) var wind = 0.0
    private(set) var currentIndex = 0
    private(set) var phase = Phase.aiming

    @ObservationIgnored private var loop: Task<Void, Never>?

    var current: Tank { tanks[currentIndex] }

    init() {
        terrain = Terrain(width: Int(Game.worldSize.x), maxHeight: Game.worldSize.y)
        newGame()
    }

    func newGame() {
        loop?.cancel()
        terrain = Terrain(width: Int(Game.worldSize.x), maxHeight: Game.worldSize.y)
        let startingAmmo = Dictionary(uniqueKeysWithValues: Weapon.arsenal.compactMap { w in w.startingAmmo.map { (w, $0) } })
        let players: [(String, Color, ClosedRange<Double>, Double)] = [
            ("Red", .red, 70...300, 60),
            ("Blue", .blue, 700...930, 120),
        ]
        tanks = players.enumerated().map { index, player in
            let x = Double.random(in: player.2)
            terrain.flatten(around: x, halfWidth: 14)
            return Tank(id: index, name: player.0, color: player.1, position: Vec(x, terrain.height(at: x)), angle: player.3, ammo: startingAmmo)
        }
        projectiles = []
        explosions = []
        currentIndex = Int.random(in: tanks.indices)
        wind = Game.randomWind()
        phase = .aiming
    }

    // MARK: Aiming

    func setAngle(_ angle: Double) {
        guard phase == .aiming else { return }
        tanks[currentIndex].angle = min(max(angle, 0), 180).rounded()
    }

    /// Hinge opening sets elevation; the barrel keeps facing the side it already faces.
    func aimWithHinge(degrees: Double) {
        let elevation = min(max(degrees - 80, 0), 90)
        setAngle(current.angle <= 90 ? elevation : 180 - elevation)
    }

    func setPower(_ power: Double) {
        guard phase == .aiming else { return }
        tanks[currentIndex].power = min(max(power, 0), 100).rounded()
    }

    func select(_ weapon: Weapon) {
        guard phase == .aiming, current.ammoCount(weapon) != 0 else { return }
        tanks[currentIndex].selectedWeapon = weapon
    }

    func fire() {
        guard phase == .aiming else { return }
        var tank = current
        let weapon = tank.selectedWeapon
        if let count = tank.ammoCount(weapon) {
            guard count > 0 else { return }
            tank.ammo[weapon] = count - 1
            if count == 1 { tank.selectedWeapon = .babyMissile }
        }
        tanks[currentIndex] = tank

        let direction = tank.barrelDirection
        projectiles = [Projectile(
            position: tank.turretCenter + direction * Tank.barrelLength,
            velocity: direction * tank.power * Game.speedPerPower,
            weapon: weapon,
            ownerID: tank.id
        )]
        phase = .firing
        startLoop()
    }

    // MARK: Simulation

    private func startLoop() {
        loop?.cancel()
        loop = Task { [weak self] in
            var last = ContinuousClock.now
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(16))
                let now = ContinuousClock.now
                let elapsed = (now - last).components
                last = now
                let dt = min(Double(elapsed.seconds) + Double(elapsed.attoseconds) * 1e-18, 1.0 / 20)
                guard let self, self.advance(by: dt) else { return }
            }
        }
    }

    /// Returns false once everything has come to rest and the turn is over.
    private func advance(by dt: Double) -> Bool {
        var remaining = dt
        while remaining > 0 {
            let step = min(remaining, 1.0 / 240)
            simulate(step)
            remaining -= step
        }

        for i in explosions.indices { explosions[i].age += dt }
        explosions.removeAll { $0.age >= Explosion.duration }

        let isSettling = tanks.contains { $0.position.y > terrain.height(at: $0.position.x) + 0.5 }
        guard projectiles.isEmpty, explosions.isEmpty, !isSettling else { return true }
        endTurn()
        return false
    }

    private func simulate(_ dt: Double) {
        var next: [Projectile] = []
        for var p in projectiles {
            p.velocity += Vec(wind, -Game.gravity) * dt
            p.position += p.velocity * dt
            p.age += dt
            if p.trail.last.map({ ($0 - p.position).length > 5 }) ?? true {
                p.trail.append(p.position)
            }

            if case let .splitAtApex(count, child) = p.weapon.behavior, p.velocity.y <= 0 {
                for i in 0..<count {
                    let spread = (Double(i) - Double(count - 1) / 2) * 22
                    next.append(Projectile(position: p.position, velocity: Vec(p.velocity.x + spread, p.velocity.y), weapon: child, ownerID: p.ownerID, age: p.age, trail: [p.position]))
                }
                continue
            }

            guard p.position.x >= 0, p.position.x <= Game.worldSize.x else { continue }

            let hitTank = tanks.contains { tank in
                tank.isAlive && (tank.id != p.ownerID || p.age > 0.3) && (tank.turretCenter - p.position).length < Tank.hitRadius
            }
            let ground = terrain.height(at: p.position.x)
            if hitTank || p.position.y <= ground {
                next += detonate(p.weapon, at: Vec(p.position.x, max(p.position.y, ground)), ownerID: p.ownerID)
                continue
            }
            next.append(p)
        }
        projectiles = next
        settleTanks(dt)
    }

    private func detonate(_ weapon: Weapon, at center: Vec, ownerID: Int) -> [Projectile] {
        switch weapon.behavior {
        case .dirt:
            terrain.addDirt(center: center, radius: weapon.blastRadius)
            explosions.append(Explosion(center: center, radius: weapon.blastRadius, isDirt: true))
            return []
        case let .scatterOnImpact(count, child):
            explode(weapon, at: center)
            return (0..<count).map { _ in
                let angle = Double.random(in: 0.25...(.pi - 0.25))
                let speed = Double.random(in: 120...260)
                return Projectile(position: center + Vec(0, 3), velocity: Vec(cos(angle), sin(angle)) * speed, weapon: child, ownerID: ownerID, age: 1)
            }
        case .explode, .splitAtApex:
            explode(weapon, at: center)
            return []
        }
    }

    private func explode(_ weapon: Weapon, at center: Vec) {
        terrain.carve(center: center, radius: weapon.blastRadius)
        explosions.append(Explosion(center: center, radius: weapon.blastRadius, isDirt: false))
        let reach = weapon.blastRadius + Tank.hitRadius
        for i in tanks.indices where tanks[i].isAlive {
            let distance = (tanks[i].turretCenter - center).length
            guard distance < reach else { continue }
            tanks[i].health = max(0, tanks[i].health - weapon.damage * (1 - distance / reach))
        }
    }

    private func settleTanks(_ dt: Double) {
        for i in tanks.indices {
            let ground = terrain.height(at: tanks[i].position.x)
            if tanks[i].position.y > ground + 0.5 {
                let drop = min(Game.fallSpeed * dt, tanks[i].position.y - ground)
                tanks[i].position.y -= drop
                tanks[i].fallDistance += drop
            } else {
                tanks[i].position.y = ground
                if tanks[i].fallDistance > 0 {
                    if tanks[i].isAlive {
                        tanks[i].health = max(0, tanks[i].health - max(0, tanks[i].fallDistance - 6) * 0.5)
                    }
                    tanks[i].fallDistance = 0
                }
            }
        }
    }

    private func endTurn() {
        let alive = tanks.filter(\.isAlive)
        if alive.count <= 1 {
            phase = .gameOver(winnerID: alive.first?.id)
            return
        }
        repeat {
            currentIndex = (currentIndex + 1) % tanks.count
        } while !tanks[currentIndex].isAlive
        wind = Game.randomWind()
        phase = .aiming
    }

    private static func randomWind() -> Double {
        Double.random(in: -maxWind...maxWind).rounded()
    }
}
