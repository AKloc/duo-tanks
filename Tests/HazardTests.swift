import Testing
@testable import DuoTanks

/// Lava, vents, ice, gravity wells and the bosses that use them.
@MainActor
struct HazardTests {
    private func makeGame(_ terrain: Terrain, tankXs: [Double] = [300, 700]) -> Game {
        var settings = MatchSettings()
        settings.world = .hills
        settings.weather = .clear
        settings.volume = 0
        settings.hapticsEnabled = false
        let game = Game(settings: settings)
        game.installScenario(terrain: terrain, tankXs: tankXs)
        return game
    }

    @Test func gravityWellsBendShotsAndSwallowCloseOnes() throws {
        var terrain = Terrain(flatHeight: 100)
        let plain = Ballistics(terrain: terrain, wind: 0, gravity: 200, speedPerPower: Game.speedPerPower, origin: Vec(200, 107), ownerID: 0, tanks: [])
        terrain.addHazards(wells: [GravityWell(center: Vec(560, 260), strength: 160)])
        let bent = Ballistics(terrain: terrain, wind: 0, gravity: 200, speedPerPower: Game.speedPerPower, origin: Vec(200, 107), ownerID: 0, tanks: [])
        let straight = try #require(plain.impact(angle: 45, power: 50))
        let curved = try #require(bent.impact(angle: 45, power: 50))
        #expect(abs(curved.x - straight.x) > 15)
        #expect(terrain.isSwallowed(Vec(560, 265)))
    }

    @Test func standingInLavaBurns() {
        var terrain = Terrain(flatHeight: 50)
        terrain.addHazards(lavaLevel: 80)
        let game = makeGame(terrain)
        game.lift(tank: 1, by: 0)
        game.runUntilSettled(maxSeconds: 1)
        #expect(game.tanks[1].health < 100)
    }

    @Test func ventsEruptEveryThirdTurnAndBuildTheGround() {
        var terrain = Terrain(flatHeight: 100)
        terrain.addHazards(vents: [500])
        let game = makeGame(terrain)
        for _ in 0..<3 {
            game.fireForTesting(weapon: .babyMissile, angle: 170, power: 5)
            game.runUntilSettled()
        }
        #expect(game.terrain.height(at: 500) > 110)
    }

    @Test func aTankKilledMidSlideStillLetsTheTurnEnd() {
        var heights = Array(repeating: 200.0, count: 1000)
        for x in 600..<1000 { heights[x] = 20 }
        var terrain = Terrain(heights: heights)
        terrain.addHazards(isIcy: true)
        let game = makeGame(terrain, tankXs: [300, 580])
        game.setHealth(5, ofTank: 1)
        game.fireForTesting(weapon: .missile, angle: 60, power: 34)
        game.runUntilSettled(maxSeconds: 30)
        #expect(game.phase != .firing)
    }

    @Test func blastsSendTanksSlidingOnIce() {
        var terrain = Terrain(flatHeight: 100)
        terrain.addHazards(isIcy: true)
        let game = makeGame(terrain, tankXs: [300, 360])
        game.fireForTesting(weapon: .missile, angle: 60, power: 18)
        game.runUntilSettled()
        #expect(abs(game.tanks[1].position.x - 360) > 8)
    }

    @Test func aBlackHoleLastsThreeTurns() {
        let game = makeGame(Terrain(flatHeight: 100))
        game.fireForTesting(weapon: .blackHole, angle: 60, power: 40)
        game.runUntilSettled()
        #expect(game.terrain.wells.count == 1)
        for _ in 0..<3 {
            game.fireForTesting(weapon: .babyMissile, angle: 170, power: 5)
            game.runUntilSettled()
        }
        #expect(game.terrain.wells.isEmpty)
    }
}

@MainActor
struct BossTests {
    private func settings() -> MatchSettings {
        var settings = MatchSettings()
        settings.volume = 0
        settings.hapticsEnabled = false
        settings.musicEnabled = false
        return settings
    }

    @Test func theCrawlerResurfacesSomewhereElse() {
        let game = Game(mission: Mission.with(id: "cinder-boss")!, difficulty: .normal, settings: settings())
        let start = game.tanks[1].position.x
        game.setCurrentTank(1)
        game.fireForTesting(weapon: .missile, angle: 170, power: 5)
        game.runUntilSettled()
        #expect(abs(game.tanks[1].position.x - start) > 1)
        #expect(abs(game.tanks[1].position.x - game.tanks[0].position.x) > 200, "it surfaces away from you")
    }

    @Test func theIcebreakersPlowHalvesBlastsFromTheFront() {
        let game = Game(mission: Mission.with(id: "glacia-boss")!, difficulty: .normal, settings: settings())
        game.place(tank: 0, at: game.tanks[1].position + Vec(-60, 0))
        game.runUntilSettled()
        game.setCurrentTank(0)
        game.fireForTesting(weapon: .missile, angle: 30, power: 10)
        game.runUntilSettled()
        let taken = game.tanks[1].maxHealth - game.tanks[1].health
        #expect(taken > 0 && taken <= 40, "armored hit took \(taken)")
    }

    @Test func theMothershipFliesAsASingleBoss() {
        let game = Game(mission: Mission.with(id: "rift-boss")!, difficulty: .hard, settings: settings())
        #expect(game.tanks[1].kind == .mothership)
        #expect(game.leviathan?.pods.count == 1)
    }
}
