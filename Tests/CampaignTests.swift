import Testing
@testable import DuoTanks

@MainActor
struct CampaignTests {
    private func settings() -> MatchSettings {
        var settings = MatchSettings()
        settings.volume = 0
        settings.hapticsEnabled = false
        settings.musicEnabled = false
        return settings
    }

    @Test(arguments: Mission.all)
    func everyMissionStartsWithEveryoneReady(_ mission: Mission) {
        for difficulty in TourDifficulty.allCases {
            let game = Game(mission: mission, difficulty: difficulty, settings: settings())
            #expect(game.phase == .aiming)
            #expect(game.current.id == 0, "the player goes first")
            let player = game.tanks[0]
            #expect(!player.isBuried(in: game.terrain))
            #expect(!game.terrain.isInAbyss(player.position), "\(mission.id): the player starts on solid ground")
            #expect(game.terrain.support(at: player.position.x, y: player.position.y) == player.position.y)
            #expect(player.inventory.hasAmmo)
            for enemy in game.tanks.dropFirst() {
                #expect(enemy.isAlive)
                #expect(enemy.side != player.side)
                if !enemy.isAnchored {
                    #expect(!game.terrain.isInAbyss(enemy.position), "\(mission.id): \(enemy.name) starts on solid ground")
                    #expect(!enemy.isBuried(in: game.terrain))
                }
            }
        }
    }

    @Test func harderDifficultiesMakeToughEnemies() {
        let easy = Game(mission: Mission.with(id: "terra-boss")!, difficulty: .easy, settings: settings())
        let hard = Game(mission: Mission.with(id: "terra-boss")!, difficulty: .hard, settings: settings())
        #expect(easy.tanks[1].maxHealth < hard.tanks[1].maxHealth)
        #expect(easy.tanks[0].inventory.parachutes > hard.tanks[0].inventory.parachutes)
    }

    @Test func easyShowsALongerAimGuideAndHardShowsNone() {
        let mission = Mission.with(id: "terra-1")!
        #expect(Game(mission: mission, difficulty: .easy, settings: settings()).aimPreviewFraction > 0.5)
        #expect(Game(mission: mission, difficulty: .hard, settings: settings()).aimPreviewFraction == 0)
    }

    @Test func trickShotsTakeAwayTheFreeShells() {
        let game = Game(mission: Mission.with(id: "terra-4")!, difficulty: .normal, settings: settings())
        #expect(game.tanks[0].ammoCount(.babyMissile) == 0)
        #expect(game.tanks[0].selectedWeapon == .roller)
    }

    /// Searches angles and powers for a shot that wins, using the real simulation.
    private func findsWinningShot(missionID: String, weapon: Weapon, angles: StrideThrough<Double>, powers: StrideThrough<Double>) -> Bool {
        let game = Game(mission: Mission.with(id: missionID)!, difficulty: .hard, settings: settings())
        for angle in angles {
            for power in powers {
                game.restartMission()
                game.fireForTesting(weapon: weapon, angle: angle, power: power)
                game.runUntilSettled()
                if case .missionOver(won: true, _) = game.phase { return true }
            }
        }
        return false
    }

    @Test func downhillDeliveryCanBeSolvedWithOneRoller() {
        #expect(findsWinningShot(missionID: "terra-4", weapon: .roller, angles: stride(from: 25, through: 75, by: 5), powers: stride(from: 25, through: 80, by: 5)))
    }

    @Test func dropZoneCanBeSolvedWithAMissile() {
        #expect(findsWinningShot(missionID: "aerie-3", weapon: .missile, angles: stride(from: 15, through: 70, by: 5), powers: stride(from: 20, through: 70, by: 4)))
    }

    @Test func runningOutOfAmmoOnATrickShotFailsTheMission() {
        let game = Game(mission: Mission.with(id: "terra-4")!, difficulty: .normal, settings: settings())
        game.fireForTesting(weapon: .roller, angle: 170, power: 20)
        game.runUntilSettled()
        game.fireForTesting(weapon: .roller, angle: 170, power: 20)
        game.runUntilSettled()
        #expect(game.phase == .missionOver(won: false, stars: 0))
    }

    @Test func blastsCantGetThroughTheShieldButTheFallCan() {
        let game = Game(mission: Mission.with(id: "aerie-3")!, difficulty: .normal, settings: settings())
        game.give(.weapon(.babyNuke), quantity: 1, toTank: 1)
        game.setCurrentTank(1)
        game.fireForTesting(weapon: .babyNuke, angle: 90, power: 30)
        game.runUntilSettled()
        let target = game.tanks[1]
        #expect(target.shield > 0 && target.shield < 999, "the shield soaked up the blast")
        #expect(target.health == 0, "but the blast took out the thin island and the fall went straight through")
    }

    @Test func theBastionRechargesItsShield() {
        let game = Game(mission: Mission.with(id: "terra-boss")!, difficulty: .normal, settings: settings())
        #expect(game.tanks[1].kind == .bastion)
        #expect(game.tanks[1].shield == 50)
        #expect(game.tanks[1].shieldRegen > 0)
    }

    @Test func theLeviathanHasOneGunnerAtATime() {
        let game = Game(mission: Mission.with(id: "aerie-boss")!, difficulty: .normal, settings: settings())
        #expect(game.leviathan?.pods.count == 3)
        let gunners = game.players.filter { $0.id != 0 && !$0.isDummy }
        #expect(gunners.count == 1)
    }

    @Test func starsRewardShotsUnderParAndLittleDamage() throws {
        let mission = Mission.with(id: "terra-1")!
        let game = Game(mission: mission, difficulty: .hard, settings: settings())
        game.setHealth(1, ofTank: 1)
        let ballistics = Ballistics(
            terrain: game.terrain, wind: game.wind, gravity: game.gravity, speedPerPower: game.launchSpeed(forPower: 1),
            origin: game.tanks[0].turretCenter, ownerID: 0, tanks: game.tanks.map { .init(id: $0.id, center: $0.turretCenter, radius: $0.radius) }
        )
        let aim = try #require(ballistics.bestAim(at: game.tanks[1].turretCenter))
        game.fireForTesting(weapon: .babyMissile, angle: aim.angle, power: aim.power)
        game.runUntilSettled()
        #expect(game.phase == .missionOver(won: true, stars: 3))
    }
}

@MainActor
struct TourProgressTests {
    @Test func missionsUnlockInOrderAndChaptersAfterTheBoss() {
        let progress = TourProgress.shared
        progress.reset()
        defer { progress.reset() }
        let terra = Chapter.terra.missions
        #expect(progress.isUnlocked(terra[0]))
        #expect(!progress.isUnlocked(terra[1]))
        progress.record(terra[0], stars: 2)
        #expect(progress.isUnlocked(terra[1]))
        #expect(!progress.isUnlocked(.aerie))
        progress.record(terra[5], stars: 1)
        #expect(progress.isUnlocked(.aerie))
        #expect(!progress.isUnlocked(.cinder), "not built yet")
    }

    @Test func threeFailuresLetYouSkipAhead() {
        let progress = TourProgress.shared
        progress.reset()
        defer { progress.reset() }
        let terra = Chapter.terra.missions
        for _ in 0..<3 { progress.record(terra[0], stars: 0) }
        #expect(progress.isUnlocked(terra[1]))
    }

    @Test func bestStarsAreKept() {
        let progress = TourProgress.shared
        progress.reset()
        defer { progress.reset() }
        let mission = Chapter.terra.missions[0]
        progress.record(mission, stars: 3)
        progress.record(mission, stars: 1)
        #expect(progress.stars(for: mission) == 3)
    }
}
