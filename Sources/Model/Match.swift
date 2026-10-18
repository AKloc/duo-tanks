import SwiftUI

struct Inventory {
    var ammo: [Weapon: Int] = [:]
    var parachutes = 0
    var shields = 0
    var repairKits = 0
    /// World units of driving left.
    var fuel = 0.0

    static let starting = Inventory(ammo: [.missile: 2], fuel: 30)

    /// `nil` means unlimited.
    func count(of weapon: Weapon) -> Int? {
        weapon.isUnlimited ? nil : ammo[weapon, default: 0]
    }

    func count(of item: ShopItem) -> Int {
        switch item {
        case let .weapon(weapon): count(of: weapon) ?? 0
        case .parachute: parachutes
        case .shield: shields
        case .repairKit: repairKits
        case .fuel: Int(fuel.rounded(.down))
        }
    }

    mutating func add(_ item: ShopItem, quantity: Int) {
        switch item {
        case let .weapon(weapon): ammo[weapon, default: 0] += quantity
        case .parachute: parachutes += quantity
        case .shield: shields += quantity
        case .repairKit: repairKits += quantity
        case .fuel: fuel += Double(quantity)
        }
    }
}

struct Player: Identifiable {
    let id: Int
    let name: String
    let color: Color
    var money: Int
    var wins = 0
    var kills = 0
    var inventory = Inventory.starting
    /// `nil` for a person.
    var computer: Difficulty?

    var isComputer: Bool { computer != nil }
}

struct MatchSettings {
    var rounds = 5
    var startingMoney = 15_000
    var world = WorldChoice.random
    var weather = WeatherSetting.auto
    var wind = WindSetting.normal
    var roughness = Roughness.rolling
    var volume = 0.8
    var hapticsEnabled = true
    /// `nil` for two people passing the phone.
    var computerOpponent: Difficulty?
}

/// Money earned this round, broken down for the results screen.
struct RoundEarnings {
    var damage = 0
    var kills = 0
    var bonus = 0

    var total: Int { damage + kills + bonus }
}

enum Economy {
    static let perDamagePoint = 40
    static let perKill = 2_500
    static let roundWin = 4_000
    static let participation = 1_000
}

enum ShopItem: Hashable, Identifiable {
    case weapon(Weapon)
    case parachute, shield, repairKit, fuel

    static let catalog: [ShopItem] = Weapon.arsenal.filter { !$0.isUnlimited }.map(ShopItem.weapon) + [.parachute, .shield, .repairKit, .fuel]

    var id: String {
        switch self {
        case let .weapon(weapon): weapon.rawValue
        case .parachute: "parachute"
        case .shield: "shield"
        case .repairKit: "repairKit"
        case .fuel: "fuel"
        }
    }

    var name: String {
        switch self {
        case let .weapon(weapon): weapon.name
        case .parachute: "Parachute"
        case .shield: "Shield"
        case .repairKit: "Repair Kit"
        case .fuel: "Fuel"
        }
    }

    var price: Int {
        switch self {
        case let .weapon(weapon):
            switch weapon {
            case .missile: 3_000
            case .babyNuke: 6_000
            case .nuke: 12_000
            case .mirv: 8_000
            case .deathsHead: 16_000
            case .funkyBomb: 7_000
            case .roller: 4_000
            case .sandhog: 4_000
            case .napalm: 7_000
            case .leapfrog: 5_000
            case .dirtClod: 2_000
            case .riotCharge: 2_000
            case .tracer: 500
            case .heavyRoller: 7_000
            case .hotNapalm: 11_000
            case .tonOfDirt: 4_000
            case .liquidDirt: 4_000
            case .plasmaBlast: 9_000
            case .laser: 10_000
            default: 0
            }
        case .parachute: 3_000
        case .shield: 8_000
        case .repairKit: 4_000
        case .fuel: 1_500
        }
    }

    /// How many you get per purchase.
    var bundle: Int {
        switch self {
        case let .weapon(weapon):
            switch weapon {
            case .missile, .dirtClod: 3
            case .roller, .sandhog, .leapfrog, .riotCharge, .liquidDirt: 2
            case .tracer: 5
            default: 1
            }
        case .parachute: 2
        case .shield, .repairKit: 1
        case .fuel: 60
        }
    }

    var summary: String {
        switch self {
        case let .weapon(weapon):
            switch weapon {
            case .missile: "A bigger bang than the Baby Missile."
            case .babyNuke: "Big blast. Clears a hilltop."
            case .nuke: "Huge blast and a blinding flash."
            case .mirv: "Splits into 5 warheads at the top of its arc."
            case .deathsHead: "Splits into 9 heavy warheads."
            case .funkyBomb: "Scatters bomblets on impact."
            case .roller: "Rolls downhill, then explodes."
            case .sandhog: "Tunnels under the target, then explodes."
            case .napalm: "Burning fuel that flows downhill."
            case .leapfrog: "Bounces twice, exploding each time."
            case .dirtClod: "A ball of dirt. Bury your opponent."
            case .riotCharge: "Blasts away dirt in front of you."
            case .tracer: "No damage. Leaves its path on screen."
            case .heavyRoller: "A bigger, deadlier Roller."
            case .hotNapalm: "More fuel that burns hotter and longer."
            case .tonOfDirt: "A huge mound of dirt. Bury them completely."
            case .liquidDirt: "Flows downhill and fills the valley it lands in."
            case .plasmaBlast: "A huge energy blast. No fire, no smoke."
            case .laser: "A straight beam. Ignores gravity and wind, burns through hills."
            default: ""
            }
        case .parachute: "Opens automatically when you fall. No fall damage."
        case .shield: "A bubble that absorbs 60 damage."
        case .repairKit: "Restores 35 health on your turn."
        case .fuel: "Drive your tank on your turn. Steep slopes stop you."
        }
    }

    var systemImage: String {
        switch self {
        case let .weapon(weapon):
            switch weapon {
            case .babyNuke, .nuke: "atom"
            case .mirv, .deathsHead: "sparkles"
            case .funkyBomb: "party.popper"
            case .roller: "circle.fill"
            case .sandhog: "arrow.down.right.circle"
            case .napalm: "flame"
            case .leapfrog: "hare"
            case .dirtClod: "mountain.2"
            case .riotCharge: "wind"
            case .tracer: "scribble"
            case .heavyRoller: "circle.circle.fill"
            case .hotNapalm: "flame.fill"
            case .tonOfDirt: "mountain.2.fill"
            case .liquidDirt: "drop.fill"
            case .plasmaBlast: "bolt.circle.fill"
            case .laser: "line.diagonal"
            default: "scope"
            }
        case .parachute: "umbrella.fill"
        case .shield: "shield.lefthalf.filled"
        case .repairKit: "wrench.and.screwdriver"
        case .fuel: "fuelpump.fill"
        }
    }
}
