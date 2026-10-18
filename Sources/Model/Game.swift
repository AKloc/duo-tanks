import Observation
import SwiftUI
import UIKit

typealias Vec = SIMD2<Double>

extension SIMD2 where Scalar == Double {
    var length: Double { (x * x + y * y).squareRoot() }
}

extension Duration {
    var seconds: Double {
        Double(components.seconds) + Double(components.attoseconds) * 1e-18
    }
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
    var muzzle: Vec { turretCenter + barrelDirection * Tank.barrelLength }
    var barrelDirection: Vec {
        let radians = angle * .pi / 180
        return Vec(cos(radians), sin(radians))
    }

    /// `nil` means unlimited.
    func ammoCount(_ weapon: Weapon) -> Int? {
        weapon.startingAmmo == nil ? nil : ammo[weapon, default: 0]
    }
}

struct Projectile: Identifiable {
    static let maxTrail = 60

    let id = UUID()
    var position: Vec
    var velocity: Vec
    let weapon: Weapon
    let ownerID: Int
    var age = 0.0
    var trail: [Vec] = []
}

struct Explosion: Identifiable {
    static let duration = 0.7

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
    /// Power gained per second while the fire button is held.
    nonisolated static let chargeRate = 50.0

    private(set) var terrain: Terrain
    private(set) var tanks: [Tank] = []
    private(set) var projectiles: [Projectile] = []
    private(set) var explosions: [Explosion] = []
    private(set) var particles: [Particle] = []
    private(set) var floatingTexts: [FloatingText] = []
    private(set) var wind = 0.0
    private(set) var currentIndex = 0
    private(set) var phase = Phase.aiming
    /// Live power while the fire button is held; `nil` otherwise.
    private(set) var chargePower: Double?
    /// 0...1, decays after each blast.
    private(set) var shake = 0.0
    private(set) var flash = 0.0

    @ObservationIgnored private let sound = SoundEngine()
    @ObservationIgnored private let haptics = UIImpactFeedbackGenerator(style: .heavy)
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var chargeStartedAt: ContinuousClock.Instant?

    var current: Tank { tanks[currentIndex] }

    init() {
        terrain = Terrain(width: Int(Game.worldSize.x), maxHeight: Game.worldSize.y)
        newGame()
    }

