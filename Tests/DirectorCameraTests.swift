import Testing
@testable import DuoTanks

@MainActor
struct DirectorCameraTests {
    private func makeGame() -> Game {
        var settings = MatchSettings()
        settings.world = .hills
        settings.weather = .clear
        settings.volume = 0
        settings.hapticsEnabled = false
        let game = Game(settings: settings)
        game.installScenario(terrain: Terrain(flatHeight: 100), tankXs: [300, 700])
        return game
    }

    @Test func showsTheWholeBattlefieldBetweenShots() {
        let director = DirectorCamera()
        #expect(director.update(game: makeGame(), time: 0) == nil)
    }

    @Test func chasesTheShellAndThenEasesBackOut() throws {
        let game = makeGame()
        let director = DirectorCamera()
        game.fireForTesting(weapon: .babyMissile, angle: 50, power: 55)
        var time = 0.0
        for _ in 0..<40 {
            game.stepForTesting()
            time += 1.0 / 60
            _ = director.update(game: game, time: time)
        }
        let camera = try #require(director.update(game: game, time: time))
        let shell = try #require(game.projectiles.first)
        #expect(camera.zoom > 1.5)
        #expect(abs(camera.center.x - shell.position.x) < 60)

        game.runUntilSettled()
        for _ in 0..<600 {
            time += 1.0 / 60
            _ = director.update(game: game, time: time)
        }
        #expect(director.update(game: game, time: time) == nil)
    }
}
