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
    static let maxShield = 60.0
    /// Dirt deeper than this over a tank counts as burying it.
    static let buriedThreshold = 3.0

    let id: Int
    let name: String
    let color: Color
    var position: Vec
    var health = 100.0
    var shield = 0.0
    var angle: Double
    var power = 55.0
    var inventory: Inventory
    var selectedWeapon = Weapon.babyMissile
    var fallDistance = 0.0
    var isParachuting = false
    /// Who last hurt or undermined this tank, so fall damage and kills get credited.
    var lastAttackerID: Int?
    /// Rocking from nearby blasts (radians), settling on a spring. Visual only.
    var tilt = 0.0
    var tiltVelocity = 0.0
    /// Height of a blast-induced hop above the ground. Visual only.
    var hop = 0.0
    var hopVelocity = 0.0
    var hasTurret = true
    /// How far the treads have turned, for animating them.
    var treadTravel = 0.0

    /// How deep under the dirt this tank sits; 0 when it's on the surface.
    func buriedDepth(in terrain: Terrain) -> Double {
        max(0, terrain.height(at: position.x) - position.y)
    }

    func isBuried(in terrain: Terrain) -> Bool {
        buriedDepth(in: terrain) > Tank.buriedThreshold
    }

    var isRocking: Bool { abs(tilt) > 0.002 || abs(tiltVelocity) > 0.01 || hop > 0.01 || hopVelocity > 0.01 }

    var isAlive: Bool { health > 0 }
    var turretCenter: Vec { position + Vec(0, Tank.bodyHeight) }
    var muzzle: Vec { turretCenter + barrelDirection * Tank.barrelLength }
    var barrelDirection: Vec {
        let radians = angle * .pi / 180
        return Vec(cos(radians), sin(radians))
    }

    /// `nil` means unlimited.
    func ammoCount(_ weapon: Weapon) -> Int? {
        inventory.count(of: weapon)
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
    var smokeTimer = 0.0
    var bouncesLeft = 0
    /// Set while a Roller is rolling: -1 left, +1 right.
    var rollDirection: Double?
    var rollTime = 0.0
    /// Set while a Sandhog is tunneling: seconds left underground.
    var burrowTimeLeft: Double?
    var burrowDistance = 0.0

    var isFlying: Bool { rollDirection == nil && burrowTimeLeft == nil }
}

struct Explosion: Identifiable {
    enum Style { case fire, dirt, plasma }

    static let duration = 0.7

    let id = UUID()
    let center: Vec
    let radius: Double
    let style: Style
    var age = 0.0

    var progress: Double { min(age / Explosion.duration, 1) }
}

/// A crater that keeps trickling smoke for a while after the blast.
struct Smolder {
    let x: Double
    let spread: Double
    let duration: Double
    var remaining: Double
    var timer = 0.0

    var intensity: Double { remaining / duration }
}

/// A laser beam's path, fading out.
struct Beam: Identifiable {
    static let lifetime = 0.6

    let id = UUID()
    let points: [Vec]
    var age = 0.0
}

/// Burning napalm fuel that runs downhill.
struct Flame: Identifiable {
    let id = UUID()
    var x: Double
    var life: Double
    let ownerID: Int
    var emitTimer = 0.0
}

/// A turret blown off a destroyed tank, tumbling until it comes to rest.
struct FlyingTurret: Identifiable {
    let id = UUID()
    var position: Vec
    var velocity: Vec
    var angle: Double
    var spin: Double
    let color: Color
    var isResting = false
}

struct Camera: Equatable {
    var center: Vec
    var zoom: Double

    /// The whole battlefield; a center height of 0 means "as low as the view allows".
    static let overview = Camera(center: Vec(Game.worldSize.x / 2, 0), zoom: 1)
}

/// Everything needed to play the last shot again exactly.
private struct ShotSnapshot {
    let terrain: Terrain
    let tanks: [Tank]
    let wind: Double
    let shooterIndex: Int
    let weapon: Weapon
    let seed: UInt64
    let roundEarnings: [Int: RoundEarnings]
    let players: [Player]
}

enum Phase: Equatable {
    case aiming
    case firing
    /// Slow-motion replay of the shot that ended the round.
    case killCam
    case roundOver(winnerID: Int?)
    case shopping(playerIndex: Int)
    case matchOver
}

@MainActor
@Observable
final class Game {
    nonisolated static let worldSize = Vec(1000, 400)
    nonisolated static let standardGravity = 200.0
    /// Normal-setting maximum wind, used to scale wind visuals.
    nonisolated static let windReference = 45.0
    nonisolated static let speedPerPower = 6.0
    nonisolated static let fallSpeed = 160.0
    nonisolated static let parachuteSpeed = 35.0
    nonisolated static let driveSpeed = 28.0
    /// Falls shorter than this are free; beyond it, each unit costs `fallDamagePerUnit`.
    nonisolated static let safeFallHeight = 5.0
    nonisolated static let fallDamagePerUnit = 0.75
    /// At or below this health the music switches to its danger arrangement.
    nonisolated static let dangerHealth = 20.0
    /// Power gained per second while the fire button is held.
    nonisolated static let chargeRate = 50.0
    /// The simulation always advances in steps this long, so a shot plays out the same way every time.
    nonisolated static let stepDuration = 1.0 / 240

    private(set) var settings: MatchSettings
    private(set) var theme = WorldTheme.hills
    private(set) var weather = Weather.clear
    private(set) var gravity = Game.standardGravity
    private(set) var maxWind = Game.windReference
    private(set) var players: [Player] = []
    private(set) var round = 0
    private(set) var roundEarnings: [Int: RoundEarnings] = [:]

    private(set) var terrain: Terrain
    private(set) var tanks: [Tank] = []
    private(set) var projectiles: [Projectile] = []
    private(set) var flames: [Flame] = []
    private(set) var tracers: [Int: [Vec]] = [:]
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
    private(set) var turrets: [FlyingTurret] = []
    private(set) var beams: [Beam] = []
    /// `nil` shows the whole battlefield.
    private(set) var camera: Camera?
    /// Playback speed of the simulation; slowed during the kill cam.
    private(set) var timeScale = 1.0
    /// -1 or +1 while the current tank is driving.
    private(set) var driveDirection: Double?
    /// What the computer is doing on its turn, for the control panel.
    private(set) var computerStatus: String?

