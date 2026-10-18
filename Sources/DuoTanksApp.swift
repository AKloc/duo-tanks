import SwiftUI

@main
struct DuoTanksApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

struct RootView: View {
    private enum Screen: Equatable {
        case menu, quickMatch, tour
        case playing(Game, fromTour: Bool)

        static func == (a: Screen, b: Screen) -> Bool {
            switch (a, b) {
            case (.menu, .menu), (.quickMatch, .quickMatch), (.tour, .tour): true
            case let (.playing(x, _), .playing(y, _)): x === y
            default: false
            }
        }
    }

    @State private var screen = Screen.menu
    @AppStorage("tourDifficulty") private var tourDifficulty = TourDifficulty.normal

    var body: some View {
        Group {
            switch screen {
            case .menu:
                let saved = MatchStore.load()
                MainMenuView(onContinueTour: { play($0, tourDifficulty) }, onTourMap: { screen = .tour },
                             onQuickMatch: { screen = .quickMatch },
                             onResumeMatch: saved.map { match in { screen = .playing(Game(restoring: match), fromTour: false) } },
                             resumeSummary: saved?.summary)
            case .quickMatch:
                QuickMatchView(onStart: { settings in screen = .playing(Game(settings: settings), fromTour: false) },
                               onBack: { screen = .menu })
            case .tour:
                TourView(onPlay: play, onBack: { screen = .menu })
            case let .playing(game, fromTour):
                GameView(game: game, onQuit: { screen = fromTour ? .tour : .menu }, onPlayMission: play)
            }
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.35), value: screen)
    }

    private func play(_ mission: Mission, _ difficulty: TourDifficulty) {
        screen = .playing(Game(mission: mission, difficulty: difficulty, settings: .saved()), fromTour: true)
    }
}
