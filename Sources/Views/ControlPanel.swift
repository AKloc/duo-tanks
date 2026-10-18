import SwiftUI

struct ControlPanel: View {
    let game: Game
    let hinge: HingeState?
    let onQuit: () -> Void

    var body: some View {
        Group {
            switch game.phase {
            case let .roundOver(winnerID):
                RoundResults(game: game, winnerID: winnerID)
            case .matchOver:
                MatchResults(game: game, onQuit: onQuit)
            default:
                controls(for: game.current)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
    }

    private func controls(for tank: Tank) -> some View {
        let money = game.players.first { $0.id == tank.id }?.money ?? 0
        let isComputer = game.isComputerTurn
        return HStack(spacing: 20) {
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    Circle().fill(tank.color).frame(width: 12, height: 12)
                    Text("\(tank.name)'s turn").font(.headline)
                    Text("Round \(game.round)/\(game.settings.rounds)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if hinge?.isPartiallyOpen == true {
                        Image(systemName: "laptopcomputer")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Hinge aiming")
                    }
                    Text(money, format: .currency(code: "USD").precision(.fractionLength(0)))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                    HealthLabel(health: tank.health, shield: tank.shield)
                    Menu {
                        Text("\(game.theme.name) · gravity \(Int(game.theme.gravityScale * 100))%")
                        Button("Quit to Title", systemImage: "xmark", role: .destructive, action: onQuit)
                    } label: {
                        Image(systemName: "ellipsis.circle").font(.title3)
                    }
                    .accessibilityLabel("Menu")
                }

                HStack(spacing: 12) {
                    Stepper(value: Binding(get: { tank.angle }, set: game.setAngle), in: 0...180) {
                        Text("Angle \(Int(tank.angle))°").monospacedDigit().lineLimit(1)
                    }
                    .frame(maxWidth: 200)
                    Spacer(minLength: 0)
                    weaponMenu(for: tank)
                    gearMenu(for: tank)
                }

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(game.chargePower.map { "\(Int($0))%" } ?? "\(Int(tank.power))%")
                        .font(.system(.largeTitle, design: .rounded).bold().monospacedDigit())
                        .foregroundStyle(game.chargePower == nil ? .secondary : .primary)
                        .contentTransition(.numericText())
                    if isComputer {
                        Label(game.computerStatus ?? "Computer's turn", systemImage: "cpu")
                            .font(.caption.bold())
                            .foregroundStyle(tank.color)
                            .transaction { $0.animation = nil }
                    } else {
                        Text(game.chargePower == nil ? "last power · hold FIRE to charge" : "power")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }

            ArcadeButton(color: tank.color, charge: game.chargePower, hapticsEnabled: game.settings.hapticsEnabled, onPress: game.beginCharge, onRelease: { game.releaseCharge() })
        }
        .disabled(game.phase != .aiming)
        .allowsHitTesting(!isComputer)
    }

    private func weaponMenu(for tank: Tank) -> some View {
        Menu {
            ForEach(Weapon.arsenal) { weapon in
                let count = tank.ammoCount(weapon)
                if count != 0 {
                    Button("\(weapon.name)  \(count.map(String.init) ?? "∞")") { game.select(weapon) }
                }
            }
        } label: {
            Label(tank.selectedWeapon.name, systemImage: ShopItem.weapon(tank.selectedWeapon).systemImage).lineLimit(1)
        }
        .buttonStyle(.bordered)
    }

    private func gearMenu(for tank: Tank) -> some View {
        let gear = tank.inventory
        return Menu {
            Button("Raise Shield (\(gear.shields))", systemImage: ShopItem.shield.systemImage, action: game.activateShield)
                .disabled(gear.shields == 0 || tank.shield > 0)
            Button("Use Repair Kit (\(gear.repairKits))", systemImage: ShopItem.repairKit.systemImage, action: game.useRepairKit)
                .disabled(gear.repairKits == 0 || tank.health >= 100)
            Label("Parachutes: \(gear.parachutes)", systemImage: ShopItem.parachute.systemImage)
        } label: {
            Label("Gear", systemImage: "shippingbox")
                .labelStyle(.iconOnly)
                .overlay(alignment: .topTrailing) {
                    if gear.shields + gear.repairKits + gear.parachutes > 0 {
                        Circle().fill(.orange).frame(width: 7, height: 7).offset(x: 5, y: -4)
                    }
                }
        }
        .buttonStyle(.bordered)
        .accessibilityLabel("Gear")
    }
}

struct HealthLabel: View {
    let health: Double
    let shield: Double

    var body: some View {
        HStack(spacing: 6) {
            if shield > 0 {
                Label("\(Int(shield.rounded(.up)))", systemImage: "shield.fill")
                    .foregroundStyle(.cyan)
            }
            Text("HP \(Int(health.rounded(.up)))")
        }
        .monospacedDigit()
    }
}

struct RoundResults: View {
    let game: Game
    let winnerID: Int?

