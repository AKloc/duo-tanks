import Testing
@testable import DuoTanks

/// Plays real shots through the game's simulation on known terrain.
@MainActor
struct GameplayTests {
    private func makeGame(wind: Double = 0) -> Game {
        var settings = MatchSettings()
        settings.world = .hills
        settings.weather = .clear
        settings.volume = 0
        settings.hapticsEnabled = false
        let game = Game(settings: settings)
        game.installScenario(terrain: Terrain(flatHeight: 100), tankXs: [300, 520], wind: wind, currentIndex: 0)
        return game
    }

    /// Finds a whole-degree angle and power that lands on the other tank, the way a careful player would.
    private func aimAtOpponent(in game: Game) throws -> (angle: Double, power: Double) {
        let ballistics = Ballistics(
            heights: game.terrain.heights, wind: game.wind, gravity: game.gravity,
            speedPerPower: game.launchSpeed(forPower: 1), origin: game.tanks[0].turretCenter, ownerID: 0,
            tanks: game.tanks.map { .init(id: $0.id, center: $0.turretCenter) }
        )
        let target = game.tanks[1].turretCenter
        let rough = try #require(ballistics.bestAim(at: target))
        let angle = rough.angle.rounded()
        let power = try #require(stride(from: max(rough.power - 5, 1), through: min(rough.power + 5, 100), by: 0.05).min { a, b in
            let missA = ballistics.impact(angle: angle, power: a).map { ($0 - target).length } ?? .infinity
            let missB = ballistics.impact(angle: angle, power: b).map { ($0 - target).length } ?? .infinity
            return missA < missB
        })
        return (angle, power)
    }

    @Test func theComputersPredictionMatchesTheRealShot() throws {
        let game = makeGame(wind: 14)
        let ballistics = Ballistics(
            heights: game.terrain.heights, wind: game.wind, gravity: game.gravity,
            speedPerPower: game.launchSpeed(forPower: 1), origin: game.tanks[0].turretCenter, ownerID: 0, tanks: []
        )
        let predicted = try #require(ballistics.impact(angle: 40, power: 45))
        game.installScenario(terrain: Terrain(flatHeight: 100), tankXs: [300, 990], wind: 14)
        game.fireForTesting(weapon: .babyMissile, angle: 40, power: 45)
        game.runUntilSettled()
        let actual = try #require(game.lastImpact)
        #expect((actual - predicted).length < 1.5)
    }

    @Test func aDirectHitWithABabyMissileTakesSixtyHealth() throws {
        let game = makeGame()
        let aim = try aimAtOpponent(in: game)
        game.fireForTesting(weapon: .babyMissile, angle: aim.angle, power: aim.power)
        game.runUntilSettled()
        // 60 from the hit, plus a few points from dropping into the crater.
        #expect((58...65).contains(100 - game.tanks[1].health))
        #expect(game.phase == .aiming)
        #expect(game.currentIndex == 1)
    }

    @Test func aKillEndsTheRoundAndPaysTheShooter() throws {
        let game = makeGame()
        game.setHealth(30, ofTank: 1)
        let aim = try aimAtOpponent(in: game)
        game.fireForTesting(weapon: .babyMissile, angle: aim.angle, power: aim.power)
        game.runUntilSettled()
        #expect(game.phase == .roundOver(winnerID: 0))
        let start = game.settings.startingMoney
        #expect(game.players[0].money == start + 30 * Economy.perDamagePoint + Economy.perKill + Economy.roundWin + Economy.participation)
        #expect(game.players[1].money == start + Economy.participation)
        #expect(game.players[0].wins == 1)
        #expect(game.players[0].kills == 1)
    }

    @Test func aKillReplaysInTheKillCamWithoutPayingTwice() throws {
        let game = makeGame()
        game.setHealth(30, ofTank: 1)
        let aim = try aimAtOpponent(in: game)
        game.fireForTesting(weapon: .funkyBomb, angle: aim.angle, power: aim.power)
        var sawKillCam = false
        for _ in 0..<6_000 where game.phase == .firing || game.phase == .killCam {
            game.stepForTesting()
            if game.phase == .killCam { sawKillCam = true }
        }
        #expect(sawKillCam)
        #expect(game.phase == .roundOver(winnerID: 0))
        #expect(game.tanks[1].health == 0, "the replay plays out the same, scattered bomblets and all")
        #expect(game.players[0].kills == 1)
        #expect(game.camera == nil)
    }

    @Test func aLaserFliesStraightThroughTheWindAndHits() {
        let game = makeGame(wind: 40)
        game.fireForTesting(weapon: .laser, angle: 0, power: 10)
        game.runUntilSettled()
        #expect((88...91).contains(100 - game.tanks[1].health))
        #expect(game.tanks[0].health == 100)
    }

    @Test func plasmaHurtsWithoutScorchingTheGround() throws {
        let game = makeGame()
        let aim = try aimAtOpponent(in: game)
        game.fireForTesting(weapon: .plasmaBlast, angle: aim.angle, power: aim.power)
        game.runUntilSettled()
        #expect(game.tanks[1].health < 15)
        #expect(!game.terrain.scorchMarks.contains { $0.radius == Weapon.plasmaBlast.blastRadius }, "only the wreck's own blast scorches")
    }

    @Test func theShopChargesAndStocksItems() throws {
        let game = makeGame()
        game.setHealth(1, ofTank: 1)
        let aim = try aimAtOpponent(in: game)
        game.fireForTesting(weapon: .babyMissile, angle: aim.angle, power: aim.power)
        game.runUntilSettled()
        game.continueAfterRound()
        #expect(game.phase == .shopping(playerIndex: 0))
        let money = game.players[0].money
        game.buy(.weapon(.missile))
        #expect(game.players[0].money == money - 3_000)
        #expect(game.players[0].inventory.count(of: .missile) == 5)
        game.buy(.weapon(.deathsHead))
        game.buy(.weapon(.deathsHead))
        #expect(game.players[0].inventory.count(of: .deathsHead) == 1, "the second one is unaffordable")
    }

    @Test func aParachuteBreaksTheFall() {
        let game = makeGame()
        game.give(.parachute, quantity: 1, toTank: 1)
        game.lift(tank: 1, by: 80)
        game.runUntilSettled()
        #expect(game.tanks[1].health == 100)
        #expect(game.tanks[1].inventory.parachutes == 0)
    }

    @Test func fallingWithoutAParachuteHurts() {
        let game = makeGame()
        game.lift(tank: 1, by: 80)
        game.runUntilSettled()
        #expect(abs(game.tanks[1].health - (100 - (80 - Game.safeFallHeight) * Game.fallDamagePerUnit)) < 0.5)
    }

    @Test func drivingMovesTheTankAndBurnsFuel() {
        let game = makeGame()
        game.setFuel(50, ofTank: 0)
        game.startDriving(1)
        for _ in 0..<60 { game.stepForTesting() }
        game.stopDriving()
        let moved = game.tanks[0].position.x - 300
        #expect(abs(moved - Game.driveSpeed) < 1)
        #expect(abs(game.tanks[0].inventory.fuel - (50 - moved)) < 0.01)
    }

    @Test func drivingStopsWhenTheFuelRunsOut() {
        let game = makeGame()
        game.setFuel(10, ofTank: 0)
        game.startDriving(-1)
        for _ in 0..<120 { game.stepForTesting() }
        #expect(abs(game.tanks[0].position.x - 290) < 0.5)
        #expect(game.driveDirection == nil)
    }

    @Test func aSteepSlopeStopsTheTank() {
        let game = makeGame()
        var heights = Array(repeating: 100.0, count: 1000)
        for x in 320..<1000 { heights[x] = 150 }
        game.installScenario(terrain: Terrain(heights: heights), tankXs: [300, 700])
        game.setFuel(100, ofTank: 0)
        game.startDriving(1)
        for _ in 0..<180 { game.stepForTesting() }
        #expect(game.tanks[0].position.x < 320)
        #expect(game.driveDirection == nil)
    }

    @Test func drivingOffACliffHurts() {
        let game = makeGame()
        var heights = Array(repeating: 100.0, count: 1000)
        for x in 0..<310 { heights[x] = 180 }
        game.installScenario(terrain: Terrain(heights: heights), tankXs: [300, 700])
        game.setFuel(40, ofTank: 0)
        game.startDriving(1)
        for _ in 0..<180 { game.stepForTesting() }
        game.stopDriving()
        for _ in 0..<120 { game.stepForTesting() }
        #expect(game.tanks[0].position.y < 101)
        #expect(abs(game.tanks[0].health - (100 - (80 - Game.safeFallHeight) * Game.fallDamagePerUnit)) < 1)
    }

    @Test func aShieldSoaksUpTheBlast() throws {
        let game = makeGame()
        game.setCurrentTank(1)
        game.give(.shield, quantity: 1, toTank: 1)
        game.activateShield()
        #expect(game.tanks[1].shield == Tank.maxShield)
        game.setCurrentTank(0)
        let aim = try aimAtOpponent(in: game)
        game.fireForTesting(weapon: .babyMissile, angle: aim.angle, power: aim.power)
        game.runUntilSettled()
        #expect(game.tanks[1].health >= 94, "only fall damage gets through")
    }
}