    func newGame() {
        loop?.cancel()
        loop = nil
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
        particles = []
        floatingTexts = []
        chargeStartedAt = nil
        chargePower = nil
        shake = 0
        flash = 0
        currentIndex = Int.random(in: tanks.indices)
        wind = Game.randomWind()
        phase = .aiming
        sound.updateFlights([])
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

    func select(_ weapon: Weapon) {
        guard phase == .aiming, current.ammoCount(weapon) != 0 else { return }
        tanks[currentIndex].selectedWeapon = weapon
    }

    func beginCharge() {
        guard phase == .aiming, chargeStartedAt == nil else { return }
        chargeStartedAt = .now
        chargePower = 0
        startLoop()
    }

    func releaseCharge() {
        guard let start = chargeStartedAt else { return }
        let power = min((ContinuousClock.now - start).seconds * Game.chargeRate, 100).rounded()
        chargeStartedAt = nil
        chargePower = nil
        tanks[currentIndex].power = power
        fire()
    }

    private func fire() {
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
            position: tank.muzzle,
            velocity: direction * tank.power * Game.speedPerPower,
            weapon: weapon,
            ownerID: tank.id
        )]
        particles += ParticleFactory.muzzle(at: tank.muzzle, direction: direction)
        sound.launch(atX: tank.position.x)
        haptics.impactOccurred(intensity: 0.5)
        shake = max(shake, 0.15)
        phase = .firing
        startLoop()
    }

    // MARK: Simulation

    private func startLoop() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            var last = ContinuousClock.now
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(16))
                let now = ContinuousClock.now
                let dt = min((now - last).seconds, 1.0 / 20)
                last = now
                guard let self else { return }
                if !self.advance(by: dt) {
                    self.loop = nil
                    return
                }
            }
        }
    }

    /// Returns false once nothing is moving and the loop can stop.
    private func advance(by dt: Double) -> Bool {
        if let start = chargeStartedAt {
            chargePower = min((ContinuousClock.now - start).seconds * Game.chargeRate, 100).rounded()
        }

        if phase == .firing {
            var remaining = dt
            while remaining > 0 {
                let step = min(remaining, 1.0 / 240)
                simulate(step)
                remaining -= step
            }
            sound.updateFlights(projectiles)
        }

        updateEffects(dt)

        let isSettling = tanks.contains { $0.position.y > terrain.height(at: $0.position.x) + 0.5 }
        if phase == .firing, projectiles.isEmpty, explosions.isEmpty, !isSettling {
            endTurn()
        }

        let isAnimating = !particles.isEmpty || !floatingTexts.isEmpty || !explosions.isEmpty || shake > 0.01 || flash > 0.01
        if !isAnimating && phase != .firing && chargeStartedAt == nil {
            shake = 0
            flash = 0
            return false
        }
        return true
    }

    private func simulate(_ dt: Double) {
        var next: [Projectile] = []
        for var p in projectiles {
            p.velocity += Vec(wind, -Game.gravity) * dt
            p.position += p.velocity * dt
            p.age += dt
            if p.trail.last.map({ ($0 - p.position).length > 5 }) ?? true {
                p.trail.append(p.position)
                if p.trail.count > Projectile.maxTrail { p.trail.removeFirst() }
            }

            if case let .splitAtApex(count, child) = p.weapon.behavior, p.velocity.y <= 0 {
                for i in 0..<count {
                    let spread = (Double(i) - Double(count - 1) / 2) * 22
                    next.append(Projectile(position: p.position, velocity: Vec(p.velocity.x + spread, p.velocity.y), weapon: child, ownerID: p.ownerID, age: p.age, trail: [p.position]))
                }
                particles += (0..<12).map { _ in
                    Particle(kind: .spark, position: p.position, velocity: Vec(Double.random(in: -80...80), Double.random(in: -80...80)), lifetime: 0.3, size: 1.8, color: .cyan)
                }
                continue
            }

            guard p.position.x >= 0, p.position.x <= Game.worldSize.x else { continue }

            let hitTank = tanks.first { tank in
                tank.isAlive && (tank.id != p.ownerID || p.age > 0.3) && (tank.turretCenter - p.position).length < Tank.hitRadius
            }
            let ground = terrain.height(at: p.position.x)
            if hitTank != nil || p.position.y <= ground {
                next += detonate(p.weapon, at: Vec(p.position.x, max(p.position.y, ground)), ownerID: p.ownerID, directHitID: hitTank?.id)
                continue
            }
            next.append(p)
        }
        projectiles = next
        settleTanks(dt)
    }

    private func detonate(_ weapon: Weapon, at center: Vec, ownerID: Int, directHitID: Int?) -> [Projectile] {
        switch weapon.behavior {
        case .dirt:
            terrain.addDirt(center: center, radius: weapon.blastRadius)
            explosions.append(Explosion(center: center, radius: weapon.blastRadius, isDirt: true))
            particles += ParticleFactory.dirt(at: center, radius: weapon.blastRadius)
            sound.dirt(atX: center.x)
            shake = max(shake, 0.25)
            return []
        case let .scatterOnImpact(count, child):
            explode(weapon, at: center, directHitID: directHitID)
            return (0..<count).map { _ in
                let angle = Double.random(in: 0.25...(.pi - 0.25))
                let speed = Double.random(in: 120...260)
                return Projectile(position: center + Vec(0, 3), velocity: Vec(cos(angle), sin(angle)) * speed, weapon: child, ownerID: ownerID, age: 1)
            }
        case .explode, .splitAtApex:
            explode(weapon, at: center, directHitID: directHitID)
            return []
        }
    }

    private func explode(_ weapon: Weapon, at center: Vec, directHitID: Int?) {
        let radius = weapon.blastRadius
        terrain.carve(center: center, radius: radius)
        explosions.append(Explosion(center: center, radius: radius, isDirt: false))
        particles += ParticleFactory.explosion(at: center, radius: radius)
        sound.explosion(atX: center.x, radius: radius)
        haptics.impactOccurred(intensity: min(1, 0.4 + radius / 80))
        shake = min(1, max(shake, radius / 70))
        if radius >= 50 { flash = max(flash, min(1, radius / 100)) }

        let reach = radius + Tank.hitRadius
        for i in tanks.indices where tanks[i].isAlive {
            let distance = tanks[i].id == directHitID ? 0 : (tanks[i].turretCenter - center).length
            guard distance < reach else { continue }
            let falloff = distance / reach
            damage(tankAt: i, by: weapon.damage * (1 - falloff * falloff))
        }
    }

    private func damage(tankAt index: Int, by amount: Double) {
        let applied = min(amount, tanks[index].health)
        guard applied >= 1 else { return }
        tanks[index].health -= applied
        floatingTexts.append(FloatingText(position: tanks[index].turretCenter + Vec(0, 26), text: "-\(Int(applied.rounded()))", color: tanks[index].color))
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
                        damage(tankAt: i, by: max(0, tanks[i].fallDistance - 6) * 0.5)
                    }
                    tanks[i].fallDistance = 0
                }
            }
        }
    }

    private func updateEffects(_ dt: Double) {
        for i in explosions.indices { explosions[i].age += dt }
        explosions.removeAll { $0.age >= Explosion.duration }

        for i in floatingTexts.indices { floatingTexts[i].age += dt }
        floatingTexts.removeAll { $0.age >= FloatingText.lifetime }

        for i in particles.indices {
            var p = particles[i]
            p.age += dt
            switch p.kind {
            case .spark:
                p.velocity *= 1 - 2.5 * dt
                p.velocity.y -= Game.gravity * 0.3 * dt
            case .debris:
                p.velocity.y -= Game.gravity * dt
                p.velocity.x += wind * dt
            case .smoke:
                p.velocity.x += wind * 0.5 * dt
            }
            p.position += p.velocity * dt
            if p.kind == .debris, p.position.y < terrain.height(at: p.position.x) { p.age = p.lifetime }
            particles[i] = p
        }
        particles.removeAll { $0.age >= $0.lifetime }
        if particles.count > 600 { particles.removeFirst(particles.count - 600) }

        shake *= exp(-5 * dt)
        flash *= exp(-6 * dt)
    }

    private func endTurn() {
        sound.updateFlights([])
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
