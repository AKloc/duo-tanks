import SwiftUI

struct ControlPanel: View {
    let game: Game
    let hinge: HingeState?

    var body: some View {
        Group {
            if case let .gameOver(winnerID) = game.phase {
                gameOver(winner: winnerID.map { game.tanks[$0] })
            } else {
                controls(for: game.current)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
    }

    private func controls(for tank: Tank) -> some View {
        HStack(spacing: 20) {
            VStack(spacing: 12) {
                HStack {
                    Circle().fill(tank.color).frame(width: 12, height: 12)
                    Text("\(tank.name)'s turn").font(.headline)
                    Spacer()
                    if hinge?.isPartiallyOpen == true {
                        Label("Hinge aiming", systemImage: "laptopcomputer")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("HP \(Int(tank.health.rounded(.up)))").monospacedDigit()
                }

                HStack(spacing: 16) {
                    Stepper(value: Binding(get: { tank.angle }, set: game.setAngle), in: 0...180) {
                        Text("Angle \(Int(tank.angle))°").monospacedDigit().lineLimit(1)
                    }
                    .frame(maxWidth: 220)
                    Spacer(minLength: 0)
                    Menu {
                        ForEach(Weapon.arsenal) { weapon in
                            let count = tank.ammoCount(weapon)
                            Button("\(weapon.name)  \(count.map(String.init) ?? "∞")") { game.select(weapon) }
                                .disabled(count == 0)
                        }
                    } label: {
                        Label(tank.selectedWeapon.name, systemImage: "scope").lineLimit(1)
                    }
                    .buttonStyle(.bordered)
                }

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(game.chargePower.map { "\(Int($0))%" } ?? "\(Int(tank.power))%")
                        .font(.system(.largeTitle, design: .rounded).bold().monospacedDigit())
                        .foregroundStyle(game.chargePower == nil ? .secondary : .primary)
                        .contentTransition(.numericText())
                    Text(game.chargePower == nil ? "last power · hold FIRE to charge" : "power")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }

            ArcadeButton(color: tank.color, charge: game.chargePower, onPress: game.beginCharge, onRelease: game.releaseCharge)
        }
        .disabled(game.phase != .aiming)
    }

    private func gameOver(winner: Tank?) -> some View {
        VStack(spacing: 12) {
            Text(winner.map { "\($0.name) wins!" } ?? "Everybody loses!")
                .font(.title.bold())
                .foregroundStyle(winner?.color ?? .primary)
            Button("New Game", systemImage: "arrow.clockwise", action: game.newGame)
                .buttonStyle(.borderedProminent)
        }
    }
}

/// A round arcade button: hold to build power (the ring fills), release to fire.
struct ArcadeButton: View {
    static let size = 92.0

    let color: Color
    let charge: Double?
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
        .sensoryFeedback(.impact(weight: .heavy, intensity: 1), trigger: isPressed) { _, pressed in pressed }
        .accessibilityLabel("Fire")
        .accessibilityHint("Hold to charge power, release to fire")
    }
}
