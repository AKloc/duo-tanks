import SwiftUI

struct ControlPanel: View {
    let game: Game
    let hinge: HingeState?
    let onQuit: () -> Void

    @AppStorage("music") private var musicEnabled = true
    @AppStorage("layout") private var layout = LayoutSetting.auto
    @AppStorage("handoff") private var handoffEnabled = true
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        Group {
            switch game.phase {
            case let .roundOver(winnerID):
                RoundResults(game: game, winnerID: winnerID)
            case .matchOver:
                MatchResults(game: game, onQuit: onQuit)
            case .killCam:
                VStack(spacing: 10) {
                    Label("Kill cam", systemImage: "video.fill")
                        .font(.title2.bold())
                        .foregroundStyle(.red)
                    Button(action: game.skipKillCam) { PlateLabel(title: "Skip", systemImage: "forward.fill") }
                        .buttonStyle(.plate(.red))
                }
            default:
                controls(for: game.current)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
        .onChange(of: musicEnabled) { _, enabled in game.setMusicEnabled(enabled) }
    }

    private func controls(for tank: Tank) -> some View {
        let isComputer = game.isComputerTurn
        let isCompact = verticalSizeClass == .compact && hinge?.isPartiallyOpen != true
        let isNarrow = horizontalSizeClass == .compact && verticalSizeClass == .regular
        return Group {
            if isCompact {
                compactControls(for: tank, isComputer: isComputer)
            } else if isNarrow {
                narrowControls(for: tank, isComputer: isComputer)
            } else {
                regularControls(for: tank, isComputer: isComputer)
            }
        }
        .disabled(game.phase != .aiming)
        .allowsHitTesting(!isComputer)
    }

    private func regularControls(for tank: Tank, isComputer: Bool) -> some View {
        HStack(spacing: 20) {
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
                    moneyLabel(for: tank)
                    HealthLabel(health: tank.health, shield: tank.shield)
                    moreMenu
                }

                HStack(spacing: 12) {
                    AngleControl(angle: tank.angle, tint: tank.color, onChange: game.setAngle)
                    Spacer(minLength: 0)
                    weaponMenu(for: tank)
                    gearMenu(for: tank)
                }

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    powerReadout(for: tank, font: .system(.largeTitle, design: .rounded).bold().monospacedDigit())
                    statusText(for: tank, isComputer: isComputer, isCompact: false)
                    Spacer()
                    DrivePad(fuel: tank.inventory.fuel, onStart: game.startDriving, onStop: game.stopDriving)
                }
            }

