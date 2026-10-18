import SwiftUI

struct GameView: View {
    let game: Game
    let onQuit: () -> Void

    @State private var hinge: HingeState?
    @State private var isFaceUp = false
    @State private var director = DirectorCamera()
    @State private var handoffPlayerID: Int?
    @State private var handoffSawFold = false
    @State private var handoffShownAt = Date.distantPast
    @AppStorage("layout") private var layout = LayoutSetting.auto
    @AppStorage("handoff") private var handoffEnabled = true

    private var isLaptopPosture: Bool { hinge?.isPartiallyOpen ?? false }
    private var isFolded: Bool { hinge?.status == .closed }
    private var isTabletop: Bool {
        layout == .tabletop || (layout == .auto && hinge?.status == .fullyOpen && isFaceUp)
    }
    private var usesHandoff: Bool {
        handoffEnabled && !isTabletop && game.players.allSatisfy { !$0.isComputer }
    }

    /// Changes whenever the phone should change hands: a new turn or a new shopper.
    private var turnToken: String {
        switch game.phase {
        case .aiming: "turn-\(game.round)-\(game.current.id)"
        case let .shopping(index): "shop-\(game.round)-\(index)"
        default: "other"
        }
    }

    var body: some View {
        Group {
            if isTabletop {
                TabletopView(game: game, onQuit: onQuit)
            } else if case let .shopping(playerIndex) = game.phase {
                ShopView(game: game, playerIndex: playerIndex)
                    .transition(.move(edge: .bottom))
            } else {
                VStack(spacing: 0) {
                    BattlefieldView(game: game, director: isLaptopPosture ? director : nil)
                        .frame(maxHeight: .infinity)
                    if isLaptopPosture, game.phase == .firing {
                        MiniMapPanel(game: game, director: director)
                            .frame(maxHeight: .infinity)
                            .transition(.opacity)
                    } else {
                        ControlPanel(game: game, hinge: hinge, onQuit: onQuit)
                            .frame(maxHeight: isLaptopPosture ? .infinity : nil)
                            .fixedSize(horizontal: false, vertical: !isLaptopPosture)
                    }
                }
                .ignoresSafeArea(edges: isLaptopPosture ? .vertical : [])
            }
        }
        .overlay {
            if let id = handoffPlayerID, usesHandoff, let player = game.players.first(where: { $0.id == id }) {
                HandoffCover(player: player, isShopping: turnToken.hasPrefix("shop"), isFolded: isFolded, onStart: dismissHandoff)
            }
        }
        .animation(.snappy, value: game.phase)
        .animation(.easeInOut(duration: 0.25), value: handoffPlayerID)
        .animation(.easeInOut(duration: 0.3), value: isTabletop)
        .background(Color(red: 0.05, green: 0.06, blue: 0.2).ignoresSafeArea())
        .background(HingeReader { hinge = $0 })
        .onChange(of: turnToken, initial: true) { _, _ in requestHandoff() }
        .onChange(of: hinge) { oldValue, newValue in
            if handoffPlayerID != nil {
                // Folding hands the phone over; opening it again starts the turn. Only a real fold from
                // open counts, and hinge reports right as the cover appears (or the screen loads) are ignored.
                guard Date.now.timeIntervalSince(handoffShownAt) > 1 else { return }
                if newValue?.status == .closed, let oldValue, oldValue.status != .closed {
                    handoffSawFold = true
                } else if handoffSawFold, newValue?.status != .closed {
                    dismissHandoff()
                }
                return
            }
            guard let newValue, newValue.isPartiallyOpen else { return }
            game.aimWithHinge(degrees: newValue.degrees)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            isFaceUp = UIDevice.current.orientation == .faceUp
        }
        .onAppear {
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            isFaceUp = UIDevice.current.orientation == .faceUp
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
    }

    private func requestHandoff() {
        guard usesHandoff else { return }
        switch game.phase {
        case .aiming: handoffPlayerID = game.current.id
        case let .shopping(index): handoffPlayerID = game.players[index].id
        default: break
        }
        handoffSawFold = false
        handoffShownAt = .now
    }

    private func dismissHandoff() {
        handoffPlayerID = nil
        handoffSawFold = false
    }
}
