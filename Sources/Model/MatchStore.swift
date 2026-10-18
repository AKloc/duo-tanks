import Foundation

/// A quick match frozen at the start of a turn (or between rounds), so it can be picked up later.
struct SavedMatch: Codable {
    enum Moment: Codable, Equatable {
        case turn
        case roundOver(winnerID: Int?)
        case shopping(playerIndex: Int)
    }

    struct SavedTank: Codable {
        let id: Int
        let name: String
        let position: Vec
        let health: Double
        let shield: Double
        let angle: Double
        let power: Double
        let inventory: Inventory
        let selectedWeapon: Weapon
        let hasTurret: Bool
    }

    struct SavedPlayer: Codable {
        let id: Int
        let name: String
        let money: Int
        let wins: Int
        let kills: Int
        let inventory: Inventory
        let computer: Difficulty?
    }

    let settings: MatchSettings
    let theme: WorldTheme
    let weather: Weather
    let gravity: Double
    let maxWind: Double
    let wind: Double
    let terrain: Terrain
    let tanks: [SavedTank]
    let players: [SavedPlayer]
    let round: Int
    let currentIndex: Int
    let moment: Moment
    let roundEarnings: [Int: RoundEarnings]
    let savedAt: Date

    var summary: String {
        let opponent = players.contains { $0.computer != nil } ? "vs computer" : "two players"
        return "Round \(round)/\(settings.rounds) · \(theme.name) · \(opponent)"
    }
}

/// Keeps the one quick match in progress on disk.
enum MatchStore {
    private static var url: URL {
        URL.applicationSupportDirectory.appending(path: "match.json")
    }

    static func save(_ match: SavedMatch) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(match).write(to: url, options: .atomic)
        } catch {
            // A failed save just means there's nothing to resume.
        }
    }

    static func load() -> SavedMatch? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SavedMatch.self, from: data)
    }

    static func clear() {
        try? FileManager.default.removeItem(at: url)
    }
}
