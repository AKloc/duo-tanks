import SwiftUI

/// The first screen: continue the Tour, play a quick match, or change settings.
struct MainMenuView: View {
    let onContinueTour: (Mission) -> Void
    let onTourMap: () -> Void
    let onQuickMatch: () -> Void
    let onResumeMatch: (() -> Void)?
    let resumeSummary: String?

    @State private var showsSettings = false
    private let progress = TourProgress.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                header
                    .padding(.bottom, 10)
                tourButton
                if let onResumeMatch, let resumeSummary {
                    Button(action: onResumeMatch) {
                        menuLabel("Resume Match", detail: resumeSummary, systemImage: "play.fill")
                    }
                    .buttonStyle(.plate(.orange, .primary, size: .large))
                }
                Button(action: onQuickMatch) {
                    menuLabel("Quick Match", detail: "Two players or vs the computer", systemImage: "flame.fill")
                }
                .buttonStyle(.plate(onResumeMatch == nil ? .orange : .gray, onResumeMatch == nil ? .primary : .secondary, size: .large))
                HStack(spacing: 12) {
                    Button(action: onTourMap) { PlateLabel(title: "Tour Map", systemImage: "map.fill") }
                        .buttonStyle(.plate(.teal))
                    Button { showsSettings = true } label: { PlateLabel(title: "Settings", systemImage: "gearshape.fill") }
                        .buttonStyle(.plate())
                }
            }
            .padding(24)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background {
            LinearGradient(stops: ThemeLook.for(.hills).sky, startPoint: .top, endPoint: .bottom)
                .overlay(Color.black.opacity(0.35))
                .ignoresSafeArea()
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showsSettings) {
            SettingsView()
                .presentationDetents([.medium, .large])
        }
    }

    private var tourButton: some View {
        let next = progress.nextMission
        let started = Mission.all.contains(where: progress.isBeaten)
        return Button { onContinueTour(next) } label: {
            menuLabel(started ? "Continue the Tour" : "Start the Tour",
                      detail: "\(next.chapter.name) · \(next.isBoss ? "Boss" : next.code) · \(next.title)",
                      systemImage: "globe.americas.fill")
        }
        .buttonStyle(.plate(.teal, .primary, size: .large))
    }

    private func menuLabel(_ title: String, detail: String, systemImage: String) -> some View {
        VStack(spacing: 3) {
            PlateLabel(title: title, systemImage: systemImage, size: .large)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text("DUO")
                .font(.system(size: 15, weight: .semibold).width(.expanded))
                .tracking(14)
                .padding(.leading, 14)
                .foregroundStyle(.orange)
            Text("TANKS")
                .font(.system(size: 64, weight: .black).width(.expanded))
                .tracking(-1)
                .foregroundStyle(LinearGradient(colors: [Color(white: 0.97), Color(white: 0.72)], startPoint: .top, endPoint: .bottom))
                .shadow(color: .black.opacity(0.5), radius: 0, y: 3)
            Capsule()
                .fill(.orange)
                .frame(width: 64, height: 3)
                .padding(.top, 2)
            Text("A turn-based artillery duel")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 6)
        }
        .accessibilityElement(children: .combine)
        .padding(.top, 28)
    }
}

/// Sound, feel and two-player options, plus resetting the Tour.
struct SettingsView: View {
    @AppStorage("volume") private var volume = 0.8
    @AppStorage("haptics") private var hapticsEnabled = true
    @AppStorage("music") private var musicEnabled = true
    @AppStorage("handoff") private var handoffEnabled = true
    @AppStorage("layout") private var layout = LayoutSetting.auto
    @Environment(\.dismiss) private var dismiss
    @State private var confirmsReset = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Sound and feel") {
                    LabeledContent("Volume") {
                        Slider(value: $volume, in: 0...1) {
                            Text("Volume")
                        } minimumValueLabel: {
                            Image(systemName: "speaker.fill")
                        } maximumValueLabel: {
                            Image(systemName: "speaker.wave.3.fill")
                        }
                    }
                    Toggle("Music", isOn: $musicEnabled)
                    Toggle("Haptics", isOn: $hapticsEnabled)
                }
                Section {
                    Toggle("Private turns", isOn: $handoffEnabled)
                    Picker("Layout", selection: $layout) {
                        ForEach(LayoutSetting.allCases) { Text($0.name).tag($0) }
                    }
                } header: {
                    Text("Two players")
                } footer: {
                    Text("Private turns hide your turn and shop until the phone changes hands. On iPhone Duo, fold to pass it over, or lay it flat for tabletop play.")
                }
                Section {
                    Button("Reset Tour Progress", role: .destructive) { confirmsReset = true }
                } footer: {
                    Text("Clears every star and locks the Tour back to the first mission.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .confirmationDialog("Reset all Tour progress?", isPresented: $confirmsReset, titleVisibility: .visible) {
                Button("Reset", role: .destructive) { TourProgress.shared.reset() }
            }
        }
        .preferredColorScheme(.dark)
    }
}
