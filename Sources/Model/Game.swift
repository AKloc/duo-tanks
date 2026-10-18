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

enum TankKind: Equatable {
    case standard
    /// A boss bunker: big, armored, and bolted to the ground.
    case bastion
    /// A gun pod riding a boss through the air.
    case pod
    /// Cinder's boss: a lava worm that burrows and resurfaces each turn.
    case crawler
    /// Glacia's boss: a plow tank that drives at you, rams, and is armored in front.
    case icebreaker
    /// The Rift's boss: a flying saucer with a tractor beam.
    case mothership
}

struct Tank: Identifiable {
    static let bodyHeight = 7.0
    static let standardRadius = 12.0
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
    var kind = TankKind.standard
    var maxHealth = 100.0
    var radius = Tank.standardRadius
    /// Tanks on the same team don't count as enemies; `nil` means a team of one.
    var team: Int?
    /// Shield points restored at the start of each of this tank's turns.
    var shieldRegen = 0.0
    var shieldCap = Tank.maxShield
    /// Sideways speed while sliding on ice.
    var slide = 0.0

    var side: Int { team ?? id }
    /// Bosses don't fall, slide or get buried.
    var isAnchored: Bool { kind != .standard }
    var healthFraction: Double { health / maxHealth }

    /// How deep under the dirt this tank sits; 0 when it's on the surface.
    func buriedDepth(in terrain: Terrain) -> Double {
        guard !isAnchored else { return 0 }
        return max(0, terrain.support(at: position.x, y: position.y) - position.y)
    }

    func isBuried(in terrain: Terrain) -> Bool {
        buriedDepth(in: terrain) > Tank.buriedThreshold
    }

    var isRocking: Bool { abs(tilt) > 0.002 || abs(tiltVelocity) > 0.01 || hop > 0.01 || hopVelocity > 0.01 }

    var isAlive: Bool { health > 0 }
    var turretCenter: Vec {
        switch kind {
        case .standard: position + Vec(0, Tank.bodyHeight)
        case .bastion: position + Vec(0, 18)
        case .crawler: position + Vec(0, 16)
        case .icebreaker: position + Vec(0, 12)
        case .pod, .mothership: position
        }
    }
    var barrelLength: Double {
        switch kind {
        case .bastion, .icebreaker: 26
        case .crawler, .mothership: 22
        default: Tank.barrelLength
        }
    }
    var muzzle: Vec { turretCenter + barrelDirection * barrelLength }
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
    /// Set while a Burrower is tunneling: seconds left underground.
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
    let y: Double
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

/// Islands easing to their next positions between turns, carrying any tanks on them.
private struct IslandDrift {
    var from: [Int: Vec] = [:]
    var to: [Int: Vec] = [:]
    var riders: [Int: Int] = [:]
    var creatureFrom: Vec?
    var creatureTo: Vec?
    /// Tanks driven along the ground: tank index to start and end.
    var movers: [Int: (from: Vec, to: Vec)] = [:]
    var ramTarget: (attacker: Int, target: Int)?
    var elapsed = 0.0
}

/// Burning napalm fuel that runs downhill.
struct Flame: Identifiable {
    let id = UUID()
    var x: Double
    var y: Double
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
    case missionOver(won: Bool, stars: Int)
}

/// A Tour mission in progress.
struct MissionRun {
    let mission: Mission
    let difficulty: TourDifficulty
    let windRange: ClosedRange<Double>
    var shots = 0
    var damageTaken = 0.0
    var enemyTurns = 0
    var hintShown = false

    var shotsUnderPar: Int { mission.par + difficulty.parAllowance }
}

struct TractorBeam {
    static let duration = 1.4

    let sourceIndex: Int
    let targetIndex: Int
    var age = 0.0
}

/// A flying boss's path: the Sky Leviathan with its pods, or the Mothership.
struct LeviathanFlight {
    let home: Vec
    var phase = 0.0
    var center: Vec
    /// Tank index of each pod and where it rides relative to the center.
    var pods: [(index: Int, offset: Vec)]
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
    /// Health lost by falling into the clouds below the islands.
    nonisolated static let abyssDamage = 50.0
    nonisolated static let lavaDamagePerSecond = 30.0
    /// How high the Mothership's tractor beam lifts a tank before letting go.
    nonisolated static let abductionHeight = 60.0
    /// How long islands take to drift into place between turns.
    nonisolated static let islandDriftDuration = 1.4
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
    private(set) var mission: MissionRun?
    private(set) var leviathan: LeviathanFlight?
    private(set) var tractorBeam: TractorBeam?

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
    @ObservationIgnored private var islandDrift: IslandDrift?
    @ObservationIgnored private var gustTimer = 0.0
    @ObservationIgnored private var mothershipTurns = 0
    @ObservationIgnored private var turnNumber = 0
    @ObservationIgnored private var lavaTextTimer = 0.0
    @ObservationIgnored private var lavaDamage: [Int: Double] = [:]

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