    @ObservationIgnored private let sound = SoundEngine()
    @ObservationIgnored private let haptics = UIImpactFeedbackGenerator(style: .heavy)
    @ObservationIgnored private let detents = UISelectionFeedbackGenerator()
    @ObservationIgnored private let rumble = ChargeRumble()
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var chargeStartedAt: ContinuousClock.Instant?
    @ObservationIgnored private var smolders: [Smolder] = []
    @ObservationIgnored private var tankSmokeTimers: [Int: Double] = [:]
    @ObservationIgnored private var pendingWrecks: [Int] = []
    @ObservationIgnored private var burnDamage: [Int: Double] = [:]
    @ObservationIgnored private var burnTextTimer = 0.0
    @ObservationIgnored private var computerTask: Task<Void, Never>?
    @ObservationIgnored private var accumulator = 0.0
    /// Drives gameplay randomness (bomblet scatter, napalm spread); reseeded for every shot.
    @ObservationIgnored private var rng = SeededRandom(seed: 1)
    /// Where the most recent blast went off.
    @ObservationIgnored private(set) var lastImpact: Vec?
    @ObservationIgnored private var lastShot: ShotSnapshot?
    @ObservationIgnored private var victimsThisShot: [Int] = []
    @ObservationIgnored private var finalOutcome: (earnings: [Int: RoundEarnings], players: [Player])?
    @ObservationIgnored private var killCamHold = 0.0
    @ObservationIgnored private var killCamImpactTime: Double?
    @ObservationIgnored private var killCamVictimID: Int?
    @ObservationIgnored private var driveTickDistance = 0.0

    var current: Tank { tanks[currentIndex] }

    var isComputerTurn: Bool {
        players.first { $0.id == current.id }?.isComputer ?? false
    }

    /// Launch speed for a power setting. Low gravity slows launches a little, so shots float and carry farther but stay on screen.
    func launchSpeed(forPower power: Double) -> Double {
        power * Game.speedPerPower * pow(theme.gravityScale, 0.35)
    }

    func setComputerStatus(_ status: String?) {
        computerStatus = status
    }

    var standings: [Player] {
        players.sorted { ($0.wins, $0.money) > ($1.wins, $1.money) }
    }

    init(settings: MatchSettings = MatchSettings()) {
        self.settings = settings
        terrain = Terrain(width: Int(Game.worldSize.x), maxHeight: Game.worldSize.y)
        startMatch(settings)
    }

    func thunder() {
        sound.thunder(atX: Double.random(in: 0...Game.worldSize.x))
        buzz(0.3)
    }

    func setMusicEnabled(_ enabled: Bool) {
        settings.musicEnabled = enabled
        updateMusic()
    }

    /// Music follows the fight: low health, the final round, charging and shells in flight raise the tension.
    private func updateMusic() {
        var tension: Double
        var level = 0.55
        switch phase {
        case .roundOver, .matchOver: tension = 0.1
        case .shopping: tension = 0.05
        case .killCam:
            tension = 0.95
            level = 0.7
        case .aiming, .firing:
            let lowest = tanks.filter(\.isAlive).map(\.health).min() ?? 100
            tension = 0.15 + 0.45 * (1 - lowest / 100)
            if round == settings.rounds { tension += 0.15 }
            if phase == .firing { tension += 0.15 }
            if chargePower != nil { tension += 0.1 }
        }
        let isDanger = (phase == .aiming || phase == .firing) && tanks.contains { $0.isAlive && $0.health <= Game.dangerHealth }
        sound.setMusic(tension: tension, enabled: settings.musicEnabled, level: level, danger: isDanger)
    }

    private func buzz(_ intensity: Double) {
        guard settings.hapticsEnabled else { return }
        haptics.impactOccurred(intensity: intensity)
    }

    // MARK: Match flow

    func startMatch(_ settings: MatchSettings) {
        self.settings = settings
        sound.volume = settings.volume
        players = [
            Player(id: 0, name: "Red", color: .red, money: settings.startingMoney),
            Player(id: 1, name: settings.computerOpponent == nil ? "Blue" : "CPU", color: .blue, money: settings.startingMoney,
                   computer: settings.computerOpponent),
        ]
        round = 0
        startRound()
    }

    func newMatch() {
        startMatch(settings)
    }

    private func startRound() {
        loop?.cancel()
        loop = nil
        computerTask?.cancel()
        computerTask = nil
        computerStatus = nil
        round += 1
        theme = settings.world.theme ?? WorldTheme.allCases.randomElement()!
        weather = settings.weather.resolve(for: theme)
        gravity = Game.standardGravity * theme.gravityScale
        maxWind = Game.windReference * settings.wind.scale * theme.windScale
        terrain = Terrain(width: Int(Game.worldSize.x), maxHeight: Game.worldSize.y, theme: theme, roughness: settings.roughness.scale)
        let lanes: [ClosedRange<Double>] = [70...300, 700...930]
        tanks = players.map { player in
            let x = Double.random(in: lanes[player.id % lanes.count])
            terrain.flatten(around: x, halfWidth: 14)
            return Tank(
                id: player.id, name: player.name, color: player.color,
                position: Vec(x, terrain.height(at: x)),
                angle: x < Game.worldSize.x / 2 ? 60 : 120,
                inventory: player.inventory
            )
        }
        roundEarnings = Dictionary(uniqueKeysWithValues: players.map { ($0.id, RoundEarnings()) })
        driveDirection = nil
        projectiles = []
        flames = []
        tracers = [:]
        explosions = []
        particles = []
        floatingTexts = []
        turrets = []
        beams = []
        camera = nil
        timeScale = 1
        lastShot = nil
        finalOutcome = nil
        smolders = []
        tankSmokeTimers = [:]
        pendingWrecks = []
        burnDamage = [:]
        chargeStartedAt = nil
        chargePower = nil
        rumble.stop()
        shake = 0
        flash = 0
        currentIndex = Int.random(in: tanks.indices)
        wind = randomWind()
        phase = .aiming
        sound.updateFlights([])
        updateMusic()
        scheduleComputerTurn()
    }




    private func scheduleComputerTurn() {
        guard phase == .aiming, let difficulty = players.first(where: { $0.id == current.id })?.computer else { return }
        computerTask = Task { [weak self] in
            guard let self else { return }
            await ComputerPlayer.takeTurn(in: self, difficulty: difficulty)
        }
    }

    private func shopForComputers() {
        while case let .shopping(index) = phase, let difficulty = players[index].computer {
            ComputerPlayer.shop(in: self, playerIndex: index, difficulty: difficulty)
            finishShopping()
        }
    }

