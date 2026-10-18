import SwiftUI

struct GameView: View {
    let game: Game
    let onQuit: () -> Void
    var onPlayMission: (Mission, TourDifficulty) -> Void = { _, _ in }

    @State private var hinge: HingeState?
    @State private var showsBriefing = false
    @Environment(\.scenePhase) private var scenePhase
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
        game.mission == nil && (layout == .tabletop || (layout == .auto && hinge?.status == .fullyOpen && isFaceUp))
    }
    private var usesHandoff: Bool {
        handoffEnabled && !isTabletop && game.mission == nil && game.players.allSatisfy { !$0.isComputer }
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
                    // Short screens always show enough sky for high shots and flying bosses.
                    BattlefieldView(game: game, director: isLaptopPosture ? director : nil, fitHeight: 330)
                        .frame(maxHeight: .infinity)
                        .ignoresSafeArea(edges: .horizontal)
                    if isLaptopPosture, game.phase == .firing {
                        MiniMapPanel(game: game, director: director)
                            .frame(maxHeight: .infinity)
                            .transition(.opacity)
                    } else {
                        ControlPanel(game: game, hinge: hinge, onQuit: onQuit, onPlayMission: onPlayMission)
                            .frame(maxHeight: isLaptopPosture ? .infinity : nil)
                            .fixedSize(horizontal: false, vertical: !isLaptopPosture)
                    }
                }
                .ignoresSafeArea(edges: isLaptopPosture ? .vertical : [])
            }
        }
        .overlay(alignment: .top) {
            if let run = game.mission, game.phase == .aiming || game.phase == .firing {
                MissionHUD(run: run, showsBriefing: showsBriefing, canShowHint: game.canShowHint, onHint: game.showHint)
                    .padding(.top, 34)
                    .allowsHitTesting(game.canShowHint)
            }
        }
        .onChange(of: game.mission?.mission.id, initial: true) { _, id in
            guard id != nil else { return }
            showsBriefing = true
            Task {
                try? await Task.sleep(for: .seconds(4))
                withAnimation { showsBriefing = false }
            }
        }
        .onChange(of: game.mission?.shots) { _, shots in
            if (shots ?? 0) > 0 { withAnimation { showsBriefing = false } }
        }
        .overlay {
            if let id = handoffPlayerID, usesHandoff, let player = game.players.first(where: { $0.id == id }) {
                HandoffCover(player: player, isShopping: turnToken.hasPrefix("shop"), isFolded: isFolded, hasHinge: hinge != nil, onStart: dismissHandoff)
            }
        }
        .animation(.snappy, value: game.phase)
        .animation(.easeInOut(duration: 0.25), value: handoffPlayerID)
        .animation(.easeInOut(duration: 0.3), value: isTabletop)
        .background(Color(red: 0.05, green: 0.06, blue: 0.2).ignoresSafeArea())
        .background(HingeReader { hinge = $0 })
        .onChange(of: turnToken, initial: true) { _, _ in requestHandoff() }
        .onChange(of: game.phase, initial: true) { _, _ in persist() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { persist() }
        }
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

    /// Quick matches save at the start of every turn and between rounds; a finished match clears its save.
    private func persist() {
        guard game.mission == nil else { return }
        if game.phase == .matchOver {
            MatchStore.clear()
        } else if let snapshot = game.snapshot() {
            MatchStore.save(snapshot)
        }
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
