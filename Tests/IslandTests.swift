import Testing
@testable import DuoTanks

/// Floating islands, the cloud sea below them, and updrafts.
struct IslandTests {
    private func island(id: Int = 0, x: Double = 400, y: Double = 200, width: Int = 120) -> Island {
        Island(id: id, offset: Vec(x, y), bottoms: Array(repeating: -40, count: width), tops: Array(repeating: 0, count: width),
               grass: Array(repeating: 1, count: width), home: Vec(x, y), sway: .zero, phase: 0)
    }

    @Test func thingsRestOnTopOfAnIslandButNotBelowIt() {
        let terrain = Terrain(islands: [island()])
        #expect(terrain.support(at: 450, y: 230) == 200, "standing on top")
        #expect(terrain.support(at: 450, y: 100) == 0, "underneath, the only support is the cloud sea")
        #expect(terrain.supportingIsland(at: 450, y: 200) == 0)
        #expect(terrain.isSolid(Vec(450, 180)))
        #expect(!terrain.isSolid(Vec(450, 120)))
        #expect(terrain.isInAbyss(Vec(450, 0)))
    }

    @Test func blastsCarveIslandsAndCanDestroyThem() {
        var terrain = Terrain(islands: [island()])
        terrain.carve(center: Vec(460, 200), radius: 15)
        #expect(abs(terrain.support(at: 460, y: 230) - 185) < 0.01)
        terrain.carve(center: Vec(460, 180), radius: 200)
        #expect(terrain.islands.isEmpty)
    }

    @Test func dirtLandsOnIslandsAndIsLostOverTheClouds() {
        var terrain = Terrain(islands: [island()])
        terrain.addDirt(center: Vec(460, 205), radius: 10)
        #expect(terrain.support(at: 460, y: 300) > 205)
        terrain.addDirt(center: Vec(100, 50), radius: 10)
        #expect(terrain.height(at: 100) == 0)
    }

    @Test func tanksSpawnOnTheNearestIsland() {
        let terrain = Terrain(islands: [island(id: 0, x: 100), island(id: 1, x: 700)])
        let spawn = terrain.spawnPoint(near: 760)
        #expect((730...790).contains(spawn.x))
        #expect(spawn.y == 200)
    }

    @Test func updraftsCarryShotsHigherAndFarther() throws {
        let calm = Terrain(islands: [island(x: 100), island(id: 1, x: 760)])
        let windy = Terrain(islands: [island(x: 100), island(id: 1, x: 760)], updrafts: [Updraft(x: 300...700, strength: 60)])
        func shot(_ terrain: Terrain) -> Vec? {
            Ballistics(terrain: terrain, wind: 0, gravity: 100, speedPerPower: Game.speedPerPower, origin: Vec(160, 207), ownerID: 0, tanks: [])
                .impact(angle: 35, power: 30)
        }
        let plain = try #require(shot(calm)), lifted = try #require(shot(windy))
        #expect(lifted.x > plain.x + 30)
    }
}

/// Rules that only show up on the islands.
@MainActor
struct IslandGameplayTests {
    private func makeGame() -> Game {
        var settings = MatchSettings()
        settings.world = .aerie
        settings.weather = .clear
        settings.volume = 0
        settings.hapticsEnabled = false
        let game = Game(settings: settings)
        let left = Island(id: 0, offset: Vec(200, 200), bottoms: Array(repeating: -40, count: 160), tops: Array(repeating: 0, count: 160),
                          grass: Array(repeating: 1, count: 160), home: Vec(200, 200), sway: .zero, phase: 0)
        let right = Island(id: 1, offset: Vec(640, 220), bottoms: Array(repeating: -40, count: 160), tops: Array(repeating: 0, count: 160),
                           grass: Array(repeating: 1, count: 160), home: Vec(640, 220), sway: .zero, phase: 0)
        game.installScenario(terrain: Terrain(islands: [left, right]), tankXs: [280, 720])
        return game
    }

    @Test func tanksStartOnTheirIslands() {
        let game = makeGame()
        #expect(game.tanks[0].position.y == 200)
        #expect(game.tanks[1].position.y == 220)
    }

    @Test func fallingIntoTheCloudsHurtsAndGetsYouRescued() {
        let game = makeGame()
        game.place(tank: 1, at: Vec(500, 250))
        game.runUntilSettled()
        #expect(game.tanks[1].health == 100 - Game.abyssDamage)
        let island = game.terrain.supportingIsland(at: game.tanks[1].position.x, y: game.tanks[1].position.y)
        #expect(island != nil, "back on solid ground at \\(game.tanks[1].position)")
    }

    @Test func aParachuteMakesTheAbyssHarmless() {
        let game = makeGame()
        game.give(.parachute, quantity: 1, toTank: 1)
        game.place(tank: 1, at: Vec(500, 250))
        game.runUntilSettled()
        #expect(game.tanks[1].health == 100)
    }
}
