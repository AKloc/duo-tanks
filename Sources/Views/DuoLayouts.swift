import SwiftUI

enum LayoutSetting: String, CaseIterable, Identifiable {
    /// Tabletop when the phone lies fully open and face-up, otherwise standard.
    case auto, standard, tabletop

    var id: Self { self }
    var name: String { rawValue.capitalized }
}

/// Director mode's chase camera: rides along with the shell, holds on the impact, then eases back out.
@MainActor
final class DirectorCamera {
    private(set) var camera = Camera.overview
    private(set) var visibleWorld: CGRect?
    private var lastTime: Double?
    private var holdUntil = 0.0
    private var focus = Camera.overview

    func update(game: Game, time: Double) -> Camera? {
        let dt = lastTime.map { min(max(time - $0, 0), 0.1) } ?? 0
        lastTime = time
        let target: Camera
        if game.phase == .firing, let shell = game.projectiles.first {
            focus = Camera(center: shell.position, zoom: 2.2)
            holdUntil = time + 1.4
            target = focus
        } else if game.phase == .firing || time < holdUntil {
            target = Camera(center: game.lastImpact ?? focus.center, zoom: 2)
        } else {
            target = .overview
        }
        let ease = min(1, dt * 3)
        camera.center += (target.center - camera.center) * ease
        camera.zoom += (target.zoom - camera.zoom) * ease
        let halfWidth = Game.worldSize.x / (2 * camera.zoom)
        camera.center.x = min(max(camera.center.x, halfWidth), Game.worldSize.x - halfWidth)
        if target == .overview, camera.zoom < 1.02 {
            camera = .overview
            return nil
        }
        return camera
    }

    func record(visible: CGRect?) {
        visibleWorld = visible
    }
}

/// The lower half in director mode: the whole battlefield, with a box showing the chase camera's view.
struct MiniMapPanel: View {
    let game: Game
    let director: DirectorCamera

    var body: some View {
        BattlefieldView(game: game, viewport: director, isSecondary: true, fitHeight: Game.worldSize.y * 1.4)
            .overlay(alignment: .topLeading) {
                Label("Overview", systemImage: "map")
                    .font(.caption.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(10)
            }
    }
}

/// Lying flat between two people: each player's half faces them.
struct TabletopView: View {
    let game: Game
    let onQuit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if let far = game.players.last {
                PlayerHalf(game: game, player: far, isPrimary: false, onQuit: onQuit)
                    .rotationEffect(.degrees(180))
            }
            Rectangle().fill(.black).frame(height: 2)
            if let near = game.players.first {
                PlayerHalf(game: game, player: near, isPrimary: true, onQuit: onQuit)
            }
        }
        .ignoresSafeArea()
    }
}

struct PlayerHalf: View {
    let game: Game
    let player: Player
    let isPrimary: Bool
    let onQuit: () -> Void

    var body: some View {
        if case let .shopping(index) = game.phase, game.players[index].id == player.id {
            ShopView(game: game, playerIndex: index)
        } else {
            VStack(spacing: 0) {
                BattlefieldView(game: game, isSecondary: !isPrimary, fitHeight: 330)
                    .frame(maxHeight: .infinity)
                panel
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private var panel: some View {
        switch game.phase {
        case let .shopping(index):
            WaitingPanel(player: player, message: "\(game.players[index].name) is shopping…", game: game)
        case .aiming, .firing:
            if game.current.id == player.id {
                ControlPanel(game: game, hinge: nil, onQuit: onQuit)
            } else {
                WaitingPanel(player: player, message: "\(game.current.name)'s turn", game: game)
            }
        default:
            ControlPanel(game: game, hinge: nil, onQuit: onQuit)
        }
    }
}

struct WaitingPanel: View {
    let player: Player
    let message: String
    let game: Game

    var body: some View {
        let tank = game.tanks.first { $0.id == player.id }
        HStack(spacing: 12) {
            Circle().fill(player.color).frame(width: 12, height: 12)
            Text(player.name).font(.headline)
            if let tank {
                HealthLabel(health: tank.health, shield: tank.shield)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
    }
}

/// Covers the screen while the phone changes hands. Fold to pass it over; unfolding starts the turn.
struct HandoffCover: View {
    let player: Player
    let isShopping: Bool
    let isFolded: Bool
    let onStart: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(colors: [player.color.mix(with: .black, by: 0.6), .black], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(spacing: 14) {
                Image(systemName: isFolded ? "iphone.gen3" : "arrow.left.arrow.right")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(player.color)
                Text(isShopping ? "\(player.name)'s shop" : "\(player.name)'s turn")
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                if isFolded {
                    Text("Unfold to play")
                        .font(.title3.bold())
                        .foregroundStyle(.white.opacity(0.85))
                } else {
                    Text("Pass the phone to \(player.name). Fold it to hand it over, then unfold.")
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.75))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 380)
                    Button(action: onStart) {
                        Text("I'm \(player.name), let's go")
                            .font(.headline)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(player.color)
                    .padding(.top, 6)
                }
            }
            .padding(24)
        }
        .transition(.opacity)
    }
}
