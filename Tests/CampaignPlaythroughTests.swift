import Foundation
import Testing
@testable import DuoTanks

/// Plays the whole Tour: a sharp-shooting stand-in for the player against enemies who aim like Normal difficulty.
/// Trick shots are covered separately by the solvability tests, since they need a particular shot rather than good aim.
@MainActor
struct CampaignPlaythroughTests {
    nonisolated static let missions = Mission.all.filter { $0.objective != .trickShot }

    /// Like a player retrying, a mission counts as winnable if any of three attempts wins (wind varies between them).
    @Test(arguments: missions)
    func missionCanBeWonOnNormal(_ mission: Mission) {
        var settings = MatchSettings()
        settings.volume = 0
        settings.hapticsEnabled = false
        settings.musicEnabled = false
        let game = Game(mission: mission, difficulty: .normal, settings: settings)
        var random = SeededRandom(seed: 7)
        func gaussian() -> Double {
            let u1 = Double.random(in: Double.ulpOfOne...1, using: &random), u2 = Double.random(in: 0...1, using: &random)
            return (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
        }
        var outcomes: [String] = []
        for attempt in 1...3 {
            if attempt > 1 { game.restartMission() }
            var turns = 0
            var steps = 0
            while turns < 60 {
                steps += 1
                if steps > 200 {
                    let tanks = game.tanks.map { "\($0.name) at \($0.position) slide \($0.slide) fall \($0.fallDistance) hp \(Int($0.health))" }
                    Issue.record("\(mission.id) attempt \(attempt) got stuck in \(game.phase) after \(turns) turns: \(tanks.joined(separator: "; "))")
                    return
                }
                if case .missionOver = game.phase { break }
                if game.phase == .aiming {
                    turns += 1
                    if game.current.id == 0 {
                        game.playTurnForTesting()
                    } else {
                        game.playTurnForTesting(angleError: gaussian() * Difficulty.normal.angleError, powerError: gaussian() * Difficulty.normal.powerError)
                    }
                }
                game.runUntilSettled()
            }
            if case .missionOver(won: true, _) = game.phase { return }
            let enemies = game.tanks.dropFirst().map { "\($0.name) \(Int($0.health))/\(Int($0.maxHealth))" }.joined(separator: ", ")
            outcomes.append("attempt \(attempt): \(game.phase) after \(turns) turns, enemies left \(enemies)")
        }
        Issue.record("\(mission.id) couldn't be won in three attempts. \(outcomes.joined(separator: "; "))")
    }

    @Test func theMothershipAbductsAndYourParachuteSavesYou() {
        var settings = MatchSettings()
        settings.volume = 0
        settings.hapticsEnabled = false
        let game = Game(mission: Mission.with(id: "rift-boss")!, difficulty: .normal, settings: settings)
        let parachutes = game.tanks[0].inventory.parachutes
        let ground = game.tanks[0].position.y
        game.setCurrentTank(1)
        game.abductForTesting()
        #expect(game.tractorBeam != nil)
        #expect(game.tanks[0].position.y > ground + 50, "lifted by the beam")
        game.runUntilSettled()
        #expect(abs(game.tanks[0].position.y - ground) < 1, "back on the ground")
        #expect(game.tanks[0].inventory.parachutes == parachutes - 1)
        #expect(game.tanks[0].health == game.tanks[0].maxHealth)
    }

    @Test func withoutAParachuteTheDropHurts() {
        var settings = MatchSettings()
        settings.volume = 0
        settings.hapticsEnabled = false
        let game = Game(mission: Mission.with(id: "rift-boss")!, difficulty: .hard, settings: settings)
        game.give(.parachute, quantity: -game.tanks[0].inventory.parachutes, toTank: 0)
        game.setCurrentTank(1)
        game.abductForTesting()
        game.runUntilSettled()
        #expect(game.tanks[0].health < game.tanks[0].maxHealth)
    }
}