            fireButton(for: tank, size: 92)
        }
    }

    /// Three stacked rows for narrow screens, like a folded phone held upright.
    private func narrowControls(for tank: Tank, isComputer: Bool) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Circle().fill(tank.color).frame(width: 10, height: 10)
                Text(tank.name).font(.headline)
                Text("R\(game.round)/\(game.settings.rounds)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                moneyLabel(for: tank)
                HealthLabel(health: tank.health, shield: tank.shield).font(.subheadline)
                moreMenu
            }
            HStack(spacing: 8) {
                AngleControl(angle: tank.angle, tint: tank.color, onChange: game.setAngle)
                Spacer(minLength: 0)
                weaponMenu(for: tank, size: .small)
                gearMenu(for: tank)
            }
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 0) {
                    powerReadout(for: tank, font: .system(.title, design: .rounded).bold().monospacedDigit())
                    statusText(for: tank, isComputer: isComputer, isCompact: true).lineLimit(1)
                }
                .fixedSize()
                Spacer(minLength: 0)
                DrivePad(fuel: tank.inventory.fuel, onStart: game.startDriving, onStop: game.stopDriving)
                fireButton(for: tank, size: 72)
            }
        }
    }

    /// One row for short screens, like a regular iPhone held sideways.
    private func compactControls(for tank: Tank, isComputer: Bool) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Circle().fill(tank.color).frame(width: 9, height: 9)
                    Text(tank.name).font(.subheadline.bold())
                }
                HealthLabel(health: tank.health, shield: tank.shield).font(.caption)
                let money = (game.players.first { $0.id == tank.id }?.money ?? 0).formatted(.currency(code: "USD").precision(.fractionLength(0)))
                Text("R\(game.round)/\(game.settings.rounds) · \(money)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .fixedSize()
            AngleControl(angle: tank.angle, tint: tank.color, onChange: game.setAngle)
            weaponMenu(for: tank, size: .small)
                .layoutPriority(1)
            gearMenu(for: tank)
            DrivePad(fuel: tank.inventory.fuel, onStart: game.startDriving, onStop: game.stopDriving)
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 0) {
                powerReadout(for: tank, font: .system(.title2, design: .rounded).bold().monospacedDigit())
                statusText(for: tank, isComputer: isComputer, isCompact: true)
                    .lineLimit(1)
            }
            .fixedSize()
            moreMenu
            fireButton(for: tank, size: 64)
        }
    }

    private func moneyLabel(for tank: Tank) -> some View {
        Text(game.players.first { $0.id == tank.id }?.money ?? 0, format: .currency(code: "USD").precision(.fractionLength(0)))
            .font(.subheadline.monospacedDigit())
            .foregroundStyle(.secondary)
    }

    private var moreMenu: some View {
        Menu {
            Text("\(game.theme.name) · gravity \(Int(game.theme.gravityScale * 100))%")
            Toggle("Music", systemImage: "music.note", isOn: $musicEnabled)
            Picker("Layout", systemImage: "rectangle.split.1x2", selection: $layout) {
                ForEach(LayoutSetting.allCases) { Text($0.name).tag($0) }
            }
            .pickerStyle(.menu)
            if game.players.allSatisfy({ !$0.isComputer }) {
                Toggle("Private Turns", systemImage: "eye.slash", isOn: $handoffEnabled)
            }
            Button("Quit to Title", systemImage: "xmark", role: .destructive, action: onQuit)
        } label: {
            Image(systemName: "ellipsis.circle").font(.title3)
        }
        .accessibilityLabel("Menu")
    }

    private func powerReadout(for tank: Tank, font: Font) -> some View {
        Text(game.chargePower.map { "\(Int($0))%" } ?? "\(Int(tank.power))%")
            .font(font)
            .foregroundStyle(game.chargePower == nil ? .secondary : .primary)
            .contentTransition(.numericText())
    }

    @ViewBuilder
    private func statusText(for tank: Tank, isComputer: Bool, isCompact: Bool) -> some View {
        if isComputer {
            Label(game.computerStatus ?? "Computer's turn", systemImage: "cpu")
                .font(.caption.bold())
                .foregroundStyle(tank.color)
                .transaction { $0.animation = nil }
        } else if tank.isBuried(in: game.terrain), game.chargePower == nil {
            Label(isCompact ? "Buried! Dig out" : "Buried! Fire a Dig Charge upward to dig out", systemImage: "exclamationmark.triangle.fill")
                .font(.caption.bold())
                .foregroundStyle(.orange)
        } else {
            Text(game.chargePower == nil ? (isCompact ? "hold FIRE" : "last power · hold FIRE to charge") : "power")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func fireButton(for tank: Tank, size: Double) -> some View {
        ArcadeButton(color: tank.color, charge: game.chargePower, hapticsEnabled: game.settings.hapticsEnabled, size: size,
                     onPress: game.beginCharge, onRelease: { game.releaseCharge() })
    }

    private func weaponMenu(for tank: Tank, size: PlateLabel.Size = .regular) -> some View {
        Menu {
            ForEach(Weapon.arsenal) { weapon in
                let count = tank.ammoCount(weapon)
                if count != 0 {
                    Button { game.select(weapon) } label: {
                        Text(weapon.name)
                        Text(count.map { "\($0) left" } ?? "Unlimited")
                    }
                }
            }
        } label: {
            PlateSurface(tint: tank.color, prominence: .secondary, size: size) {
                PlateLabel(title: tank.selectedWeapon.name, systemImage: ShopItem.weapon(tank.selectedWeapon).systemImage, size: size)
                    .fixedSize()
            }
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
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
            PlateSurface(tint: tank.color, prominence: .secondary) {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 15, weight: .bold))
                    .overlay(alignment: .topTrailing) {
                        if gear.shields + gear.repairKits + gear.parachutes > 0 {
                            Circle().fill(.orange).frame(width: 7, height: 7).offset(x: 6, y: -5)
                        }
                    }
            }
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .accessibilityLabel("Gear")
    }
}

