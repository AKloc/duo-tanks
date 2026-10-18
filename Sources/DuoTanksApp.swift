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
        case title, tour
        case playing(Game, fromTour: Bool)

        static func == (a: Screen, b: Screen) -> Bool {
            switch (a, b) {
            case (.title, .title), (.tour, .tour): true
            case let (.playing(x, _), .playing(y, _)): x === y
            default: false
            }
        }
    }

    @State private var screen = Screen.title

    var body: some View {
        Group {
            switch screen {
            case .title:
                TitleView(onStart: { settings in screen = .playing(Game(settings: settings), fromTour: false) },
                          onTour: { screen = .tour })
            case .tour:
                TourView(onPlay: play, onBack: { screen = .title })
            case let .playing(game, fromTour):
                GameView(game: game, onQuit: { screen = fromTour ? .tour : .title }, onPlayMission: play)
            }
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.35), value: screen)
    }

    private func play(_ mission: Mission, _ difficulty: TourDifficulty) {
        screen = .playing(Game(mission: mission, difficulty: difficulty, settings: .saved()), fromTour: true)
    }
}
