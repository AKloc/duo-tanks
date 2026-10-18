import SwiftUI

/// One enemy in a mission.
struct EnemySpec {
    var name: String
    var color: Color
    var x: Double
    var health = 100.0
    var kind = TankKind.standard
    var radius = Tank.standardRadius
    var shield = 0.0
    var shieldRegen = 0.0
    var shieldCap = Tank.maxShield
    var inventory = Inventory(ammo: [.missile: 10])
    /// Never takes a turn: a practice target, or a boss pod waiting its turn.
    var isDummy = false
    /// Aims no better than this, whatever the difficulty.
    var aimCap: Difficulty?
    /// Placed exactly here instead of on the ground near `x`.
    var position: Vec?
    /// Health isn't scaled by difficulty.
    var fixedHealth = false
}

/// Everything needed to lay out a mission's battlefield.
struct MissionSetup {
    var terrain: Terrain
    var wind: ClosedRange<Double>
    var weather = Weather.clear
    var playerX: Double
    var playerInventory: Inventory
    var enemies: [EnemySpec]
    /// Center the Sky Leviathan circles around, if it's in this mission.
    var leviathanHome: Vec?

    static let enemyColors: [Color] = [.blue, .purple, .teal]

    static func make(_ mission: Mission, difficulty: TourDifficulty) -> MissionSetup {
        var setup = layout(for: mission)
        setup.playerInventory.parachutes += difficulty.bonusParachutes
        for i in setup.enemies.indices where !setup.enemies[i].fixedHealth {
            setup.enemies[i].health = (setup.enemies[i].health * difficulty.enemyHealthScale).rounded()
        }
        return setup
    }

