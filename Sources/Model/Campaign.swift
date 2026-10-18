import Foundation
import Observation
import SwiftUI

/// How forgiving the Tour is.
enum TourDifficulty: String, CaseIterable, Identifiable, Codable {
    case easy, normal, hard

    var id: Self { self }
    var name: String { rawValue.capitalized }

    var enemyAim: Difficulty {
        switch self {
        case .easy: .easy
        case .normal: .normal
        case .hard: .hard
        }
    }

    var enemyHealthScale: Double {
        switch self {
        case .easy: 0.7
        case .normal: 1
        case .hard: 1.25
        }
    }

    var bonusParachutes: Int {
        switch self {
        case .easy: 2
        case .normal: 1
        case .hard: 0
        }
    }

    /// Share of the predicted shot path drawn while aiming.
    var aimPreview: Double {
        switch self {
        case .easy: 0.6
        case .normal: 0.25
        case .hard: 0
        }
    }

    /// Extra shots allowed before losing the "under par" star.
    var parAllowance: Int {
        switch self {
        case .easy: 2
        case .normal: 1
        case .hard: 0
        }
    }

    /// Failed attempts before the game offers to show a working shot; `nil` never offers.
    var hintAfterFailures: Int? {
        switch self {
        case .easy: 1
        case .normal: 3
        case .hard: nil
        }
    }

    var summary: String {
        switch self {
        case .easy: "Long aim guide, weaker enemies, extra parachutes, hints after one miss."
        case .normal: "Short aim guide and hints if you get stuck."
        case .hard: "No aim guide, tougher enemies, no hints."
        }
    }
}

enum Chapter: String, CaseIterable, Identifiable, Codable {
    case terra, aerie, cinder, glacia, rift

    var id: Self { self }

    var name: String {
        switch self {
        case .terra: "Terra"
        case .aerie: "Aerie"
        case .cinder: "Cinder"
        case .glacia: "Glacia"
        case .rift: "The Rift"
        }
    }

    var subtitle: String {
        switch self {
        case .terra: "Training Grounds"
        case .aerie: "The Floating Isles"
        case .cinder: "The Forge World"
        case .glacia: "The Frozen Wastes"
        case .rift: "Luna and Beyond"
        }
    }

    var gravityLabel: String {
        switch self {
        case .terra: "1.0g"
        case .aerie: "0.5g"
        case .cinder: "1.6g"
        case .glacia: "1.0g · gales"
        case .rift: "0.4g · gravity wells"
        }
    }

    var theme: WorldTheme {
        switch self {
        case .terra: .hills
        case .aerie: .aerie
        case .cinder: .desert
        case .glacia: .snow
        case .rift: .moon
        }
    }

    var isAvailable: Bool { self == .terra || self == .aerie }
    var missions: [Mission] { Mission.all.filter { $0.chapter == self } }
}

enum Objective: Equatable {
    /// Destroy every enemy.
    case destroyAll
    /// Destroy every enemy, or last this many enemy turns.
    case survive(turns: Int)
    /// Destroy every target with only the ammo you're given.
    case trickShot
}

struct Mission: Identifiable, Equatable {
    let id: String
    let chapter: Chapter
    let number: Int
    let title: String
    let briefing: String
    let tip: String
    let objective: Objective
    /// Shots to beat for the second star.
    let par: Int
    var isBoss = false

    var code: String { "\(Chapter.allCases.firstIndex(of: chapter)! + 1)-\(number)" }

    var next: Mission? {
        guard let index = Mission.all.firstIndex(of: self), index + 1 < Mission.all.count else { return nil }
        let candidate = Mission.all[index + 1]
        return candidate.chapter.isAvailable ? candidate : nil
    }