    private func endRound(winnerID: Int?) {
        for player in players {
            roundEarnings[player.id, default: RoundEarnings()].bonus += Economy.participation + (player.id == winnerID ? Economy.roundWin : 0)
        }
        for i in players.indices {
            players[i].money += roundEarnings[players[i].id]?.total ?? 0
            if let tank = tanks.first(where: { $0.id == players[i].id }) {
                players[i].inventory = tank.inventory
            }
            if players[i].id == winnerID { players[i].wins += 1 }
        }
        phase = .roundOver(winnerID: winnerID)
        sound.playFanfare()
        updateMusic()
    }

    func continueAfterRound() {
        guard case .roundOver = phase else { return }
        phase = round >= settings.rounds ? .matchOver : .shopping(playerIndex: 0)
        updateMusic()
        shopForComputers()
    }

    func buy(_ item: ShopItem) {
        guard case let .shopping(index) = phase, players[index].money >= item.price else { return }
        players[index].money -= item.price
        players[index].inventory.add(item, quantity: item.bundle)
    }

    func finishShopping() {
        guard case let .shopping(index) = phase else { return }
        if index + 1 < players.count {
            phase = .shopping(playerIndex: index + 1)
            if !players[index + 1].isComputer { return }
            shopForComputers()
        } else {
            startRound()
        }
    }

    // MARK: Aiming and gear

    func setAngle(_ angle: Double) {
        guard phase == .aiming else { return }
        tanks[currentIndex].angle = min(max(angle, 0), 180).rounded()
    }

    /// Hinge opening sets elevation; the barrel keeps facing the side it already faces.
    /// A light tick every 5° makes the hinge feel like a dial.
    func aimWithHinge(degrees: Double) {
        guard phase == .aiming, !isComputerTurn else { return }
        let before = current.angle
        let elevation = min(max(degrees - 80, 0), 90)
        setAngle(before <= 90 ? elevation : 180 - elevation)
        if settings.hapticsEnabled, Int(before / 5) != Int(current.angle / 5) {
            detents.selectionChanged()
        }
    }

    func select(_ weapon: Weapon) {
        guard phase == .aiming, current.ammoCount(weapon) != 0 else { return }
        tanks[currentIndex].selectedWeapon = weapon
    }

    func activateShield() {
        guard phase == .aiming, current.inventory.shields > 0, current.shield <= 0 else { return }
        tanks[currentIndex].inventory.shields -= 1
        tanks[currentIndex].shield = Tank.maxShield
        buzz(0.4)
    }

    func useRepairKit() {
        guard phase == .aiming, current.inventory.repairKits > 0, current.health < 100 else { return }
        let healed = min(35, 100 - current.health)
        tanks[currentIndex].inventory.repairKits -= 1
        tanks[currentIndex].health += healed
        floatingTexts.append(FloatingText(position: current.turretCenter + Vec(0, 26), text: "+\(Int(healed.rounded()))", color: .green))
        buzz(0.4)
        startLoop()
    }

    func startDriving(_ direction: Double) {
        guard phase == .aiming, current.inventory.fuel > 0 else { return }
        driveDirection = direction < 0 ? -1 : 1
        startLoop()
    }

    func stopDriving() {
        driveDirection = nil
    }

    private func drive(_ dt: Double) {
        guard let direction = driveDirection, phase == .aiming else { return }
        var tank = current
        let step = min(Game.driveSpeed * dt, tank.inventory.fuel)
        guard step > 0 else { return stopDriving() }
        let nextX = min(max(tank.position.x + direction * step, 12), Game.worldSize.x - 12)
        let ahead = terrain.height(at: nextX)
        if tank.isBuried(in: terrain) {
            stopDriving()
            floatingTexts.append(FloatingText(position: tank.turretCenter + Vec(0, 26), text: "Buried", color: .gray))
            buzz(0.3)
            return
        }
        if ahead - tank.position.y > step * 1.3 + 0.2 {
            stopDriving()
            floatingTexts.append(FloatingText(position: tank.turretCenter + Vec(0, 26), text: "Too steep", color: .gray))
            buzz(0.3)
            return
        }
        tank.inventory.fuel -= abs(nextX - tank.position.x)
        tank.treadTravel += nextX - tank.position.x
        tank.position.x = nextX
        tank.position.y = max(tank.position.y, ahead)
        tanks[currentIndex] = tank
        if Double.random(in: 0...1) < dt * 25 {
            particles.append(Particle(kind: .debris, position: Vec(tank.position.x - direction * 12, ahead + 1),
                                      velocity: Vec(-direction * Double.random(in: 10...30), Double.random(in: 8...25)),
                                      lifetime: 0.5, size: 1.4, color: Color(red: 0.45, green: 0.33, blue: 0.2)))
        }
        driveTickDistance += step
        if driveTickDistance >= 12, settings.hapticsEnabled {
            driveTickDistance = 0
            detents.selectionChanged()
        }
        if tank.inventory.fuel <= 0 { stopDriving() }
    }

    func beginCharge() {
        guard phase == .aiming, chargeStartedAt == nil else { return }
        stopDriving()
        chargeStartedAt = .now
        chargePower = 0
        if settings.hapticsEnabled, !isComputerTurn { rumble.start() }
        startLoop()
    }

    func releaseCharge(cappedAt cap: Double = 100) {
        guard let start = chargeStartedAt else { return }
        let power = min((ContinuousClock.now - start).seconds * Game.chargeRate, cap, 100).rounded()
        chargeStartedAt = nil
        chargePower = nil
        rumble.stop()
        tanks[currentIndex].power = power
        fire()
    }

    private func fire() {
        guard phase == .aiming else { return }
        var tank = current
        let weapon = tank.selectedWeapon
        if let count = tank.ammoCount(weapon) {
            guard count > 0 else { return }
            tank.inventory.ammo[weapon] = count - 1
            if count == 1 { tank.selectedWeapon = .babyMissile }
        }
        tanks[currentIndex] = tank

        let seed = UInt64.random(in: 1...UInt64.max)
        lastShot = ShotSnapshot(terrain: terrain, tanks: tanks, wind: wind, shooterIndex: currentIndex, weapon: weapon,
                                seed: seed, roundEarnings: roundEarnings, players: players)
        victimsThisShot = []
        phase = .firing
        launch(weapon, from: tank, seed: seed)
        startLoop()
    }

