import Foundation

enum WeaponBehavior {
    case explode
    case splitAtApex(count: Int, child: Weapon)
    case scatterOnImpact(count: Int, child: Weapon)
    case dirt
    /// Rolls downhill along the surface, then explodes.
    case roll
    /// Tunnels through the ground, then explodes.
    case burrow
    /// Spreads burning fuel that flows downhill.
    case napalm(flames: Int, burnTime: ClosedRange<Double>)
    /// Dirt that flows downhill and pools level in the nearest valley.
    case liquidDirt(volume: Double)
    /// A large energy blast with no fire or lingering smoke.
    case plasma
    /// A straight beam that ignores gravity and wind and burns through the ground.
    case laser
    /// Explodes, then bounces on to explode again.
    case bounce(times: Int)
    /// Draws its path and does nothing else.
    case tracer
    /// Clears dirt in front of the barrel without harming anyone.
    case riot
    /// Leaves a temporary black hole above where it lands.
    case singularity
}

enum Weapon: String, CaseIterable, Identifiable {
    case babyMissile, missile, babyNuke, nuke, mirv, deathsHead, funkyBomb
    case roller, sandhog, napalm, leapfrog, dirtClod, riotCharge, tracer
    case heavyRoller, hotNapalm, tonOfDirt, liquidDirt, plasmaBlast, laser, blackHole
    case mirvWarhead, deathsHeadWarhead, funkyBomblet

    var id: Self { self }

    /// Weapons a player can own and fire, in menu order.
    static let arsenal: [Weapon] = [
        .babyMissile, .missile, .babyNuke, .nuke, .mirv, .deathsHead, .funkyBomb, .plasmaBlast, .laser, .blackHole,
        .roller, .heavyRoller, .sandhog, .napalm, .hotNapalm, .leapfrog,
        .dirtClod, .tonOfDirt, .liquidDirt, .riotCharge, .tracer,
    ]

    var name: String {
        switch self {
        case .babyMissile: "Shell"
        case .missile: "Missile"
        case .babyNuke: "Mini Nuke"
        case .nuke: "Nuke"
        case .mirv: "MIRV"
        case .deathsHead: "Hydra"
        case .funkyBomb: "Cluster Bomb"
        case .roller: "Roller"
        case .sandhog: "Burrower"
        case .napalm: "Napalm"
        case .leapfrog: "Skipper"
        case .dirtClod: "Dirt Bomb"
        case .riotCharge: "Dig Charge"
        case .tracer: "Tracer"
        case .heavyRoller: "Heavy Roller"
        case .hotNapalm: "Inferno"
        case .tonOfDirt: "Landslide"
        case .liquidDirt: "Mudflow"
        case .plasmaBlast: "Ion Blast"
        case .laser: "Laser"
        case .blackHole: "Black Hole"
        case .mirvWarhead, .deathsHeadWarhead: "Warhead"
        case .funkyBomblet: "Bomblet"
        }
    }

    var isUnlimited: Bool { self == .babyMissile }

    var blastRadius: Double {
        switch self {
        case .babyMissile: 16
        case .missile: 28
        case .babyNuke: 55
        case .nuke: 95
        case .mirv, .mirvWarhead: 26
        case .deathsHead, .deathsHeadWarhead: 42
        case .funkyBomb: 30
        case .funkyBomblet: 20
        case .roller: 30
        case .sandhog: 26
        case .napalm: 10
        case .leapfrog: 22
        case .dirtClod: 38
        case .riotCharge: 34
        case .tracer: 0
        case .heavyRoller: 50
        case .hotNapalm: 12
        case .tonOfDirt: 75
        case .liquidDirt: 12
        case .plasmaBlast: 70
        case .laser: 4
        case .blackHole: 12
        }
    }

    /// Damage at the center of the blast or on a direct hit.
    var damage: Double {
        switch self {
        case .babyMissile: 60
        case .missile: 80
        case .babyNuke: 100
        case .nuke: 150
        case .mirv, .mirvWarhead: 50
        case .deathsHead, .deathsHeadWarhead: 70
        case .funkyBomb: 60
        case .funkyBomblet: 40
        case .roller: 70
        case .sandhog: 55
        case .leapfrog: 45
        case .heavyRoller: 100
        case .plasmaBlast: 90
        case .laser: 90
        case .blackHole: 20
        case .napalm, .hotNapalm, .dirtClod, .tonOfDirt, .liquidDirt, .riotCharge, .tracer: 0
        }
    }

    var behavior: WeaponBehavior {
        switch self {
        case .mirv: .splitAtApex(count: 5, child: .mirvWarhead)
        case .deathsHead: .splitAtApex(count: 9, child: .deathsHeadWarhead)
        case .funkyBomb: .scatterOnImpact(count: 7, child: .funkyBomblet)
        case .dirtClod, .tonOfDirt: .dirt
        case .roller, .heavyRoller: .roll
        case .sandhog: .burrow
        case .napalm: .napalm(flames: 9, burnTime: 3.5...4.5)
        case .hotNapalm: .napalm(flames: 15, burnTime: 5...6.5)
        case .liquidDirt: .liquidDirt(volume: 2_800)
        case .plasmaBlast: .plasma
        case .laser: .laser
        case .blackHole: .singularity
        case .leapfrog: .bounce(times: 2)
        case .tracer: .tracer
        case .riotCharge: .riot
        default: .explode
        }
    }
}
