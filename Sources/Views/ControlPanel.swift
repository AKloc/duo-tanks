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
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
    }

    private func controls(for tank: Tank) -> some View {
        let isAiming = game.phase == .aiming
        return VStack(spacing: 10) {
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

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) {
                    angleStepper(for: tank).frame(width: 220)
                    powerSlider(for: tank).frame(minWidth: 200)
                }
                VStack(spacing: 8) {
                    angleStepper(for: tank)
                    powerSlider(for: tank)
                }
            }

            HStack {
                Menu {
                    ForEach(Weapon.arsenal) { weapon in
                        let count = tank.ammoCount(weapon)
                        Button("\(weapon.name)  \(count.map(String.init) ?? "∞")") { game.select(weapon) }
                            .disabled(count == 0)
                    }
                } label: {
                    Label(tank.selectedWeapon.name, systemImage: "scope")
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Fire!", systemImage: "flame.fill", action: game.fire)
                    .buttonStyle(.borderedProminent)
                    .tint(tank.color)
                    .controlSize(.large)
            }
        }
        .disabled(!isAiming)
    }

    private func angleStepper(for tank: Tank) -> some View {
        Stepper(value: Binding(get: { tank.angle }, set: game.setAngle), in: 0...180) {
            Text("Angle \(Int(tank.angle))°").monospacedDigit().lineLimit(1)
        }
    }

    private func powerSlider(for tank: Tank) -> some View {
        HStack {
            Text("Power").foregroundStyle(.secondary)
            Slider(value: Binding(get: { tank.power }, set: game.setPower), in: 0...100)
            Text("\(Int(tank.power))").monospacedDigit().frame(width: 32, alignment: .trailing)
        }
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
