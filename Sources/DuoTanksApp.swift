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
    @State private var game: Game?

    var body: some View {
        Group {
            if let game {
                GameView(game: game) { self.game = nil }
                    .transition(.opacity)
            } else {
                TitleView { settings in game = Game(settings: settings) }
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: game == nil)
    }
}
