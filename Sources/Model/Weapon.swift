import Foundation

enum WeaponBehavior {
    case explode
    case splitAtApex(count: Int, child: Weapon)
    case scatterOnImpact(count: Int, child: Weapon)
    case dirt
}

enum Weapon: String, CaseIterable, Identifiable {
    case babyMissile, missile, babyNuke, nuke, mirv, deathsHead, funkyBomb, dirtClod
    case mirvWarhead, deathsHeadWarhead, funkyBomblet

    var id: Self { self }

    static let arsenal: [Weapon] = [.babyMissile, .missile, .babyNuke, .nuke, .mirv, .deathsHead, .funkyBomb, .dirtClod]

    var name: String {
        switch self {
        case .babyMissile: "Baby Missile"
        case .missile: "Missile"
        case .babyNuke: "Baby Nuke"
        case .nuke: "Nuke"
        case .mirv: "MIRV"
        case .deathsHead: "Death's Head"
        case .funkyBomb: "Funky Bomb"
        case .dirtClod: "Dirt Clod"
        case .mirvWarhead, .deathsHeadWarhead: "Warhead"
        case .funkyBomblet: "Bomblet"
        }
    }

    /// `nil` means unlimited.
    var startingAmmo: Int? {
        switch self {
        case .babyMissile: nil
        case .missile: 5
        case .babyNuke: 2
        case .nuke: 1
        case .mirv: 2
        case .deathsHead: 1
        case .funkyBomb: 2
        case .dirtClod: 3
        case .mirvWarhead, .deathsHeadWarhead, .funkyBomblet: 0
        }
    }

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
        case .dirtClod: 38
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
        case .dirtClod: 0
        }
    }

    var behavior: WeaponBehavior {
        switch self {
        case .mirv: .splitAtApex(count: 5, child: .mirvWarhead)
        case .deathsHead: .splitAtApex(count: 9, child: .deathsHeadWarhead)
        case .funkyBomb: .scatterOnImpact(count: 7, child: .funkyBomblet)
        case .dirtClod: .dirt
        default: .explode
        }
    }
}