    convenience init(mission: Mission, difficulty: TourDifficulty, settings base: MatchSettings = MatchSettings()) {
        var settings = base
        settings.rounds = 1
        settings.world = WorldChoice(rawValue: mission.chapter.theme.rawValue) ?? .hills
        settings.computerOpponent = nil
        self.init(settings: settings)
        startMission(mission, difficulty: difficulty)
    }

    // MARK: Tour missions

    var aimPreviewFraction: Double {
        guard let mission, phase == .aiming, !isComputerTurn, current.id == 0 else { return 0 }
        return mission.difficulty.aimPreview
    }

    var canShowHint: Bool {
        guard let mission, !mission.hintShown, phase == .aiming, current.id == 0,
              let threshold = mission.difficulty.hintAfterFailures else { return false }
        return TourProgress.shared.failures(for: mission.mission) >= threshold
    }

    func restartMission() {
        guard let mission else { return }
        startMission(mission.mission, difficulty: mission.difficulty)
    }

    private func startMission(_ mission: Mission, difficulty: TourDifficulty) {
        let setup = MissionSetup.make(mission, difficulty: difficulty)
        self.mission = MissionRun(mission: mission, difficulty: difficulty, windRange: setup.wind)
        theme = mission.chapter.theme
        weather = setup.weather
        gravity = Game.standardGravity * theme.gravityScale
        terrain = setup.terrain
        round = 1

        var you = Player(id: 0, name: "You", color: .red, money: 0)
        you.inventory = setup.playerInventory
        players = [you] + setup.enemies.enumerated().map { index, enemy in
            var player = Player(id: index + 1, name: enemy.name, color: enemy.color, money: 0,
                                computer: enemy.isDummy ? nil : difficulty.enemyAim.capped(at: enemy.aimCap))
            player.isDummy = enemy.isDummy
            player.inventory = enemy.inventory
            return player
        }

        let start = terrain.spawnPoint(near: setup.playerX)
        terrain.flatten(around: start.x, halfWidth: 14, y: start.y)
        var player = Tank(id: 0, name: you.name, color: you.color, position: Vec(start.x, terrain.support(at: start.x, y: start.y + 1)),
                          angle: 60, inventory: setup.playerInventory)
        player.team = 0
        if player.ammoCount(.babyMissile) == 0, let first = Weapon.arsenal.first(where: { (player.ammoCount($0) ?? 1) > 0 }) {
            player.selectedWeapon = first
        }
        tanks = [player]
        for (index, enemy) in setup.enemies.enumerated() {
            let position: Vec
            if let fixed = enemy.position {
                position = fixed
            } else {
                let spawn = terrain.spawnPoint(near: enemy.x)
                terrain.flatten(around: spawn.x, halfWidth: enemy.kind == .bastion ? 30 : 14, y: spawn.y)
                position = Vec(spawn.x, terrain.support(at: spawn.x, y: spawn.y + 1))
            }
            var tank = Tank(id: index + 1, name: enemy.name, color: enemy.color, position: position,
                            angle: position.x > start.x ? 120 : 60, inventory: enemy.inventory)
            tank.team = 1
            tank.kind = enemy.kind
            tank.radius = enemy.radius
            tank.maxHealth = enemy.health
            tank.health = enemy.health
            tank.shield = enemy.shield
            tank.shieldRegen = enemy.shieldRegen
            tank.shieldCap = enemy.shieldCap
            tanks.append(tank)
        }
        leviathan = setup.leviathanHome.map { home in
            LeviathanFlight(home: home, center: home,
                            pods: tanks.indices.filter { [.pod, .mothership].contains(tanks[$0].kind) }.map { ($0, tanks[$0].position - home) })
        }
        roundEarnings = Dictionary(uniqueKeysWithValues: players.map { ($0.id, RoundEarnings()) })
        resetBattlefield()
        currentIndex = 0
        wind = randomWind()
        phase = .aiming
        sound.updateFlights([])
        updateMusic()
    }

    /// Clears everything left over from the last round.
    private func resetBattlefield() {
        loop?.cancel()
        loop = nil
        computerTask?.cancel()
        computerTask = nil
        computerStatus = nil
        islandDrift = nil
        tractorBeam = nil
        mothershipTurns = 0
        turnNumber = 0
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
    }

    /// Points the barrel at a shot that should work and leaves its path on screen.
    func showHint() {
        guard canShowHint, let target = tanks.filter({ $0.isAlive && $0.side != 0 }).first else { return }
        let ballistics = Ballistics(
            terrain: terrain, wind: wind, gravity: gravity, speedPerPower: launchSpeed(forPower: 1),
            origin: current.turretCenter, ownerID: current.id,
            tanks: tanks.filter(\.isAlive).map { .init(id: $0.id, center: $0.turretCenter, radius: $0.radius) }
        )
        guard let aim = ballistics.bestAim(at: target.turretCenter, safeRadius: 30) else { return }
        setAngle(aim.angle)
        tracers[current.id] = ballistics.trajectory(angle: aim.angle, power: aim.power)
        floatingTexts.append(FloatingText(position: current.turretCenter + Vec(0, 30), text: "Try \(Int(aim.power.rounded()))% power", color: .yellow))
        mission?.hintShown = true
        startLoop()
    }

