import Foundation
import Testing
@testable import DuoTanks

@MainActor
struct SaveTests {
    private func makeGame(world: WorldChoice = .hills) -> Game {
        var settings = MatchSettings()
        settings.world = world
        settings.weather = .clear
        settings.volume = 0
        settings.hapticsEnabled = false
        settings.computerOpponent = .normal
        return Game(settings: settings)
    }

    @Test func aMatchSurvivesASaveAndRestore() throws {
        let game = makeGame()
        game.fireForTesting(weapon: .missile, angle: 45, power: 40)
        game.runUntilSettled()
        let snapshot = try #require(game.snapshot())
        let data = try JSONEncoder().encode(snapshot)
        let restored = Game(restoring: try JSONDecoder().decode(SavedMatch.self, from: data))
        #expect(restored.round == game.round)
        #expect(restored.currentIndex == game.currentIndex)
        #expect(restored.wind == game.wind)
        #expect(restored.terrain.heights == game.terrain.heights, "craters come back too")
        for (a, b) in zip(restored.tanks, game.tanks) {
            #expect(a.position == b.position)
            #expect(a.health == b.health)
            #expect(a.inventory.count(of: .missile) == b.inventory.count(of: .missile))
        }
        #expect(restored.players[1].computer == .normal)
        #expect(restored.phase == .aiming)
    }

    @Test func floatingIslandsSaveTooAndLandWhereTheyWereHeaded() throws {
        let game = makeGame(world: .aerie)
        game.fireForTesting(weapon: .babyMissile, angle: 170, power: 5)
        game.runUntilSettled()
        let snapshot = try #require(game.snapshot())
        let restored = Game(restoring: snapshot)
        #expect(restored.terrain.islands.count == game.terrain.islands.count)
        let player = restored.tanks[0]
        #expect(abs(restored.terrain.support(at: player.position.x, y: player.position.y) - player.position.y) < 1, "the tank is still on its island")
    }

    @Test func missionsAndShotsInFlightArentSaved() {
        var settings = MatchSettings()
        settings.volume = 0
        #expect(Game(mission: Mission.with(id: "terra-1")!, difficulty: .normal, settings: settings).snapshot() == nil)
        let game = makeGame()
        game.fireForTesting(weapon: .missile, angle: 45, power: 40)
        #expect(game.snapshot() == nil)
    }

    @Test func theStoreKeepsOneMatch() throws {
        MatchStore.clear()
        defer { MatchStore.clear() }
        #expect(MatchStore.load() == nil)
        let game = makeGame()
        MatchStore.save(try #require(game.snapshot()))
        let loaded = try #require(MatchStore.load())
        #expect(loaded.round == 1)
        #expect(loaded.summary.contains("vs computer"))
        MatchStore.clear()
        #expect(MatchStore.load() == nil)
    }
}