    static let all: [Mission] = [
        Mission(id: "terra-1", chapter: .terra, number: 1, title: "First Contact",
                briefing: "A lone gunner across the valley. Show them what you've got.",
                tip: "Hold FIRE to charge your shot and let go to fire. Watch where it lands, then adjust.",
                objective: .destroyAll, par: 4),
        Mission(id: "terra-2", chapter: .terra, number: 2, title: "Over the Ridge",
                briefing: "The enemy is dug in behind a mountain. Go over the top.",
                tip: "Raise your barrel for a high, steep arc.",
                objective: .destroyAll, par: 4),
        Mission(id: "terra-3", chapter: .terra, number: 3, title: "Into the Wind",
                briefing: "A gale is blowing straight at you. Account for it.",
                tip: "The wind pushes shells while they fly. Aim long into a headwind, and watch the clouds.",
                objective: .destroyAll, par: 5),
        Mission(id: "terra-4", chapter: .terra, number: 4, title: "Downhill Delivery",
                briefing: "A target sits at the bottom of a deep gorge. You have two Rollers. Make them count.",
                tip: "Rollers roll downhill when they land. Drop one on the slope above the target.",
                objective: .trickShot, par: 1),
        Mission(id: "terra-5", chapter: .terra, number: 5, title: "Crossfire",
                briefing: "You're surrounded: one gunner on each side.",
                tip: "Deal with the closer threat first, and keep a parachute handy.",
                objective: .destroyAll, par: 7),
        Mission(id: "terra-boss", chapter: .terra, number: 6, title: "The Bastion",
                briefing: "A fortified bunker guards the pass. Its shield recharges every turn.",
                tip: "Small hits barely scratch the shield. Save your big guns and land them back to back.",
                objective: .destroyAll, par: 10, isBoss: true),
        Mission(id: "aerie-1", chapter: .aerie, number: 1, title: "Island Hopping",
                briefing: "Welcome to Aerie. Gravity is half of what you're used to.",
                tip: "Shots float a long way here. Use much less power than on Terra.",
                objective: .destroyAll, par: 4),
        Mission(id: "aerie-2", chapter: .aerie, number: 2, title: "Rising Air",
                briefing: "A column of warm air rises between you and the target.",
                tip: "Updrafts lift shells. Send a low, flat shot through the column and let it carry you up and over.",
                objective: .destroyAll, par: 4),
        Mission(id: "aerie-3", chapter: .aerie, number: 3, title: "Drop Zone",
                briefing: "This target's shield shrugs off any blast. The island under it is another story.",
                tip: "Blow the island apart beneath it. The clouds below go straight through shields.",
                objective: .trickShot, par: 2),
        Mission(id: "aerie-4", chapter: .aerie, number: 4, title: "Drifters",
                briefing: "The islands here swing wildly between turns.",
                tip: "Your last aim won't work twice. Re-aim every turn as the islands move.",
                objective: .destroyAll, par: 5),
        Mission(id: "aerie-5", chapter: .aerie, number: 5, title: "Skyfall",
                briefing: "Two gunners hold the high islands. Survive four of their turns, or take them both down.",
                tip: "Knocking an island out from under them is as good as a direct hit.",
                objective: .survive(turns: 4), par: 8),
        Mission(id: "aerie-boss", chapter: .aerie, number: 6, title: "The Sky Leviathan",
                briefing: "Something huge is circling the isles, with three gun pods on its back.",
                tip: "Destroy all three pods. It moves every turn, so lead your shots, and only one pod fires at a time.",
                objective: .destroyAll, par: 10, isBoss: true),
    ]

    static func with(id: String) -> Mission? { all.first { $0.id == id } }
}

/// Best stars, beaten missions and failed attempts, saved on the device.
@MainActor
@Observable
final class TourProgress {
    static let shared = TourProgress()

    private struct Saved: Codable {
        var stars: [String: Int] = [:]
        var failures: [String: Int] = [:]
    }

    private static let key = "tourProgress"
    private var saved: Saved

    private init() {
        saved = UserDefaults.standard.data(forKey: TourProgress.key).flatMap { try? JSONDecoder().decode(Saved.self, from: $0) } ?? Saved()
    }

    func stars(for mission: Mission) -> Int { saved.stars[mission.id] ?? 0 }
    func isBeaten(_ mission: Mission) -> Bool { stars(for: mission) > 0 }
    func failures(for mission: Mission) -> Int { saved.failures[mission.id] ?? 0 }

    func totalStars(in chapter: Chapter) -> Int { chapter.missions.reduce(0) { $0 + stars(for: $1) } }

    func isUnlocked(_ mission: Mission) -> Bool {
        guard mission.chapter.isAvailable, isUnlocked(mission.chapter) else { return false }
        let missions = mission.chapter.missions
        guard let index = missions.firstIndex(of: mission), index > 0 else { return true }
        return isBeaten(missions[index - 1]) || failures(for: missions[index - 1]) >= 3
    }

    /// A chapter opens once the previous chapter's boss is beaten.
    func isUnlocked(_ chapter: Chapter) -> Bool {
        guard chapter.isAvailable else { return false }
        guard let index = Chapter.allCases.firstIndex(of: chapter), index > 0 else { return true }
        let previous = Chapter.allCases[index - 1]
        return previous.missions.last.map(isBeaten) ?? true
    }

    func record(_ mission: Mission, stars: Int) {
        if stars > 0 {
            saved.stars[mission.id] = max(saved.stars[mission.id] ?? 0, stars)
            saved.failures[mission.id] = 0
        } else {
            saved.failures[mission.id, default: 0] += 1
        }
        if let data = try? JSONEncoder().encode(saved) { UserDefaults.standard.set(data, forKey: TourProgress.key) }
    }

    func reset() {
        saved = Saved()
        UserDefaults.standard.removeObject(forKey: TourProgress.key)
    }
}