    /// The path a shot would take from the current tank, for the aim guide.
    func previewPath(power: Double) -> [Vec] {
        Ballistics(terrain: terrain, wind: wind, gravity: gravity, speedPerPower: launchSpeed(forPower: 1),
                   origin: current.turretCenter, ownerID: current.id,
                   tanks: tanks.filter(\.isAlive).map { .init(id: $0.id, center: $0.turretCenter, radius: $0.radius) })
            .trajectory(angle: current.angle, power: power)
    }

    private func finishMission(won: Bool) {
        guard let run = mission else { return }
        var stars = 0
        if won {
            stars = 1
            if run.shots <= run.shotsUnderPar { stars += 1 }
            if run.damageTaken <= 25 { stars += 1 }
        }
        TourProgress.shared.record(run.mission, stars: stars)
        phase = .missionOver(won: won, stars: stars)
        if won { sound.playFanfare() }
        updateMusic()
    }

    /// Whose turn is skipped: dummies, and dead tanks.
    private func takesTurns(_ index: Int) -> Bool {
        tanks[index].isAlive && !(players.first { $0.id == tanks[index].id }?.isDummy ?? false)
    }

    /// When the Leviathan's firing pod is destroyed, another takes over.
    private func promoteGunnerPod() {
        guard let flight = leviathan, let difficulty = mission?.difficulty else { return }
        let alivePods = flight.pods.map(\.index).filter { tanks[$0].isAlive }
        guard !alivePods.contains(where: takesTurns), let next = alivePods.first,
              let p = players.firstIndex(where: { $0.id == tanks[next].id }) else { return }
        players[p].isDummy = false
        players[p].computer = difficulty.enemyAim
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
        case .roundOver, .matchOver, .missionOver: tension = 0.1
        case .shopping: tension = 0.05
        case .killCam:
            tension = 0.95
            level = 0.7
        case .aiming, .firing:
            let lowest = tanks.filter(\.isAlive).map(\.healthFraction).min() ?? 1
            tension = 0.15 + 0.45 * (1 - lowest)
            if round == settings.rounds { tension += 0.15 }
            if phase == .firing { tension += 0.15 }
            if chargePower != nil { tension += 0.1 }
        }
        let isDanger = (phase == .aiming || phase == .firing) && tanks.contains { $0.isAlive && $0.healthFraction * 100 <= Game.dangerHealth }
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
        mission = nil
        leviathan = nil
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
            let spawn = terrain.spawnPoint(near: Double.random(in: lanes[player.id % lanes.count]))
            terrain.flatten(around: spawn.x, halfWidth: 14, y: spawn.y)
            let x = spawn.x
            return Tank(
                id: player.id, name: player.name, color: player.color,
                position: Vec(x, terrain.support(at: x, y: spawn.y + 1)),
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
        if current.kind == .mothership {
            mothershipTurns += 1
            if mothershipTurns % 2 == 0 {
                computerTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(1))
                    guard let self, !Task.isCancelled else { return }
                    while self.isTerrainMoving { try? await Task.sleep(for: .milliseconds(50)) }
                    self.abduct()
                }
                return
            }
        }
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
        if mission != nil {
            finishMission(won: winnerID == 0)
            return
        }
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
        guard phase == .aiming, current.inventory.repairKits > 0, current.health < current.maxHealth else { return }
        let healed = min(35, current.maxHealth - current.health)
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
        let ahead = terrain.support(at: nextX, y: tank.position.y + step * 1.5 + 1)
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
            if count == 1 {
                tank.selectedWeapon = Weapon.arsenal.first { (tank.ammoCount($0) ?? 1) > 0 } ?? .babyMissile
            }
        }
        if mission != nil, tank.id == 0 { mission?.shots += 1 }
        tanks[currentIndex] = tank

        // Shots always fly over still terrain, so the kill cam can replay them exactly.
        updateIslandDrift(0, snap: true)
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
            if Int(travelled) % 6 == 0, terrain.isSolid(point) || terrain.isSolid(point - Vec(0, weapon.blastRadius)) {
                terrain.carve(center: point, radius: weapon.blastRadius, leavesScorch: false)
                terrain.burnGrass(around: point.x, radius: 3)
            }
            for i in tanks.indices where tanks[i].isAlive && tanks[i].id != tank.id && !struck.contains(tanks[i].id)
                && (tanks[i].turretCenter - point).length < tanks[i].radius {
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
            updateIslandDrift(dt)
            drive(dt)
            if driveDirection != nil || tanks.contains(where: isUnsettled) {
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
        let isSettling = tanks.contains(where: isUnsettled)
        let isSettled = projectiles.isEmpty && flames.isEmpty && explosions.isEmpty && !isSettling
        if phase == .firing, isSettled {
            endTurn()
        } else if phase == .killCam, isSettled {
            killCamHold -= dt
            if killCamHold <= 0 { finishKillCam() }
        }

        let isSmoking = !smolders.isEmpty || tanks.contains { $0.healthFraction < 0.5 }
        let isMoving = tanks.contains(where: \.isRocking) || turrets.contains { !$0.isResting }
        let isAnimating = isSmoking || isMoving || islandDrift != nil || tractorBeam != nil || phase == .killCam || !beams.isEmpty || !particles.isEmpty || !floatingTexts.isEmpty || !explosions.isEmpty || shake > 0.01 || flash > 0.01
        if !isAnimating && phase != .firing && chargeStartedAt == nil && driveDirection == nil {
            shake = 0
            flash = 0
            return false
        }
        return true
    }

    private func simulate(_ dt: Double) {
        if terrain.hasGusts, !projectiles.isEmpty {
            gustTimer += dt
            if gustTimer >= 0.7 {
                gustTimer = 0
                wind = min(max(wind + Double.random(in: -14...14, using: &rng), -Game.windReference * 1.3), Game.windReference * 1.3)
            }
        }
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
        slideTanks(dt)
        settleTanks(dt)
        burnInLava(dt)
        blowUpWrecks()
    }

    private func fly(_ p: inout Projectile, _ dt: Double) -> [Projectile] {
        p.velocity += (Vec(wind, -gravity) + terrain.force(at: p.position)) * dt
        p.position += p.velocity * dt
        p.smokeTimer += dt
        if terrain.isSwallowed(p.position) {
            particles += (0..<10).map { _ in
                Particle(kind: .spark, position: p.position, velocity: Vec(Double.random(in: -40...40), Double.random(in: -40...40)),
                         lifetime: 0.4, size: 1.6, color: .purple)
            }
            lastImpact = p.position
            return []
        }
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

        let hit = tankHit(by: p, extraReach: 0)
        guard hit != nil || terrain.isSolid(p.position) else { return [p] }
        if hit == nil, terrain.isInAbyss(p.position) {
            // Lost in the clouds below the islands.
            particles += (0..<6).map { _ in
                Particle(kind: .smoke, position: p.position + Vec(0, 4), velocity: Vec(Double.random(in: -8...8), Double.random(in: 4...12)),
                         lifetime: 1.2, size: 5, color: Color(white: 0.95))
            }
            lastImpact = p.position
            return []
        }
        // Land on the surface the shell came down on, but not on top of an island it hit from below.
        let top = terrain.support(at: p.position.x, y: p.position.y)
        let landing = top <= p.position.y + 4 ? max(p.position.y, top) : p.position.y
        return impact(p, at: Vec(p.position.x, landing), directHitID: hit)
    }

    private func roll(_ p: inout Projectile, _ dt: Double) -> [Projectile] {
        guard let direction = p.rollDirection else { return [] }
        p.rollTime += dt
        let here = terrain.support(at: p.position.x, y: p.position.y)
        let nextX = p.position.x + direction * 85 * dt
        let ahead = terrain.support(at: nextX, y: p.position.y)
        let hit = tankHit(by: p, extraReach: 2)
        if hit == nil, here - ahead > 12 {
            // Rolled off a ledge: fall the rest of the way.
            p.rollDirection = nil
            p.velocity = Vec(direction * 85, 0)
            return [p]
        }
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
        let hit = tankHit(by: p, extraReach: 4)
        if hit != nil || timeLeft <= 0 || p.position.x < 0 || p.position.x > Game.worldSize.x || p.position.y < 4 {
            explode(p.weapon, at: p.position, ownerID: p.ownerID, directHitID: hit)
            return []
        }
        return [p]
    }

    private func tankHit(by p: Projectile, extraReach: Double) -> Int? {
        tanks.first { tank in
            tank.isAlive && (tank.id != p.ownerID || p.age > 0.3) && (tank.turretCenter - p.position).length < tank.radius + extraReach
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
            let left = terrain.support(at: center.x - 4, y: center.y + 2), right = terrain.support(at: center.x + 4, y: center.y + 2)
            var rolling = p
            rolling.rollDirection = left == right ? (p.velocity.x < 0 ? -1 : 1) : (left < right ? -1 : 1)
            rolling.position = Vec(center.x, terrain.support(at: center.x, y: center.y + 2) + 2.5)
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
            flames += (0..<count).compactMap { i in
                let x = center.x + (Double(i) - Double(count - 1) / 2) * 4.5 + Double.random(in: -1.5...1.5, using: &rng)
                let life = Double.random(in: burnTime, using: &rng)
                let y = terrain.support(at: x, y: center.y + 6)
                guard !terrain.isInAbyss(Vec(x, y)) else { return nil }
                return Flame(x: x, y: y, life: life, ownerID: p.ownerID)
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

        case .singularity:
            explode(weapon, at: center, ownerID: p.ownerID, directHitID: directHitID, style: .plasma)
            let core = Vec(center.x, min(center.y + 45, Game.worldSize.y - 20))
            terrain.addWell(GravityWell(center: core, strength: 200, turnsLeft: 3))
            floatingTexts.append(FloatingText(position: core + Vec(0, 30), text: "Black hole!", color: .purple))
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
        if terrain.isIcy, radius >= 20 { triggerAvalanche(at: center, size: radius) }
        blastEffects(at: center, radius: radius, style: style)
        undermine(around: center.x, radius: radius * 1.5, ownerID: ownerID)

        rock(tanksNear: center, reach: (radius + Tank.standardRadius) * 2, strength: weapon.damage / 60 + radius / 40)
        for i in tanks.indices where tanks[i].isAlive {
            let reach = radius + tanks[i].radius
            let distance = tanks[i].id == directHitID ? 0 : (tanks[i].turretCenter - center).length
            guard distance < reach else { continue }
            let falloff = distance / reach
            var amount = weapon.damage * (1 - falloff * falloff)
            if tanks[i].kind == .icebreaker, (center.x - tanks[i].position.x) * (tanks[i].angle <= 90 ? 1 : -1) > 4 {
                amount *= 0.5
                floatingTexts.append(FloatingText(position: tanks[i].turretCenter + Vec(0, 40), text: "Armored", color: .cyan))
            }
            damage(tankAt: i, by: amount, attackerID: ownerID)
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
            if terrain.isIcy, !tanks[i].isAnchored {
                tanks[i].slide += side * push * 70
            }
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
        smolders.append(Smolder(x: center.x, y: center.y, spread: radius * 0.4, duration: smolderTime, remaining: smolderTime))
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
        if mission != nil, victimID == 0 { mission?.damageTaken += applied }
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

    private func isUnsettled(_ tank: Tank) -> Bool {
        !tank.isAnchored && (tank.fallDistance > 0 || abs(tank.slide) > 0.5
            || tank.position.y > terrain.support(at: tank.position.x, y: tank.position.y) + 0.5)
    }

    /// On ice, a pushed tank keeps sliding, speeding up downhill, until friction stops it or it hits a wall.
    private func slideTanks(_ dt: Double) {
        guard terrain.isIcy else { return }
        for i in tanks.indices where !tanks[i].isAlive { tanks[i].slide = 0 }
        for i in tanks.indices where !tanks[i].isAnchored && tanks[i].isAlive {
            let x = tanks[i].position.x, y = tanks[i].position.y
            let onGround = y <= terrain.support(at: x, y: y) + 0.5
            let slope = (terrain.support(at: x + 3, y: y + 4) - terrain.support(at: x - 3, y: y + 4)) / 6
            if tanks[i].slide == 0, abs(slope) < 0.7 || !onGround { continue }
            if onGround {
                tanks[i].slide -= slope * 160 * dt
                tanks[i].slide *= max(0, 1 - 1.4 * dt)
            }
            if abs(tanks[i].slide) < 3, abs(slope) < 0.7 {
                tanks[i].slide = 0
                continue
            }
            let nextX = min(max(x + tanks[i].slide * dt, 12), Game.worldSize.x - 12)
            if terrain.support(at: nextX, y: y + 4) > y + 3 {
                tanks[i].slide = 0
                continue
            }
            tanks[i].position.x = nextX
            tanks[i].treadTravel += nextX - x
            let ground = terrain.support(at: nextX, y: y + 2)
            if ground > y { tanks[i].position.y = ground }
        }
    }

    /// A big blast high on an icy slope sends snow sliding down onto whatever is below.
    private func triggerAvalanche(at center: Vec, size: Double) {
        let left = terrain.support(at: center.x - 50, y: center.y), right = terrain.support(at: center.x + 50, y: center.y)
        guard max(center.y - left, center.y - right) > 25 else { return }
        let direction: Double = left < right ? -1 : 1
        let x = min(max(center.x + direction * 75, 20), Game.worldSize.x - 20)
        let landing = Vec(x, terrain.support(at: x, y: center.y))
        terrain.addDirt(center: landing, radius: size * 0.75)
        particles += (0..<30).map { _ in
            Particle(kind: .debris, position: center + Vec(direction * Double.random(in: 0...60), Double.random(in: 0...20)),
                     velocity: Vec(direction * Double.random(in: 40...120), Double.random(in: -10...40)),
                     lifetime: Double.random(in: 0.6...1.2), size: Double.random(in: 1.5...3.5), color: .white)
        }
        floatingTexts.append(FloatingText(position: landing + Vec(0, 40), text: "Avalanche!", color: .white))
        shake = max(shake, 0.4)
    }

    /// Tanks standing in lava burn; the damage shows up as one number every half second.
    private func burnInLava(_ dt: Double) {
        guard terrain.lavaLevel != nil else { return }
        for i in tanks.indices where tanks[i].isAlive && !tanks[i].isAnchored
            && terrain.isInLava(x: tanks[i].position.x, y: tanks[i].position.y) {
            let before = tanks[i].health
            damage(tankAt: i, by: Game.lavaDamagePerSecond * dt, attackerID: tanks[i].lastAttackerID, bypassesShield: true, showsText: false)
            lavaDamage[tanks[i].id, default: 0] += before - tanks[i].health
            if Double.random(in: 0...1) < dt * 20 {
                particles.append(Particle(kind: .fire, position: tanks[i].position + Vec(Double.random(in: -10...10), 2),
                                          velocity: Vec(0, Double.random(in: 15...30)), lifetime: 0.5, size: 4, color: .orange))
            }
        }
        lavaTextTimer += dt
        guard lavaTextTimer >= 0.5 else { return }
        lavaTextTimer = 0
        for (id, amount) in lavaDamage where amount >= 1 {
            if let tank = tanks.first(where: { $0.id == id }) {
                floatingTexts.append(FloatingText(position: tank.turretCenter + Vec(0, 26), text: "-\(Int(amount.rounded()))", color: .orange))
            }
        }
        lavaDamage = [:]
    }

    /// Every third turn the vents blow, building up the ground and scorching anything close.
    private func eruptVents() {
        guard !terrain.vents.isEmpty, turnNumber % 3 == 0 else { return }
        for x in terrain.vents {
            let mouth = Vec(x, terrain.support(at: x, y: .infinity))
            terrain.addDirt(center: mouth + Vec(0, 4), radius: 16)
            particles += ParticleFactory.explosion(at: mouth + Vec(0, 6), radius: 20)
            particles += (0..<20).map { _ in
                Particle(kind: .fire, position: mouth, velocity: Vec(Double.random(in: -40...40), Double.random(in: 80...200)),
                         lifetime: Double.random(in: 0.6...1.2), size: Double.random(in: 3...6), color: .orange)
            }
            sound.explosion(atX: x, radius: 26)
            for i in tanks.indices where tanks[i].isAlive && abs(tanks[i].position.x - x) < 35 {
                damage(tankAt: i, by: 20, attackerID: nil, bypassesShield: true)
            }
            floatingTexts.append(FloatingText(position: mouth + Vec(0, 50), text: "Eruption!", color: .orange))
        }
        shake = max(shake, 0.5)
        startLoop()
    }

    private func settleTanks(_ dt: Double) {
        for i in tanks.indices where !tanks[i].isAnchored {
            let ground = terrain.support(at: tanks[i].position.x, y: tanks[i].position.y)
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
                    if terrain.isInAbyss(tanks[i].position) {
                        rescueFromAbyss(i)
                    } else if !tanks[i].isParachuting {
                        damage(tankAt: i, by: max(0, tanks[i].fallDistance - Game.safeFallHeight) * Game.fallDamagePerUnit, attackerID: tanks[i].lastAttackerID, bypassesShield: true)
                    }
                    tanks[i].fallDistance = 0
                    tanks[i].isParachuting = false
                }
            }
        }
    }

    /// Falling into the clouds costs a big chunk of health (none with a parachute); a salvage drone
    /// then drops the tank back onto the nearest island.
    private func rescueFromAbyss(_ i: Int) {
        let fell = tanks[i].position
        if !tanks[i].isParachuting {
            damage(tankAt: i, by: Game.abyssDamage, attackerID: tanks[i].lastAttackerID, bypassesShield: true, showsText: false)
            floatingTexts.append(FloatingText(position: fell + Vec(0, 30), text: "Into the abyss! -\(Int(Game.abyssDamage))", color: .white))
        } else {
            floatingTexts.append(FloatingText(position: fell + Vec(0, 30), text: "Rescued", color: .white))
        }
        let spawn = terrain.spawnPoint(near: fell.x)
        tanks[i].position = spawn
        tanks[i].fallDistance = 0
        particles += (0..<10).map { _ in
            Particle(kind: .smoke, position: fell + Vec(Double.random(in: -10...10), 4), velocity: Vec(Double.random(in: -10...10), Double.random(in: 6...16)),
                     lifetime: 1.4, size: 6, color: Color(white: 0.95))
        }
    }

    private func updateFlames(_ dt: Double) {
        guard !flames.isEmpty || !burnDamage.isEmpty else { return }
        for i in flames.indices {
            flames[i].life -= dt
            let x = flames[i].x
            let probe = flames[i].y + 2
            let here = terrain.support(at: x, y: probe)
            let left = terrain.support(at: x - 2, y: probe), right = terrain.support(at: x + 2, y: probe)
            if min(left, right) < here - 0.3 {
                flames[i].x = min(max(x + (left < right ? -1 : 1) * 28 * dt, 0), Game.worldSize.x)
            }
            flames[i].y = terrain.support(at: flames[i].x, y: probe)
            if terrain.isInAbyss(Vec(flames[i].x, flames[i].y)) { flames[i].life = 0 }
            terrain.burnGrass(around: flames[i].x, radius: 5)
            flames[i].emitTimer += dt
            if flames[i].emitTimer >= 0.05 {
                flames[i].emitTimer = 0
                let base = Vec(flames[i].x + Double.random(in: -2...2), flames[i].y + 1)
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
            let nearby = flames.filter { abs($0.x - tank.position.x) < 12 && abs(tank.position.y - $0.y) < 10 }
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
        if tractorBeam != nil {
            tractorBeam?.age += dt
            if let beam = tractorBeam, beam.age >= TractorBeam.duration { tractorBeam = nil }
        }
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
            if p.kind == .debris, terrain.isSolid(p.position) { p.age = p.lifetime }
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
            let ground = terrain.support(at: turrets[i].position.x, y: turrets[i].position.y) + 2
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
            let ground = Vec(x, terrain.support(at: x, y: smolders[i].y + 6) + 1)
            guard !terrain.isInAbyss(ground) else { continue }
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

        for tank in tanks where tank.healthFraction < 0.5 {
            let interval = !tank.isAlive ? 0.08 : tank.healthFraction < 0.25 ? 0.14 : 0.35
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
        turnNumber += 1
        terrain.ageWells()
        applyTurnHazards()
        if tanks[currentIndex].kind == .crawler, tanks[currentIndex].isAlive { burrow(currentIndex) }
        let alive = tanks.filter(\.isAlive)
        if Set(alive.map(\.side)).count <= 1 {
            if !startKillCam() { endRound(winnerID: alive.first?.side) }
            return
        }
        if var run = mission {
            if current.side != 0 { run.enemyTurns += 1 }
            mission = run
            if case let .survive(turns) = run.mission.objective, run.enemyTurns >= turns {
                return finishMission(won: true)
            }
            if case .trickShot = run.mission.objective, !tanks[0].inventory.hasAmmo, projectiles.isEmpty {
                return finishMission(won: false)
            }
            promoteGunnerPod()
        }
        repeat {
            currentIndex = (currentIndex + 1) % tanks.count
        } while !takesTurns(currentIndex)
        wind = randomWind()
        if tanks[currentIndex].shieldRegen > 0 {
            tanks[currentIndex].shield = min(tanks[currentIndex].shield + tanks[currentIndex].shieldRegen, tanks[currentIndex].shieldCap)
        }
        startIslandDrift()
        if tanks[currentIndex].kind == .icebreaker { advanceIcebreaker(currentIndex) }
        phase = .aiming
        scheduleComputerTurn()
    }

    // MARK: Hazards and bosses between turns

    /// Lava keeps burning and vents erupt. Deaths here aren't anyone's shot, so they don't get a kill cam.
    private func applyTurnHazards() {
        let aliveBefore = tanks.filter(\.isAlive).count
        for i in tanks.indices where tanks[i].isAlive && !tanks[i].isAnchored && terrain.isInLava(x: tanks[i].position.x, y: tanks[i].position.y) {
            damage(tankAt: i, by: 10, attackerID: tanks[i].lastAttackerID, bypassesShield: true)
        }
        eruptVents()
        blowUpWrecks()
        if tanks.filter(\.isAlive).count < aliveBefore { lastShot = nil }
    }

    /// The Magma Crawler dives and comes up somewhere else, well away from its enemies.
    private func burrow(_ index: Int) {
        let old = tanks[index].position
        let enemyX = tanks.filter { $0.isAlive && $0.side != tanks[index].side }.map(\.position.x)
        var best = old.x
        for _ in 0..<20 {
            let x = Double.random(in: 80...920)
            let ground = terrain.support(at: x, y: .infinity)
            guard enemyX.allSatisfy({ abs($0 - x) > 220 }), !terrain.isInLava(x: x, y: ground) else { continue }
            best = x
            break
        }
        terrain.carve(center: old + Vec(0, 6), radius: 18, leavesScorch: false)
        particles += ParticleFactory.dirt(at: old, radius: 26)
        tanks[index].position = Vec(best, terrain.support(at: best, y: .infinity))
        particles += ParticleFactory.dirt(at: tanks[index].position, radius: 26)
        floatingTexts.append(FloatingText(position: tanks[index].turretCenter + Vec(0, 40), text: "Resurfaced!", color: .orange))
        tanks[index].angle = enemyX.first.map { $0 < best ? 135 : 45 } ?? tanks[index].angle
        shake = max(shake, 0.3)
    }

    /// The Icebreaker plows toward its target and rams it if it gets close.
    private func advanceIcebreaker(_ index: Int) {
        guard let target = tanks.indices.first(where: { tanks[$0].isAlive && tanks[$0].side != tanks[index].side }) else { return }
        let from = tanks[index].position
        let gap = tanks[target].position.x - from.x
        let travel = min(90, max(0, abs(gap) - 40))
        guard travel > 5 else { return }
        let x = from.x + (gap > 0 ? 1 : -1) * travel
        var drift = islandDrift ?? IslandDrift()
        drift.movers[index] = (from, Vec(x, terrain.support(at: x, y: .infinity)))
        if abs(gap) - travel < 50 { drift.ramTarget = (index, target) }
        islandDrift = drift
        tanks[index].angle = gap > 0 ? 45 : 135
        startLoop()
    }

    private func ram(by index: Int, target: Int) {
        let direction: Double = tanks[target].position.x > tanks[index].position.x ? 1 : -1
        damage(tankAt: target, by: 25, attackerID: tanks[index].id)
        tanks[target].slide += direction * 160
        tanks[target].hopVelocity += 60
        floatingTexts.append(FloatingText(position: tanks[target].turretCenter + Vec(0, 40), text: "Rammed!", color: .white))
        shake = max(shake, 0.6)
        buzz(0.8)
        sound.explosion(atX: tanks[target].position.x, radius: 18)
        phase = .firing
        lastShot = nil
        startLoop()
    }

    /// The Mothership lifts its target high with a tractor beam and drops it.
    private func abduct() {
        guard let target = tanks.indices.first(where: { tanks[$0].isAlive && tanks[$0].side != current.side }) else { return }
        lastShot = nil
        victimsThisShot = []
        phase = .firing
        accumulator = 0
        tractorBeam = TractorBeam(sourceIndex: currentIndex, targetIndex: target)
        tanks[target].position.y += Game.abductionHeight
        tanks[target].lastAttackerID = current.id
        floatingTexts.append(FloatingText(position: tanks[target].turretCenter + Vec(0, 20), text: "Abducted!", color: .green))
        sound.laser(atX: tanks[target].position.x)
        startLoop()
    }

    // MARK: Drifting islands

    var isTerrainMoving: Bool { islandDrift != nil }

    private func startIslandDrift() {
        let moving = terrain.islands.filter { $0.sway != .zero }
        guard !moving.isEmpty || leviathan != nil else { return }
        var drift = IslandDrift()
        if var flight = leviathan {
            flight.phase += 0.9
            drift.creatureFrom = flight.center
            drift.creatureTo = Leviathan.center(home: flight.home, phase: flight.phase)
            leviathan = flight
        }
        for island in moving {
            let phase = island.phase + 0.8
            terrain.setIslandPhase(id: island.id, phase)
            drift.from[island.id] = island.offset
            drift.to[island.id] = island.position(atPhase: phase)
        }
        for i in tanks.indices where !tanks[i].isAnchored {
            if let id = terrain.supportingIsland(at: tanks[i].position.x, y: tanks[i].position.y), drift.to[id] != nil {
                drift.riders[i] = id
            }
        }
        islandDrift = drift
        startLoop()
    }

    private func updateIslandDrift(_ dt: Double, snap: Bool = false) {
        guard var drift = islandDrift else { return }
        drift.elapsed = snap ? Game.islandDriftDuration : min(drift.elapsed + dt, Game.islandDriftDuration)
        let t = drift.elapsed / Game.islandDriftDuration
        let eased = t * t * (3 - 2 * t)
        for (id, start) in drift.from {
            guard let end = drift.to[id], let island = terrain.islands.first(where: { $0.id == id }) else { continue }
            let next = start + (end - start) * eased
            let delta = next - island.offset
            terrain.moveIsland(id: id, to: next)
            for (index, rider) in drift.riders where rider == id && tanks.indices.contains(index) {
                tanks[index].position += delta
            }
        }
        for (index, move) in drift.movers where tanks.indices.contains(index) {
            let x = move.from.x + (move.to.x - move.from.x) * eased
            tanks[index].position = Vec(x, terrain.support(at: x, y: max(move.from.y, move.to.y) + 40))
            tanks[index].treadTravel += 1
        }
        if let from = drift.creatureFrom, let to = drift.creatureTo, var flight = leviathan {
            flight.center = from + (to - from) * eased
            for pod in flight.pods where tanks.indices.contains(pod.index) {
                tanks[pod.index].position = flight.center + pod.offset
            }
            leviathan = flight
        }
        islandDrift = drift.elapsed >= Game.islandDriftDuration ? nil : drift
        if islandDrift == nil, let ram = drift.ramTarget, tanks[ram.attacker].isAlive, tanks[ram.target].isAlive {
            self.ram(by: ram.attacker, target: ram.target)
        }
    }

    private func randomWind() -> Double {
        if let range = mission?.windRange { return Double.random(in: range).rounded() }
        return maxWind > 0 ? Double.random(in: -maxWind...maxWind).rounded() : 0
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
            tanks[i].position = Vec(x, terrain.support(at: x, y: .infinity))
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

    func place(tank index: Int, at position: Vec) {
        tanks[index].position = position
        phase = .firing
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