/// Hold an arrow to drive; shows fuel left.
struct DrivePad: View {
    let fuel: Double
    let onStart: (Double) -> Void
    let onStop: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            arrow("arrowtriangle.left.fill", direction: -1)
            VStack(spacing: 2) {
                Image(systemName: "fuelpump.fill").font(.caption2)
                Text("\(Int(fuel.rounded(.down)))").font(.caption.monospacedDigit().bold())
            }
            .foregroundStyle(fuel > 0 ? .primary : .secondary)
            .frame(minWidth: 30)
            arrow("arrowtriangle.right.fill", direction: 1)
        }
        .disabled(fuel <= 0)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Drive, \(Int(fuel)) fuel")
    }

    private func arrow(_ symbol: String, direction: Double) -> some View {
        HoldButton(symbol: symbol, onPress: { onStart(direction) }, onRelease: onStop)
            .accessibilityLabel(direction < 0 ? "Drive left" : "Drive right")
    }
}

struct HoldButton: View {
    let symbol: String
    let onPress: () -> Void
    let onRelease: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var isPressed = false

    var body: some View {
        PlateSurface(tint: .gray, prominence: .secondary, size: .small, isPressed: isPressed) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .bold))
                .frame(width: 18)
        }
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
    }
}

/// The barrel angle with step plates either side.
struct AngleControl: View {
    let angle: Double
    let tint: Color
    let onChange: (Double) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button { onChange(angle - 1) } label: { Image(systemName: "minus").font(.system(size: 13, weight: .heavy)).frame(width: 14) }
                .buttonStyle(.plate(tint, size: .small))
                .buttonRepeatBehavior(.enabled)
                .accessibilityLabel("Lower barrel")
            VStack(spacing: 0) {
                Text("ANGLE")
                    .font(.system(size: 9, weight: .heavy).width(.expanded))
                    .tracking(1)
                    .foregroundStyle(.secondary)
                Text("\(Int(angle))°")
                    .font(.system(size: 20, weight: .heavy, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText())
            }
            .frame(minWidth: 52)
            Button { onChange(angle + 1) } label: { Image(systemName: "plus").font(.system(size: 13, weight: .heavy)).frame(width: 14) }
                .buttonStyle(.plate(tint, size: .small))
                .buttonRepeatBehavior(.enabled)
                .accessibilityLabel("Raise barrel")
        }
        .accessibilityElement(children: .contain)
        .accessibilityValue("\(Int(angle)) degrees")
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
            Button(action: game.continueAfterRound) {
                PlateLabel(title: game.round >= game.settings.rounds ? "Final results" : "To the shop",
                           systemImage: game.round >= game.settings.rounds ? "trophy.fill" : "cart.fill")
            }
            .buttonStyle(.plate(winner?.color ?? .orange, .primary))
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
                Button(action: game.newMatch) { PlateLabel(title: "Rematch", systemImage: "arrow.clockwise") }
                    .buttonStyle(.plate(standings.first?.color ?? .orange, .primary))
                Button(action: onQuit) { PlateLabel(title: "Main Menu", systemImage: "house.fill") }
                    .buttonStyle(.plate())
            }
        }
    }
}

/// A round arcade button: hold to build power (the ring fills), release to fire.
struct ArcadeButton: View {
    let color: Color
    let charge: Double?
    let hapticsEnabled: Bool
    var size = 92.0
    let onPress: () -> Void
    let onRelease: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var isPressed = false

    var body: some View {
        let size = self.size
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
                    .font(.system(size: 20 * size / 92, weight: .black, design: .rounded))
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
