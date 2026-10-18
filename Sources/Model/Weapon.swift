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
    case napalm
    /// Explodes, then bounces on to explode again.
    case bounce(times: Int)
    /// Draws its path and does nothing else.
    case tracer
    /// Clears dirt in front of the barrel without harming anyone.
    case riot
}

enum Weapon: String, CaseIterable, Identifiable {
    case babyMissile, missile, babyNuke, nuke, mirv, deathsHead, funkyBomb
    case roller, sandhog, napalm, leapfrog, dirtClod, riotCharge, tracer
    case mirvWarhead, deathsHeadWarhead, funkyBomblet

    var id: Self { self }

    /// Weapons a player can own and fire, in menu order.
    static let arsenal: [Weapon] = [
        .babyMissile, .missile, .babyNuke, .nuke, .mirv, .deathsHead, .funkyBomb,
        .roller, .sandhog, .napalm, .leapfrog, .dirtClod, .riotCharge, .tracer,
    ]

    var name: String {
        switch self {
        case .babyMissile: "Baby Missile"
        case .missile: "Missile"
        case .babyNuke: "Baby Nuke"
        case .nuke: "Nuke"
        case .mirv: "MIRV"
        case .deathsHead: "Death's Head"
        case .funkyBomb: "Funky Bomb"
        case .roller: "Roller"
        case .sandhog: "Sandhog"
        case .napalm: "Napalm"
        case .leapfrog: "Leapfrog"
        case .dirtClod: "Dirt Clod"
        case .riotCharge: "Riot Charge"
        case .tracer: "Tracer"
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
        case .napalm, .dirtClod, .riotCharge, .tracer: 0
        }
    }

    var behavior: WeaponBehavior {
        switch self {
        case .mirv: .splitAtApex(count: 5, child: .mirvWarhead)
        case .deathsHead: .splitAtApex(count: 9, child: .deathsHeadWarhead)
        case .funkyBomb: .scatterOnImpact(count: 7, child: .funkyBomblet)
        case .dirtClod: .dirt
        case .roller: .roll
        case .sandhog: .burrow
        case .napalm: .napalm
        case .leapfrog: .bounce(times: 2)
        case .tracer: .tracer
        case .riotCharge: .riot
        default: .explode
        }
    }
}