    /// Sends the shot on its way. Shared by real shots and kill cam replays.
    private func launch(_ weapon: Weapon, from tank: Tank, seed: UInt64) {
        let direction = tank.barrelDirection
        particles += ParticleFactory.muzzle(at: tank.muzzle, direction: direction)
        buzz(0.5)
        shake = max(shake, 0.15)
        accumulator = 0
        rng = SeededRandom(seed: seed)

        if case .riot = weapon.behavior {
            // Centered close to the barrel so a buried tank can blast its way out.
            let center = tank.muzzle + direction * 6
            terrain.carve(center: center, radius: weapon.blastRadius, leavesScorch: false)
            particles += ParticleFactory.dirt(at: center, radius: weapon.blastRadius)
            sound.dirt(atX: center.x)
            shake = max(shake, 0.3)
        } else if case .laser = weapon.behavior {
            fireLaser(weapon, from: tank, direction: direction)
        } else {
            var shell = Projectile(position: tank.muzzle, velocity: direction * launchSpeed(forPower: tank.power), weapon: weapon, ownerID: tank.id)
            if case let .bounce(times) = weapon.behavior { shell.bouncesLeft = times }
            projectiles = [shell]
            sound.launch(atX: tank.position.x)
        }
    }

    /// The beam travels instantly in a straight line, burning a thin tunnel and hitting every tank in its path.
    private func fireLaser(_ weapon: Weapon, from tank: Tank, direction: Vec) {
        var point = tank.muzzle
        var path = [point]
        var struck = Set<Int>()
        var travelled = 0.0
        while travelled < 1_400, point.x >= 0, point.x <= Game.worldSize.x, point.y >= 0, point.y <= Game.worldSize.y * 2 {
            point += direction * 2
            travelled += 2
            if Int(travelled) % 6 == 0, point.y <= terrain.height(at: point.x) + weapon.blastRadius {
                terrain.carve(center: point, radius: weapon.blastRadius, leavesScorch: false)
                terrain.burnGrass(around: point.x, radius: 3)
            }
            for i in tanks.indices where tanks[i].isAlive && tanks[i].id != tank.id && !struck.contains(tanks[i].id)
                && (tanks[i].turretCenter - point).length < Tank.hitRadius {
                struck.insert(tanks[i].id)
                lastImpact = point
                damage(tankAt: i, by: weapon.damage, attackerID: tank.id)
                rock(tanksNear: point, reach: 30, strength: 2)
                particles += ParticleFactory.plasma(at: point, radius: 12)
            }
        }
        path.append(point)
        beams.append(Beam(points: path))
        sound.laser(atX: tank.position.x)
        flash = max(flash, 0.25)
        shake = max(shake, 0.25)
    }

    // MARK: Kill cam

    private func startKillCam() -> Bool {
        guard let shot = lastShot, !victimsThisShot.isEmpty else { return false }
        finalOutcome = (roundEarnings, players)
        killCamVictimID = victimsThisShot.last
        terrain = shot.terrain
        tanks = shot.tanks
        wind = shot.wind
        currentIndex = shot.shooterIndex
        projectiles = []
        flames = []
        explosions = []
        particles = []
        floatingTexts = []
        smolders = []
        turrets = []
        pendingWrecks = []
        victimsThisShot = []
        killCamHold = 1.8
        killCamImpactTime = nil
        camera = .overview
        timeScale = 1
        phase = .killCam
        launch(shot.weapon, from: tanks[shot.shooterIndex], seed: shot.seed)
        return true
    }

    func skipKillCam() {
        guard phase == .killCam else { return }
        finishKillCam()
    }

    private func finishKillCam() {
        if let outcome = finalOutcome {
            roundEarnings = outcome.earnings
            players = outcome.players
        }
        finalOutcome = nil
        camera = nil
        timeScale = 1
        projectiles = []
        flames = []
        sound.updateFlights([])
        let alive = tanks.filter(\.isAlive)
        endRound(winnerID: alive.first?.id)
    }

    /// Follows the shell, slows to bullet time near the victim, then holds on the wreck.
    private func updateKillCam(_ dt: Double) {
        guard phase == .killCam, let victim = tanks.first(where: { $0.id == killCamVictimID }) else { return }
        var target = Camera(center: victim.turretCenter, zoom: 3.2)
        var speed = 0.4
        if let shell = projectiles.min(by: { ($0.position - victim.turretCenter).length < ($1.position - victim.turretCenter).length }) {
            // 1 when far from the victim, easing to 0 as the shell closes in.
            let distance = (shell.position - victim.turretCenter).length
            let t = min(max((distance - 40) / 360, 0), 1)
            let far = t * t * (3 - 2 * t)
            target = Camera(center: shell.position, zoom: 1.6 + 1.2 * (1 - far))
            speed = 0.1 + 0.9 * far
        } else if lastImpact != nil {
            killCamImpactTime = (killCamImpactTime ?? 0) + dt
            speed = (killCamImpactTime ?? 0) < 0.8 ? 0.2 : 0.6
        }
        timeScale += (speed - timeScale) * min(1, dt * 4)
        var view = camera ?? .overview
        let ease = min(1, dt * 3.5)
        view.center += (target.center - view.center) * ease
        view.zoom += (target.zoom - view.zoom) * ease
        let halfWidth = Game.worldSize.x / (2 * view.zoom)
        view.center.x = min(max(view.center.x, halfWidth), Game.worldSize.x - halfWidth)
        camera = view
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
            let power = min((ContinuousClock.now - start).seconds * Game.chargeRate, 100)
            chargePower = power.rounded()
            rumble.update(fraction: power / 100)
        }

        updateKillCam(dt)
        if phase == .aiming {
            drive(dt)
            if driveDirection != nil || tanks.contains(where: { $0.fallDistance > 0 || $0.position.y > terrain.height(at: $0.position.x) + 0.5 }) {
                settleTanks(dt)
                blowUpWrecks()
                // Driving off a cliff to your death ends your turn.
                if !current.isAlive {
                    stopDriving()
                    phase = .firing
                }
            }
        }
        if phase == .firing || phase == .killCam {
            accumulator += dt * timeScale
            while accumulator >= Game.stepDuration {
                simulate(Game.stepDuration)
                updateFlames(Game.stepDuration)
                accumulator -= Game.stepDuration
            }
            sound.updateFlights(projectiles.filter(\.isFlying))
        }

        updateEffects(dt * timeScale)
        updateMusic()

