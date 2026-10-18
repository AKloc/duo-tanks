import SwiftUI

struct GameView: View {
    @State private var game = Game()
    @State private var hinge: HingeState?

    private var isLaptopPosture: Bool { hinge?.isPartiallyOpen ?? false }

    var body: some View {
        Group {
            if case let .shopping(playerIndex) = game.phase {
                ShopView(game: game, playerIndex: playerIndex)
                    .transition(.move(edge: .bottom))
            } else {
                VStack(spacing: 0) {
                    BattlefieldView(game: game)
                        .frame(maxHeight: .infinity)
                    ControlPanel(game: game, hinge: hinge)
                        .frame(maxHeight: isLaptopPosture ? .infinity : nil)
                        .fixedSize(horizontal: false, vertical: !isLaptopPosture)
                }
                .ignoresSafeArea(edges: isLaptopPosture ? .vertical : [])
            }
        }
        .animation(.snappy, value: game.phase)
        .background(Color(red: 0.05, green: 0.06, blue: 0.2).ignoresSafeArea())
        .background(HingeReader { hinge = $0 })
        .onChange(of: hinge) { _, newValue in
            guard let newValue, newValue.isPartiallyOpen else { return }
            game.aimWithHinge(degrees: newValue.degrees)
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
    }
}
