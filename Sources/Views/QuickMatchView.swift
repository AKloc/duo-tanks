import SwiftUI

/// Quick match setup. Choices are remembered between launches.
struct QuickMatchView: View {
    let onStart: (MatchSettings) -> Void
    let onBack: () -> Void

    @AppStorage("rounds") private var rounds = 5
    @AppStorage("startingMoney") private var startingMoney = 15_000
    @AppStorage("world") private var world = WorldChoice.random
    @AppStorage("weather") private var weather = WeatherSetting.auto
    @AppStorage("wind") private var wind = WindSetting.normal
    @AppStorage("roughness") private var roughness = Roughness.rolling
    @AppStorage("volume") private var volume = 0.8
    @AppStorage("haptics") private var hapticsEnabled = true
    @AppStorage("music") private var musicEnabled = true
    @AppStorage("opponent") private var versusComputer = false
    @AppStorage("difficulty") private var difficulty = Difficulty.normal
    @AppStorage("handoff") private var handoffEnabled = true

    private static let moneyOptions = [5_000, 15_000, 30_000, 50_000]

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                header
                worldPicker
                section("Opponent") {
                    Picker("Opponent", selection: $versusComputer) {
                        Label("Two players", systemImage: "person.2.fill").tag(false)
                        Label("Vs computer", systemImage: "cpu").tag(true)
                    }
                    .pickerStyle(.segmented)
                    if versusComputer {
                        segmented("Difficulty", selection: $difficulty, options: Difficulty.allCases) { $0.name }
                    } else {
                        Toggle(isOn: $handoffEnabled) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Private turns")
                                Text("Hide your turn and shop until the phone changes hands. On iPhone Duo, fold to pass it over, or lay it flat for tabletop play.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                section("Match") {
                    Stepper(value: $rounds, in: 1...10) {
                        LabeledContent("Rounds", value: "\(rounds)")
                    }
                    LabeledContent("Starting cash") {
                        Picker("Starting cash", selection: $startingMoney) {
                            ForEach(Self.moneyOptions, id: \.self) { amount in
                                Text("$\(amount / 1000)k").tag(amount)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 300)
                    }
                }
                section("Conditions") {
                    segmented("Weather", selection: $weather, options: WeatherSetting.allCases) { $0.name }
                    segmented("Wind", selection: $wind, options: WindSetting.allCases) { $0.name }
                    segmented("Terrain", selection: $roughness, options: Roughness.allCases) { $0.name }
                }
                Button(action: start) {
                    PlateLabel(title: "Start Match", systemImage: "flame.fill", size: .large)
                        .frame(maxWidth: 320)
                }
                .buttonStyle(.plate(.orange, .primary, size: .large))
                .padding(.bottom, 24)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background {
            LinearGradient(stops: ThemeLook.for(world.theme ?? .hills).sky, startPoint: .top, endPoint: .bottom)
                .overlay(Color.black.opacity(0.35))
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.4), value: world)
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack {
            Button(action: onBack) { PlateLabel(title: "Back", systemImage: "chevron.left", size: .small) }
                .buttonStyle(.plate(size: .small))
            Spacer()
            Text("QUICK MATCH")
                .font(.system(size: 30, weight: .black).width(.expanded))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(LinearGradient(colors: [Color(white: 0.97), Color(white: 0.72)], startPoint: .top, endPoint: .bottom))
            Spacer()
            Color.clear.frame(width: 60, height: 1)
        }
        .padding(.top, 20)
    }

    private var worldPicker: some View {
        section("World") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(WorldChoice.allCases) { choice in
                        WorldCard(choice: choice, isSelected: choice == world) { world = choice }
                    }
                }
                .padding(2)
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private func segmented<Option: Hashable>(_ title: String, selection: Binding<Option>, options: [Option], name: @escaping (Option) -> String) -> some View {
        LabeledContent(title) {
            Picker(title, selection: selection) {
                ForEach(options, id: \.self) { Text(name($0)).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 300)
        }
    }

    private func start() {
        onStart(MatchSettings(
            rounds: rounds, startingMoney: startingMoney, world: world, weather: weather,
            wind: wind, roughness: roughness, volume: volume, hapticsEnabled: hapticsEnabled, musicEnabled: musicEnabled,
            computerOpponent: versusComputer ? difficulty : nil
        ))
    }
}

struct WorldCard: View {
    let choice: WorldChoice
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack {
                    if let theme = choice.theme {
                        let look = ThemeLook.for(theme)
                        LinearGradient(stops: look.sky, startPoint: .top, endPoint: .bottom)
                        VStack {
                            Spacer()
                            LinearGradient(colors: [look.ridges[1].color, look.ridges[2].color], startPoint: .top, endPoint: .bottom)
                                .frame(height: 22)
                        }
                    } else {
                        LinearGradient(colors: [.purple, .orange, .blue, .gray], startPoint: .topLeading, endPoint: .bottomTrailing)
                        Image(systemName: "shuffle").font(.title2.bold()).foregroundStyle(.white)
                    }
                }
                .frame(width: 128, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(isSelected ? Color.orange : .white.opacity(0.15), lineWidth: isSelected ? 3 : 1))
                Text(choice.name)
                    .font(.caption.bold())
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