        // A falling tank counts until its landing (and any fall damage) has been processed.
        let isSettling = tanks.contains { $0.fallDistance > 0 || $0.position.y > terrain.height(at: $0.position.x) + 0.5 }
        let isSettled = projectiles.isEmpty && flames.isEmpty && explosions.isEmpty && !isSettling
        if phase == .firing, isSettled {
            endTurn()
        } else if phase == .killCam, isSettled {
            killCamHold -= dt
            if killCamHold <= 0 { finishKillCam() }
        }

        let isSmoking = !smolders.isEmpty || tanks.contains { $0.health < 50 }
        let isMoving = tanks.contains(where: \.isRocking) || turrets.contains { !$0.isResting }
        let isAnimating = isSmoking || isMoving || phase == .killCam || !beams.isEmpty || !particles.isEmpty || !floatingTexts.isEmpty || !explosions.isEmpty || shake > 0.01 || flash > 0.01
        if !isAnimating && phase != .firing && chargeStartedAt == nil && driveDirection == nil {
            shake = 0
            flash = 0
            return false
        }
        return true
    }

    private func simulate(_ dt: Double) {
        var next: [Projectile] = []
        for var p in projectiles {
            p.age += dt
            if p.rollDirection != nil {
                next += roll(&p, dt)
            } else if p.burrowTimeLeft != nil {
                next += burrow(&p, dt)
            } else {
                next += fly(&p, dt)
            }
        }
        projectiles = next
        settleTanks(dt)
        blowUpWrecks()
    }

    private func fly(_ p: inout Projectile, _ dt: Double) -> [Projectile] {
        p.velocity += Vec(wind, -gravity) * dt
        p.position += p.velocity * dt
        p.smokeTimer += dt
        if p.smokeTimer >= 0.035, p.weapon != .tracer {
            p.smokeTimer = 0
            particles.append(ParticleFactory.shellSmoke(at: p.position))
        }
        if p.trail.last.map({ ($0 - p.position).length > 5 }) ?? true {
            p.trail.append(p.position)
            if p.trail.count > Projectile.maxTrail, p.weapon != .tracer { p.trail.removeFirst() }
        }

        if case let .splitAtApex(count, child) = p.weapon.behavior, p.velocity.y <= 0 {
            particles += (0..<12).map { _ in
                Particle(kind: .spark, position: p.position, velocity: Vec(Double.random(in: -80...80), Double.random(in: -80...80)), lifetime: 0.3, size: 1.8, color: .cyan)
            }
            return (0..<count).map { i in
                let spread = (Double(i) - Double(count - 1) / 2) * 22
                return Projectile(position: p.position, velocity: Vec(p.velocity.x + spread, p.velocity.y), weapon: child, ownerID: p.ownerID, age: p.age, trail: [p.position])
            }
        }

        guard p.position.x >= 0, p.position.x <= Game.worldSize.x else { return [] }

        let hit = tankHit(by: p, reach: Tank.hitRadius)
        let ground = terrain.height(at: p.position.x)
        guard hit != nil || p.position.y <= ground else { return [p] }
        return impact(p, at: Vec(p.position.x, max(p.position.y, ground)), directHitID: hit)
    }

    private func roll(_ p: inout Projectile, _ dt: Double) -> [Projectile] {
        guard let direction = p.rollDirection else { return [] }
        p.rollTime += dt
        let here = terrain.height(at: p.position.x)
        let nextX = p.position.x + direction * 85 * dt
        let ahead = terrain.height(at: nextX)
        let hit = tankHit(by: p, reach: Tank.hitRadius + 2)
        if hit != nil || nextX < 0 || nextX > Game.worldSize.x || ahead > here + 0.6 || p.rollTime > 5 {
            explode(p.weapon, at: Vec(p.position.x, here + 2), ownerID: p.ownerID, directHitID: hit)
            return []
        }
        p.position = Vec(nextX, ahead + 2.5)
        p.velocity = Vec(direction * 85, 0)
        if Double.random(in: 0...1) < dt * 20 {
            particles.append(Particle(kind: .debris, position: Vec(p.position.x, ahead + 0.5), velocity: Vec(-direction * 20, Double.random(in: 10...30)),
                                      lifetime: 0.4, size: 1.2, color: Color(red: 0.4, green: 0.28, blue: 0.15)))
        }
        return [p]
    }

    private func burrow(_ p: inout Projectile, _ dt: Double) -> [Projectile] {
        guard let timeLeft = p.burrowTimeLeft else { return [] }
        p.burrowTimeLeft = timeLeft - dt
        p.position += p.velocity * dt
        p.burrowDistance += p.velocity.length * dt
        if p.burrowDistance >= 5 {
            p.burrowDistance = 0
            terrain.carve(center: p.position, radius: 7, leavesScorch: false)
            undermine(around: p.position.x, radius: 14, ownerID: p.ownerID)
        }
        let hit = tankHit(by: p, reach: Tank.hitRadius + 4)
        if hit != nil || timeLeft <= 0 || p.position.x < 0 || p.position.x > Game.worldSize.x || p.position.y < 4 {
            explode(p.weapon, at: p.position, ownerID: p.ownerID, directHitID: hit)
            return []
        }
        return [p]
    }

    private func tankHit(by p: Projectile, reach: Double) -> Int? {
        tanks.first { tank in
            tank.isAlive && (tank.id != p.ownerID || p.age > 0.3) && (tank.turretCenter - p.position).length < reach
        }?.id
    }

    /// What happens when a flying shell meets the ground or a tank.
    private func impact(_ p: Projectile, at center: Vec, directHitID: Int?) -> [Projectile] {
        let weapon = p.weapon
        switch weapon.behavior {
        case .dirt:
            terrain.addDirt(center: center, radius: weapon.blastRadius)
            explosions.append(Explosion(center: center, radius: weapon.blastRadius, style: .dirt))
            particles += ParticleFactory.dirt(at: center, radius: weapon.blastRadius)
            sound.dirt(atX: center.x)
            shake = max(shake, 0.25)
            return []

        case let .scatterOnImpact(count, child):
            explode(weapon, at: center, ownerID: p.ownerID, directHitID: directHitID)
            return (0..<count).map { _ in
                let angle = Double.random(in: 0.25...(.pi - 0.25), using: &rng)
                let speed = Double.random(in: 120...260, using: &rng)
                return Projectile(position: center + Vec(0, 3), velocity: Vec(cos(angle), sin(angle)) * speed, weapon: child, ownerID: p.ownerID, age: 1)
            }

        case .roll:
            guard directHitID == nil else {
                explode(weapon, at: center, ownerID: p.ownerID, directHitID: directHitID)
                return []
            }
            let left = terrain.height(at: center.x - 4), right = terrain.height(at: center.x + 4)
            var rolling = p
            rolling.rollDirection = left == right ? (p.velocity.x < 0 ? -1 : 1) : (left < right ? -1 : 1)
            rolling.position = Vec(center.x, terrain.height(at: center.x) + 2.5)
            sound.dirt(atX: center.x)
            return [rolling]

        case .burrow:
            guard directHitID == nil else {
                explode(weapon, at: center, ownerID: p.ownerID, directHitID: directHitID)
                return []
            }
            var digger = p
            let heading = p.velocity / p.velocity.length
            let dig = Vec(heading.x, min(max(heading.y, -0.5), -0.2))
            digger.velocity = dig / dig.length * 150
            digger.burrowTimeLeft = 0.5
            terrain.carve(center: center, radius: 8, leavesScorch: false)
            particles += ParticleFactory.dirt(at: center, radius: 20)
            sound.dirt(atX: center.x)
            return [digger]

        case let .napalm(count, burnTime):
            flames += (0..<count).map { i in
                Flame(x: center.x + (Double(i) - Double(count - 1) / 2) * 4.5 + Double.random(in: -1.5...1.5, using: &rng),
                      life: Double.random(in: burnTime, using: &rng), ownerID: p.ownerID)
            }
            explosions.append(Explosion(center: center, radius: 18, style: .fire))
            particles += ParticleFactory.explosion(at: center, radius: 14)
            sound.explosion(atX: center.x, radius: 20)
            return []

        case .bounce:
            explode(weapon, at: center, ownerID: p.ownerID, directHitID: directHitID)
            guard p.bouncesLeft > 0 else { return [] }
            var hop = Projectile(position: center + Vec(0, 4), velocity: Vec(p.velocity.x * 0.8, abs(p.velocity.y) * 0.6 + 60), weapon: weapon, ownerID: p.ownerID, age: 1)
            hop.bouncesLeft = p.bouncesLeft - 1
            return [hop]

        case .tracer:
            tracers[p.ownerID] = p.trail + [center]
            return []

        case let .liquidDirt(volume):
            terrain.pourLiquid(at: center.x, volume: volume)
            explosions.append(Explosion(center: center, radius: 22, style: .dirt))
            particles += ParticleFactory.dirt(at: center, radius: 24)
            sound.dirt(atX: center.x)
            return []

        case .plasma:
            explode(weapon, at: center, ownerID: p.ownerID, directHitID: directHitID, style: .plasma)
            return []

        case .explode, .splitAtApex, .riot, .laser:
            explode(weapon, at: center, ownerID: p.ownerID, directHitID: directHitID)
            return []
        }
    }

    private func explode(_ weapon: Weapon, at center: Vec, ownerID: Int, directHitID: Int?, style: Explosion.Style = .fire) {
        let radius = weapon.blastRadius
        lastImpact = center
        terrain.carve(center: center, radius: radius, leavesScorch: style == .fire)
        blastEffects(at: center, radius: radius, style: style)
        undermine(around: center.x, radius: radius * 1.5, ownerID: ownerID)

        let reach = radius + Tank.hitRadius
        rock(tanksNear: center, reach: reach * 2, strength: weapon.damage / 60 + radius / 40)
        for i in tanks.indices where tanks[i].isAlive {
            let distance = tanks[i].id == directHitID ? 0 : (tanks[i].turretCenter - center).length
            guard distance < reach else { continue }
            let falloff = distance / reach
            damage(tankAt: i, by: weapon.damage * (1 - falloff * falloff), attackerID: ownerID)
        }
    }

    /// Knocks nearby tanks into a rock and a hop, away from the blast.
    private func rock(tanksNear center: Vec, reach: Double, strength: Double) {
        for i in tanks.indices {
            let offset = tanks[i].turretCenter - center
            let distance = offset.length
            guard distance < reach else { continue }
            let push = (1 - distance / reach) * strength
            let side: Double = offset.x == 0 ? 1 : (offset.x > 0 ? 1 : -1)
            tanks[i].tiltVelocity -= side * push * 5
            tanks[i].hopVelocity += push * 70
        }
    }

    private func blastEffects(at center: Vec, radius: Double, style: Explosion.Style = .fire) {
        explosions.append(Explosion(center: center, radius: radius, style: style))
        particles += style == .plasma ? ParticleFactory.plasma(at: center, radius: radius) : ParticleFactory.explosion(at: center, radius: radius)
        sound.explosion(atX: center.x, radius: radius)
        buzz(min(1, 0.4 + radius / 80))
        shake = min(1, max(shake, radius / 70))
        if radius >= 50 { flash = max(flash, min(1, radius / 100)) }
        guard style == .fire else { return }
        let smolderTime = 4 + radius / 25
        smolders.append(Smolder(x: center.x, spread: radius * 0.4, duration: smolderTime, remaining: smolderTime))
    }

    /// Credits anyone who knocks the ground out from under a tank for its fall.
    private func undermine(around x: Double, radius: Double, ownerID: Int) {
        for i in tanks.indices where tanks[i].id != ownerID && abs(tanks[i].position.x - x) < radius {
            tanks[i].lastAttackerID = ownerID
        }
    }

    private func damage(tankAt index: Int, by amount: Double, attackerID: Int?, bypassesShield: Bool = false, showsText: Bool = true) {
        guard tanks[index].isAlive else { return }
        var remaining = amount
        if !bypassesShield, tanks[index].shield > 0 {
            let absorbed = min(tanks[index].shield, remaining)
            tanks[index].shield -= absorbed
            remaining -= absorbed
            if showsText, absorbed >= 1, remaining < 1 {
                floatingTexts.append(FloatingText(position: tanks[index].turretCenter + Vec(0, 26), text: "Blocked", color: .cyan))
            }
        }
        let applied = min(remaining, tanks[index].health)
        guard applied > 0 else { return }
        tanks[index].health -= applied
        if tanks[index].health < 0.5 { tanks[index].health = 0 }

        let victimID = tanks[index].id
        if let attackerID, attackerID != victimID {
            roundEarnings[attackerID, default: RoundEarnings()].damage += Int((applied * Double(Economy.perDamagePoint)).rounded())
            tanks[index].lastAttackerID = attackerID
        }
        if showsText, applied >= 1 {
            floatingTexts.append(FloatingText(position: tanks[index].turretCenter + Vec(0, 26), text: "-\(Int(applied.rounded()))", color: tanks[index].color))
        }

        if !tanks[index].isAlive {
            if let killerID = attackerID ?? tanks[index].lastAttackerID, killerID != victimID {
                roundEarnings[killerID, default: RoundEarnings()].kills += Economy.perKill
                if let k = players.firstIndex(where: { $0.id == killerID }) { players[k].kills += 1 }
            }
            pendingWrecks.append(index)
            if phase == .firing { victimsThisShot.append(victimID) }
        }
    }

    /// A destroyed tank cooks off in a small blast of its own.
    private func blowUpWrecks() {
        let wrecks = pendingWrecks
        pendingWrecks = []
        for index in wrecks {
            let center = tanks[index].turretCenter
            terrain.carve(center: center, radius: 14)
            blastEffects(at: center, radius: 24)
            tanks[index].hasTurret = false
            tanks[index].hopVelocity += 90
            tanks[index].tiltVelocity += Double.random(in: -6...6)
            turrets.append(FlyingTurret(
                position: center, velocity: Vec(Double.random(in: -70...70), Double.random(in: 170...240)),
                angle: tanks[index].angle * .pi / 180, spin: Double.random(in: -12...12), color: tanks[index].color
            ))
        }
    }

    private func settleTanks(_ dt: Double) {
        for i in tanks.indices {
            let ground = terrain.height(at: tanks[i].position.x)
            if tanks[i].position.y > ground + 0.5 {
                if !tanks[i].isParachuting, tanks[i].isAlive, tanks[i].fallDistance > 10, tanks[i].inventory.parachutes > 0 {
                    tanks[i].isParachuting = true
                    tanks[i].inventory.parachutes -= 1
                }
                let speed = tanks[i].isParachuting ? Game.parachuteSpeed : Game.fallSpeed
                let drop = min(speed * dt, tanks[i].position.y - ground)
                tanks[i].position.y -= drop
                tanks[i].fallDistance += drop
            } else {
                // Dirt piled on top buries a tank rather than lifting it.
                if tanks[i].position.y > ground - 0.5 { tanks[i].position.y = ground }
                if tanks[i].fallDistance > 0 {
                    if !tanks[i].isParachuting {
                        damage(tankAt: i, by: max(0, tanks[i].fallDistance - Game.safeFallHeight) * Game.fallDamagePerUnit, attackerID: tanks[i].lastAttackerID, bypassesShield: true)
                    }
                    tanks[i].fallDistance = 0
                    tanks[i].isParachuting = false
                }
            }
        }
    }

    private func updateFlames(_ dt: Double) {
        guard !flames.isEmpty || !burnDamage.isEmpty else { return }
        for i in flames.indices {
            flames[i].life -= dt
            let x = flames[i].x
            let here = terrain.height(at: x)
            let left = terrain.height(at: x - 2), right = terrain.height(at: x + 2)
            if min(left, right) < here - 0.3 {
                flames[i].x = min(max(x + (left < right ? -1 : 1) * 28 * dt, 0), Game.worldSize.x)
            }
            terrain.burnGrass(around: flames[i].x, radius: 5)
            flames[i].emitTimer += dt
            if flames[i].emitTimer >= 0.05 {
                flames[i].emitTimer = 0
                let base = Vec(flames[i].x + Double.random(in: -2...2), terrain.height(at: flames[i].x) + 1)
                particles.append(Particle(kind: .fire, position: base, velocity: Vec(wind * 0.2 + Double.random(in: -4...4), Double.random(in: 15...35)),
                                          lifetime: Double.random(in: 0.4...0.8), size: Double.random(in: 4...8), color: .orange))
                if Double.random(in: 0...1) < 0.2 {
                    particles.append(Particle(kind: .smoke, position: base + Vec(0, 6), velocity: Vec(wind * 0.2, Double.random(in: 12...22)),
                                              lifetime: Double.random(in: 1.2...2), size: Double.random(in: 3...5), color: Color(white: 0.2)))
                }
            }
        }

        for i in tanks.indices where tanks[i].isAlive {
            let tank = tanks[i]
            let nearby = flames.filter { abs($0.x - tank.position.x) < 12 && tank.position.y - terrain.height(at: $0.x) < 10 }
            guard let ownerID = nearby.first?.ownerID else { continue }
            let amount = (6 + 3 * Double(min(nearby.count, 6))) * dt
            let before = tanks[i].health
            damage(tankAt: i, by: amount, attackerID: ownerID, showsText: false)
            burnDamage[tank.id, default: 0] += before - tanks[i].health
        }
        flames.removeAll { $0.life <= 0 }

        burnTextTimer += dt
        if burnTextTimer >= 0.5 || flames.isEmpty {
            burnTextTimer = 0
            for (id, amount) in burnDamage where amount >= 1 {
                if let tank = tanks.first(where: { $0.id == id }) {
                    floatingTexts.append(FloatingText(position: tank.turretCenter + Vec(0, 26), text: "-\(Int(amount.rounded()))", color: .orange))
                }
            }
            burnDamage = [:]
        }
    }

    private func updateEffects(_ dt: Double) {
        for i in explosions.indices { explosions[i].age += dt }
        explosions.removeAll { $0.age >= Explosion.duration }

        for i in beams.indices { beams[i].age += dt }
        beams.removeAll { $0.age >= Beam.lifetime }

        for i in floatingTexts.indices { floatingTexts[i].age += dt }
        floatingTexts.removeAll { $0.age >= FloatingText.lifetime }

        for i in particles.indices {
            var p = particles[i]
            p.age += dt
            switch p.kind {
            case .spark:
                p.velocity *= 1 - 2.5 * dt
                p.velocity.y -= gravity * 0.3 * dt
            case .debris:
                p.velocity.y -= gravity * dt
                p.velocity.x += wind * dt
            case .smoke:
                p.velocity.x += wind * 0.5 * dt
            case .fire:
                p.velocity *= 1 - 1.8 * dt
                p.velocity.y += 25 * dt
                p.velocity.x += wind * 0.3 * dt
            }
            p.position += p.velocity * dt
            if p.kind == .debris, p.position.y < terrain.height(at: p.position.x) { p.age = p.lifetime }
            particles[i] = p
        }
        particles.removeAll { $0.age >= $0.lifetime }
        if particles.count > 900 { particles.removeFirst(particles.count - 900) }

        emitLingeringSmoke(dt)
        updateTankMotion(dt)

        shake *= exp(-5 * dt)
        flash *= exp(-6 * dt)
    }

    private func updateTankMotion(_ dt: Double) {
        for i in tanks.indices where tanks[i].isRocking {
            let springForce = -55 * tanks[i].tilt - 6 * tanks[i].tiltVelocity
            tanks[i].tiltVelocity += springForce * dt
            tanks[i].tilt = min(max(tanks[i].tilt + tanks[i].tiltVelocity * dt, -1.1), 1.1)
            tanks[i].hopVelocity -= gravity * dt
            tanks[i].hop += tanks[i].hopVelocity * dt
            if tanks[i].hop <= 0 {
                tanks[i].hop = 0
                tanks[i].hopVelocity = tanks[i].hopVelocity < -30 ? -tanks[i].hopVelocity * 0.3 : 0
            }
        }
        for i in turrets.indices where !turrets[i].isResting {
            turrets[i].velocity.y -= gravity * dt
            turrets[i].position += turrets[i].velocity * dt
            turrets[i].angle += turrets[i].spin * dt
            let ground = terrain.height(at: turrets[i].position.x) + 2
            if turrets[i].position.y <= ground {
                turrets[i].position.y = ground
                turrets[i].velocity = Vec(turrets[i].velocity.x * 0.55, -turrets[i].velocity.y * 0.35)
                turrets[i].spin *= 0.5
                if turrets[i].velocity.length < 18 { turrets[i].isResting = true }
            }
        }
    }

    private func emitLingeringSmoke(_ dt: Double) {
        for i in smolders.indices {
            smolders[i].remaining -= dt
            smolders[i].timer += dt
            let intensity = smolders[i].intensity
            guard smolders[i].timer >= 0.08 / max(intensity, 0.15) else { continue }
            smolders[i].timer = 0
            let x = smolders[i].x + Double.random(in: -smolders[i].spread...smolders[i].spread)
            let ground = Vec(x, terrain.height(at: x) + 1)
            particles.append(Particle(
                kind: .smoke,
                position: ground,
                velocity: Vec(wind * 0.15 + Double.random(in: -3...3), Double.random(in: 10...20)),
                lifetime: Double.random(in: 2...3.2),
                size: Double.random(in: 2.5...5) * (0.5 + intensity * 0.5),
                color: Color(white: 0.45)
            ))
            if intensity > 0.7, Double.random(in: 0...1) < 0.25 {
                particles.append(Particle(kind: .spark, position: ground, velocity: Vec(Double.random(in: -15...15), Double.random(in: 20...50)),
                                          lifetime: Double.random(in: 0.4...0.8), size: 1, color: .orange))
            }
        }
        smolders.removeAll { $0.remaining <= 0 }

        for tank in tanks where tank.health < 50 {
            let interval = !tank.isAlive ? 0.08 : tank.health < 25 ? 0.14 : 0.35
            tankSmokeTimers[tank.id, default: 0] += dt
            guard tankSmokeTimers[tank.id, default: 0] >= interval else { continue }
            tankSmokeTimers[tank.id] = 0
            particles.append(Particle(
                kind: .smoke,
                position: tank.turretCenter + Vec(Double.random(in: -4...4), 3),
                velocity: Vec(wind * 0.2 + Double.random(in: -3...3), Double.random(in: 12...22)),
                lifetime: Double.random(in: 1.6...2.6),
                size: Double.random(in: 2...4) * (tank.isAlive ? 1 : 1.5),
                color: Color(white: tank.isAlive ? 0.35 : 0.18)
            ))
        }
    }

    private func endTurn() {
        sound.updateFlights([])
        let alive = tanks.filter(\.isAlive)
        if alive.count <= 1 {
            if !startKillCam() { endRound(winnerID: alive.first?.id) }
            return
        }
        repeat {
            currentIndex = (currentIndex + 1) % tanks.count
        } while !tanks[currentIndex].isAlive
        wind = randomWind()
        phase = .aiming
        scheduleComputerTurn()
    }

    private func randomWind() -> Double {
        maxWind > 0 ? Double.random(in: -maxWind...maxWind).rounded() : 0
    }
}

