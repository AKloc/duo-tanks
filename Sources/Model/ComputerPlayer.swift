import Foundation

enum Difficulty: String, CaseIterable, Identifiable {
    case easy, normal, hard

    var id: Self { self }
    var name: String { rawValue.capitalized }

    /// Typical aiming error, in degrees and power points, on a first shot.
    var angleError: Double {
        switch self {
        case .easy: 7
        case .normal: 3.5
        case .hard: 0.7
        }
    }

    var powerError: Double {
        switch self {
        case .easy: 9
        case .normal: 5.5
        case .hard: 1.2
        }
    }

    /// How much of the real wind it accounts for.
    /// The least its aim error shrinks to after repeated shots.
    var bestCorrection: Double {
        switch self {
        case .easy: 0.7
        case .normal: 0.5
        case .hard: 0.35
        }
    }

    var windJudgement: Double {
        switch self {
        case .easy: 0.4
        case .normal: 0.75
        case .hard: 1
        }
    }
}

/// Plays a computer-controlled tank through the same controls a person uses.
@MainActor
enum ComputerPlayer {
    /// Consecutive shots per computer player this round; each one tightens its aim, like a person bracketing.
    private static var shotsThisRound: [Int: (round: Int, count: Int)] = [:]

    static func takeTurn(in game: Game, difficulty: Difficulty) async {
        let me = game.current
        guard let target = game.tanks.filter({ $0.isAlive && $0.id != me.id }).min(by: { abs($0.position.x - me.position.x) < abs($1.position.x - me.position.x) }) else { return }

        game.setComputerStatus("Thinking…")
        try? await Task.sleep(for: .seconds(Double.random(in: 0.7...1.3)))
        guard !Task.isCancelled else { return }

        if me.health < 45, me.inventory.repairKits > 0 {
            game.useRepairKit()
            try? await Task.sleep(for: .seconds(0.5))
        }
        if me.shield <= 0, me.inventory.shields > 0, game.current.health < 75 || difficulty == .hard {
            game.activateShield()
            try? await Task.sleep(for: .seconds(0.4))
        }

        if game.current.isBuried(in: game.terrain), game.current.ammoCount(.riotCharge) != 0 {
            game.setComputerStatus("Digging out…")
            game.select(.riotCharge)
            game.setAngle(90)
            try? await Task.sleep(for: .seconds(0.4))
            game.beginCharge()
            try? await Task.sleep(for: .seconds(0.3))
            game.setComputerStatus(nil)
            game.releaseCharge(cappedAt: 15)
            return
        }

        let weapon = chooseWeapon(for: game.current, against: target, game: game, difficulty: difficulty)
        game.select(weapon)

        let ballistics = Ballistics(
            heights: game.terrain.heights,
            wind: game.wind * difficulty.windJudgement,
            gravity: game.gravity,
            speedPerPower: game.launchSpeed(forPower: 1),
            origin: game.current.turretCenter,
            ownerID: me.id,
            tanks: game.tanks.filter(\.isAlive).map { Ballistics.Target(id: $0.id, center: $0.turretCenter) }
        )
        let aimPoint = target.turretCenter
        let safeRadius = weapon.blastRadius + Tank.hitRadius + 10
        let aim = await Task.detached(priority: .userInitiated) { ballistics.bestAim(at: aimPoint, safeRadius: safeRadius) }.value
        guard !Task.isCancelled else { return }

        let record = shotsThisRound[me.id]
        let shots = record?.round == game.round ? record!.count : 0
        shotsThisRound[me.id] = (game.round, shots + 1)
        let sharpening = max(difficulty.bestCorrection, pow(0.7, Double(shots)))

        let fallbackAngle: Double = target.position.x > me.position.x ? 50 : 130
        let angle = (aim?.angle ?? fallbackAngle) + gaussian() * difficulty.angleError * sharpening
        let power = min(max((aim?.power ?? 60) + gaussian() * difficulty.powerError * sharpening, 5), 100)

        game.setComputerStatus("Aiming…")
        let start = game.current.angle
        for step in 1...20 {
            game.setAngle(start + (angle - start) * Double(step) / 20)
            try? await Task.sleep(for: .milliseconds(35))
        }
        guard !Task.isCancelled else { return }

        game.setComputerStatus("Firing!")
        game.beginCharge()
        while let charge = game.chargePower, charge < power, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(10))
        }
        game.setComputerStatus(nil)
        game.releaseCharge(cappedAt: power)
    }

    static func shop(in game: Game, playerIndex: Int, difficulty: Difficulty) {
        let wishlist: [ShopItem] = switch difficulty {
        case .easy: [.weapon(.missile), .weapon(.dirtClod), .parachute, .weapon(.babyNuke), .weapon(.funkyBomb), .weapon(.roller)].shuffled()
        case .normal: [.parachute, .weapon(.missile), .weapon(.riotCharge), .shield, .weapon(.mirv), .weapon(.babyNuke), .weapon(.roller), .repairKit, .weapon(.nuke)]
        case .hard: [.shield, .parachute, .weapon(.riotCharge), .weapon(.mirv), .weapon(.missile), .repairKit, .weapon(.plasmaBlast), .weapon(.babyNuke), .weapon(.nuke), .weapon(.deathsHead), .weapon(.heavyRoller)]
        }
        var purchases = 0
        var bought = true
        while bought, purchases < 10 {
            bought = false
            for item in wishlist where game.players[playerIndex].money >= item.price && purchases < 10 {
                let owned = game.players[playerIndex].inventory.count(of: item)
                if item == .shield || item == .repairKit, owned >= 2 { continue }
                if item == .parachute, owned >= 3 { continue }
                if item == .weapon(.riotCharge), owned >= 2 { continue }
                game.buy(item)
                purchases += 1
                bought = true
            }
        }
    }

    private static func chooseWeapon(for me: Tank, against target: Tank, game: Game, difficulty: Difficulty) -> Weapon {
        let distance = abs(target.position.x - me.position.x)
        let owned = Weapon.arsenal.filter { me.ammoCount($0) != 0 }
        func has(_ weapon: Weapon) -> Bool { owned.contains(weapon) }

        if difficulty == .easy {
            return [Weapon.babyMissile, .missile, .babyNuke, .funkyBomb].filter(has).randomElement() ?? .babyMissile
        }

        let terrain = game.terrain
        let isInValley = terrain.height(at: target.position.x - 40) > target.position.y + 8 || terrain.height(at: target.position.x + 40) > target.position.y + 8

        if distance > 180, target.health > 70, has(.nuke) { return .nuke }
        if distance > 140, target.health > 50, has(.deathsHead) { return .deathsHead }
        if distance > 120, has(.mirv), Bool.random() { return .mirv }
        if isInValley, has(.heavyRoller) { return .heavyRoller }
        if isInValley, has(.roller) { return .roller }
        if distance > 120, target.health > 60, has(.plasmaBlast) { return .plasmaBlast }
        if distance > 120, target.health > 40, has(.babyNuke) { return .babyNuke }
        if target.health <= 60, has(.missile) { return .missile }
        if has(.funkyBomb), Double.random(in: 0...1) < 0.3 { return .funkyBomb }
        if has(.missile) { return .missile }
        return .babyMissile
    }

    private static func gaussian() -> Double {
        let u1 = Double.random(in: Double.ulpOfOne...1), u2 = Double.random(in: 0...1)
        return (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
    }
}