    var body: some View {
        let winner = game.players.first { $0.id == winnerID }
        VStack(spacing: 10) {
            Text(winner.map { "\($0.name) takes round \(game.round)!" } ?? "Round \(game.round) is a draw!")
                .font(.title2.bold())
                .foregroundStyle(winner?.color ?? .primary)
            HStack(spacing: 28) {
                ForEach(game.players) { player in
                    let earned = game.roundEarnings[player.id] ?? RoundEarnings()
                    VStack(spacing: 2) {
                        Text(player.name).font(.headline).foregroundStyle(player.color)
                        Text("+\(earned.total.formatted(.currency(code: "USD").precision(.fractionLength(0))))")
                            .font(.title3.monospacedDigit().bold())
                        Text("damage \(earned.damage.formatted()) · kills \(earned.kills.formatted()) · bonus \(earned.bonus.formatted())")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("\(player.wins) win\(player.wins == 1 ? "" : "s")").font(.caption)
                    }
                }
            }
            Button(game.round >= game.settings.rounds ? "Final results" : "To the shop", systemImage: "cart", action: game.continueAfterRound)
                .buttonStyle(.borderedProminent)
        }
    }
}

struct MatchResults: View {
    let game: Game
    let onQuit: () -> Void

    var body: some View {
        let standings = game.standings
        VStack(spacing: 10) {
            if let champion = standings.first {
                Label("\(champion.name) is the champion!", systemImage: "trophy.fill")
                    .font(.title2.bold())
                    .foregroundStyle(champion.color)
            }
            ForEach(standings) { player in
                HStack {
                    Text(player.name).foregroundStyle(player.color).bold()
                    Spacer()
                    Text("\(player.wins) wins · \(player.kills) kills · \(player.money.formatted(.currency(code: "USD").precision(.fractionLength(0))))")
                        .monospacedDigit()
                }
                .frame(maxWidth: 420)
            }
            HStack {
                Button("Rematch", systemImage: "arrow.clockwise", action: game.newMatch)
                    .buttonStyle(.borderedProminent)
                Button("Main Menu", systemImage: "house", action: onQuit)
                    .buttonStyle(.bordered)
            }
        }
    }
}

/// A round arcade button: hold to build power (the ring fills), release to fire.
struct ArcadeButton: View {
    static let size = 92.0

    let color: Color
    let charge: Double?
    let hapticsEnabled: Bool
    let onPress: () -> Void
    let onRelease: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var isPressed = false

    var body: some View {
        let size = ArcadeButton.size
        let travel = 5.0
        ZStack {
            Circle()
                .trim(from: 0, to: (charge ?? 0) / 100)
                .rotation(.degrees(-90))
                .stroke(AngularGradient(colors: [.yellow, .orange, .red, .yellow], center: .center),
                        style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .frame(width: size + 18, height: size + 18)
                .shadow(color: .orange.opacity(charge == nil ? 0 : 0.8), radius: 6)

            Circle()
                .fill(LinearGradient(colors: [Color(white: 0.28), Color(white: 0.05)], startPoint: .top, endPoint: .bottom))
                .frame(width: size + 6, height: size + 6)
                .shadow(color: .black.opacity(0.5), radius: 4, y: 3)

            Circle()
                .fill(color.mix(with: .black, by: 0.55))
                .frame(width: size - 8, height: size - 8)
                .offset(y: travel)

            ZStack {
                Circle().fill(RadialGradient(
                    colors: [color.mix(with: .white, by: 0.35), color, color.mix(with: .black, by: 0.35)],
                    center: UnitPoint(x: 0.4, y: 0.35), startRadius: 2, endRadius: size * 0.55
                ))
                Ellipse()
                    .fill(LinearGradient(colors: [.white.opacity(0.65), .white.opacity(0)], startPoint: .top, endPoint: .bottom))
                    .frame(width: size * 0.55, height: size * 0.3)
                    .offset(y: -size * 0.2)
                Text("FIRE")
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
                    .shadow(color: .black.opacity(0.4), radius: 1, y: 1)
            }
            .frame(width: size - 8, height: size - 8)
            .brightness(isPressed ? -0.12 : 0)
            .offset(y: isPressed ? travel - 1 : 0)
        }
        .frame(width: size + 20, height: size + 20)
        .saturation(isEnabled ? 1 : 0.2)
        .opacity(isEnabled ? 1 : 0.6)
        .animation(.spring(duration: 0.12), value: isPressed)
        .contentShape(Circle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard !isPressed else { return }
                isPressed = true
                onPress()
            }
            .onEnded { _ in
                isPressed = false
                onRelease()
            })
        .sensoryFeedback(.impact(weight: .heavy, intensity: 1), trigger: isPressed) { _, pressed in pressed && hapticsEnabled }
        .accessibilityLabel("Fire")
        .accessibilityHint("Hold to charge power, release to fire")
    }
}