#if DEBUG
/// Hooks for unit tests: set up exact situations and run the simulation to completion without the real-time loop.
extension Game {
    func installScenario(terrain: Terrain, tankXs: [Double], wind: Double = 0, currentIndex: Int = 0) {
        loop?.cancel()
        loop = nil
        computerTask?.cancel()
        computerTask = nil
        self.terrain = terrain
        for (i, x) in tankXs.enumerated() where tanks.indices.contains(i) {
            tanks[i].position = Vec(x, terrain.height(at: x))
            tanks[i].health = 100
            tanks[i].shield = 0
            tanks[i].fallDistance = 0
        }
        self.wind = wind
        self.currentIndex = currentIndex
        projectiles = []
        flames = []
        explosions = []
        lastImpact = nil
        phase = .aiming
    }

    /// Swaps in new ground without moving the tanks, burying any that end up under it.
    func bury(tank index: Int, under terrain: Terrain) {
        self.terrain = terrain
    }

    func setFuel(_ fuel: Double, ofTank index: Int) {
        tanks[index].inventory.fuel = fuel
    }

    func setCurrentTank(_ index: Int) {
        currentIndex = index
    }

    func setHealth(_ health: Double, ofTank index: Int) {
        tanks[index].health = health
    }

    func give(_ item: ShopItem, quantity: Int, toTank index: Int) {
        tanks[index].inventory.add(item, quantity: quantity)
    }

    func lift(tank index: Int, by height: Double) {
        tanks[index].position.y += height
        phase = .firing
    }

    func fireForTesting(weapon: Weapon, angle: Double, power: Double) {
        if weapon != .babyMissile, current.ammoCount(weapon) == 0 { give(.weapon(weapon), quantity: 1, toTank: currentIndex) }
        select(weapon)
        setAngle(angle)
        tanks[currentIndex].power = power
        fire()
        loop?.cancel()
        loop = nil
    }

    func stepForTesting() {
        loop?.cancel()
        loop = nil
        _ = advance(by: 1.0 / 60)
    }

    /// Steps the game in 60 Hz frames until the shot and everything it set off has settled.
    func runUntilSettled(maxSeconds: Double = 60) {
        loop?.cancel()
        loop = nil
        var elapsed = 0.0
        while phase == .firing || phase == .killCam, elapsed < maxSeconds {
            _ = advance(by: 1.0 / 60)
            elapsed += 1.0 / 60
        }
        loop?.cancel()
        loop = nil
    }
}
#endif