    private static func layout(for mission: Mission) -> MissionSetup {
        let gunner = { (x: Double) in EnemySpec(name: "Gunner", color: .blue, x: x) }
        switch mission.id {
        case "terra-1":
            return MissionSetup(
                terrain: ground(seed: 11) { x in 110 + 30 * sin(x / 160) },
                wind: 0...0, playerX: 180, playerInventory: .starting,
                enemies: [EnemySpec(name: "Gunner", color: .blue, x: 790, health: 60, aimCap: .easy)]
            )
        case "terra-2":
            return MissionSetup(
                terrain: ground(seed: 12) { x in 90 + 230 * exp(-pow((x - 500) / 95, 2)) },
                wind: -8...8, playerX: 200, playerInventory: .starting,
                enemies: [EnemySpec(name: "Gunner", color: .blue, x: 810, health: 80, aimCap: .easy)]
            )
        case "terra-3":
            return MissionSetup(
                terrain: ground(seed: 13) { x in 120 + 22 * sin(x / 210 + 1) },
                wind: -34 ... -28, playerX: 170, playerInventory: .starting,
                enemies: [EnemySpec(name: "Gunner", color: .blue, x: 830, health: 80, aimCap: .normal)]
            )
        case "terra-4":
            let terrain = ground(seed: 14, noise: 4) { x in
                switch x {
                case ..<300: 250
                case ..<600: 250 - (x - 300) / 300 * 190
                case ..<680: 45
                case ..<720: 45 + (x - 680) / 40 * 245
                default: 290
                }
            }
            return MissionSetup(
                terrain: terrain, wind: 0...0, playerX: 170,
                playerInventory: Inventory(ammo: [.roller: 2], fuel: 0, hasUnlimitedShells: false),
                enemies: [EnemySpec(name: "Target", color: .orange, x: 640, health: 50, isDummy: true, fixedHealth: true)]
            )
        case "terra-5":
            return MissionSetup(
                terrain: ground(seed: 15) { x in 100 + 150 * exp(-pow((x - 500) / 120, 2)) },
                wind: -15...15, playerX: 500,
                playerInventory: Inventory(ammo: [.missile: 3], parachutes: 1, fuel: 30),
                enemies: [
                    EnemySpec(name: "West Gunner", color: .blue, x: 130, health: 80, aimCap: .normal),
                    EnemySpec(name: "East Gunner", color: .purple, x: 870, health: 80, aimCap: .normal),
                ]
            )
        case "terra-boss":
            let terrain = ground(seed: 16) { x in
                let t = min(max((x - 700) / 60, 0), 1)
                return 100 + 25 * sin(x / 130) + 110 * t * t * (3 - 2 * t)
            }
            return MissionSetup(
                terrain: terrain, wind: -15...15, playerX: 160,
                playerInventory: Inventory(ammo: [.missile: 6, .babyNuke: 2, .funkyBomb: 2], shields: 1, repairKits: 1, fuel: 30),
                enemies: [EnemySpec(name: "The Bastion", color: Color(red: 0.55, green: 0.55, blue: 0.5), x: 860, health: 300, kind: .bastion,
                                    radius: 26, shield: 50, shieldRegen: 25, shieldCap: 50, inventory: Inventory(ammo: [.missile: 40]))]
            )
        case "aerie-1":
            return MissionSetup(
                terrain: Terrain(islands: [
                    Terrain.makeIsland(id: 0, x: 60, y: 180, width: 200, thickness: 60, seed: 21),
                    Terrain.makeIsland(id: 1, x: 620, y: 220, width: 220, thickness: 60, seed: 22),
                ]),
                wind: -6...6, playerX: 160, playerInventory: .starting,
                enemies: [EnemySpec(name: "Gunner", color: .blue, x: 730, health: 70, aimCap: .easy)]
            )
        case "aerie-2":
            return MissionSetup(
                terrain: Terrain(islands: [
                    Terrain.makeIsland(id: 0, x: 40, y: 170, width: 190, thickness: 60, seed: 23),
                    Terrain.makeIsland(id: 1, x: 430, y: 340, width: 70, thickness: 230, hilliness: 4, seed: 24),
                    Terrain.makeIsland(id: 2, x: 660, y: 190, width: 210, thickness: 60, seed: 25),
                ], updrafts: [Updraft(x: 330...380, strength: 230)]),
                wind: -5...5, playerX: 130, playerInventory: .starting,
                enemies: [gunner(770)]
            )
        case "aerie-3":
            return MissionSetup(
                terrain: Terrain(islands: [
                    Terrain.makeIsland(id: 0, x: 60, y: 200, width: 220, thickness: 60, seed: 26),
                    Terrain.makeIsland(id: 1, x: 600, y: 250, width: 70, thickness: 18, hilliness: 2, seed: 27),
                ]),
                wind: 0...0, playerX: 160,
                playerInventory: Inventory(ammo: [.missile: 2], fuel: 0, hasUnlimitedShells: false),
                enemies: [EnemySpec(name: "Shielded Target", color: .orange, x: 635, health: 50, shield: 999, shieldCap: 999,
                                    isDummy: true, fixedHealth: true)]
            )
        case "aerie-4":
            let sway = Vec(42, 24)
            return MissionSetup(
                terrain: Terrain(islands: [
                    Terrain.makeIsland(id: 0, x: 70, y: 200, width: 180, thickness: 60, sway: sway, seed: 28),
                    Terrain.makeIsland(id: 1, x: 400, y: 140, width: 120, thickness: 50, sway: sway * 1.3, seed: 29),
                    Terrain.makeIsland(id: 2, x: 650, y: 230, width: 200, thickness: 60, sway: sway, seed: 30),
                ]),
                wind: -10...10, playerX: 160, playerInventory: .starting,
                enemies: [EnemySpec(name: "Gunner", color: .blue, x: 750, health: 90)]
            )
        case "aerie-5":
            return MissionSetup(
                terrain: Terrain(islands: [
                    Terrain.makeIsland(id: 0, x: 30, y: 300, width: 170, thickness: 55, seed: 31),
                    Terrain.makeIsland(id: 1, x: 380, y: 130, width: 230, thickness: 60, seed: 32),
                    Terrain.makeIsland(id: 2, x: 800, y: 310, width: 170, thickness: 55, seed: 33),
                ]),
                wind: -10...10, playerX: 495,
                playerInventory: Inventory(ammo: [.missile: 4], parachutes: 1, fuel: 30),
                enemies: [
                    EnemySpec(name: "West Gunner", color: .blue, x: 110, health: 80),
                    EnemySpec(name: "East Gunner", color: .purple, x: 880, health: 80),
                ]
            )
        case "aerie-boss":
            let home = Vec(690, 255)
            let pod = { (offset: Vec, gunner: Bool) in
                EnemySpec(name: "Gun Pod", color: Color(red: 0.4, green: 0.9, blue: 0.8), x: home.x + offset.x, health: 80, kind: .pod,
                          radius: 16, inventory: Inventory(ammo: [.missile: 60]), isDummy: !gunner, position: home + offset)
            }
            return MissionSetup(
                terrain: Terrain(islands: [
                    Terrain.makeIsland(id: 0, x: 40, y: 190, width: 230, thickness: 65, seed: 34),
                    Terrain.makeIsland(id: 1, x: 420, y: 150, width: 100, thickness: 45, seed: 35),
                    Terrain.makeIsland(id: 2, x: 830, y: 120, width: 140, thickness: 50, seed: 36),
                ]),
                wind: -8...8, playerX: 150,
                playerInventory: Inventory(ammo: [.missile: 6, .mirv: 2, .babyNuke: 1, .laser: 1], parachutes: 2, shields: 1, fuel: 30),
                enemies: Leviathan.podOffsets.enumerated().map { pod($1, $0 == 1) },
                leviathanHome: home
            )
        default:
            return MissionSetup(terrain: Terrain(flatHeight: 100), wind: 0...0, playerX: 200, playerInventory: .starting, enemies: [gunner(800)])
        }
    }

    /// Ground following `profile`, roughened with a little repeatable noise.
    private static func ground(seed: UInt64, noise amount: Double = 10, _ profile: (Double) -> Double) -> Terrain {
        let noise = ValueNoise(seed: seed)
        let heights = (0..<Int(Game.worldSize.x)).map { i -> Double in
            let x = Double(i)
            return max(20, profile(x) + (noise.fbm(x * 0.01, 1, octaves: 3) - 0.5) * amount * 2)
        }
        return Terrain(heights: heights)
    }
}

/// The Aerie boss: a great flying creature carrying three gun pods.
enum Leviathan {
    static let podOffsets = [Vec(-62, 4), Vec(0, 18), Vec(62, 4)]

    /// Where it circles to on a given turn.
    static func center(home: Vec, phase: Double) -> Vec {
        home + Vec(sin(phase) * 130, cos(phase * 1.3) * 25)
    }
}
