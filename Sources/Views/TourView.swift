import SwiftUI

/// The campaign map: pick a difficulty, a chapter and a mission.
struct TourView: View {
    let onPlay: (Mission, TourDifficulty) -> Void
    let onBack: () -> Void

    @AppStorage("tourDifficulty") private var difficulty = TourDifficulty.normal
    @State private var briefing: Mission?
    private let progress = TourProgress.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                difficultyPicker
                ForEach(Chapter.allCases) { chapter in
                    ChapterCard(chapter: chapter, progress: progress) { briefing = $0 }
                }
            }
            .padding(24)
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity)
        }
        .background(LinearGradient(colors: [Color(red: 0.03, green: 0.05, blue: 0.14), Color(red: 0.12, green: 0.08, blue: 0.24)],
                                   startPoint: .top, endPoint: .bottom).ignoresSafeArea())
        .preferredColorScheme(.dark)
        .sheet(item: $briefing) { mission in
            MissionBriefing(mission: mission, difficulty: difficulty, progress: progress) {
                briefing = nil
                onPlay(mission, difficulty)
            }
            .presentationDetents([.medium, .large])
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            Button(action: onBack) { PlateLabel(title: "Back", systemImage: "chevron.left", size: .small) }
                .buttonStyle(.plate(size: .small))
            Spacer()
            VStack(spacing: 2) {
                Text("THE TOUR")
                    .font(.system(size: 40, weight: .black).width(.expanded))
                    .foregroundStyle(LinearGradient(colors: [Color(white: 0.97), Color(white: 0.72)], startPoint: .top, endPoint: .bottom))
                Text("Five worlds. Five bosses. One tank.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Color.clear.frame(width: 80, height: 1)
        }
    }

    private var difficultyPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Difficulty", selection: $difficulty) {
                ForEach(TourDifficulty.allCases) { Text($0.name).tag($0) }
            }
            .pickerStyle(.segmented)
            Text(difficulty.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }
}

struct ChapterCard: View {
    let chapter: Chapter
    let progress: TourProgress
    let onSelect: (Mission) -> Void

    var body: some View {
        let isOpen = progress.isUnlocked(chapter)
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(chapter.name.uppercased())
                        .font(.system(size: 24, weight: .black).width(.expanded))
                    Text("\(chapter.subtitle) · \(chapter.gravityLabel)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if chapter.isAvailable {
                    Label("\(progress.totalStars(in: chapter))/\(chapter.missions.count * 3)", systemImage: "star.fill")
                        .font(.subheadline.bold().monospacedDigit())
                        .foregroundStyle(.yellow)
                }
            }
            if !chapter.isAvailable {
                Label("Coming soon", systemImage: "hammer.fill")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if !isOpen {
                Label("Beat the boss of the previous world to unlock", systemImage: "lock.fill")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 116), spacing: 10)], spacing: 10) {
                    ForEach(chapter.missions) { mission in
                        MissionTile(mission: mission, stars: progress.stars(for: mission), isUnlocked: progress.isUnlocked(mission)) {
                            onSelect(mission)
                        }
                    }
                }
            }
        }
        .padding(18)
        .background {
            ZStack {
                LinearGradient(stops: ThemeLook.for(chapter.theme).sky, startPoint: .top, endPoint: .bottom)
                Color.black.opacity(chapter.isAvailable && isOpen ? 0.35 : 0.6)
            }
            .clipShape(RoundedRectangle(cornerRadius: 22))
        }
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.12)))
    }
}

struct MissionTile: View {
    let mission: Mission
    let stars: Int
    let isUnlocked: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                Text(mission.isBoss ? "BOSS" : mission.code)
                    .font(.system(size: 13, weight: .heavy).width(.expanded))
                    .foregroundStyle(mission.isBoss ? .orange : .secondary)
                Text(mission.title)
                    .font(.footnote.bold())
                    .multilineTextAlignment(.center)
                    .lineLimit(2, reservesSpace: true)
                if isUnlocked {
                    StarRow(stars: stars, size: 12)
                } else {
                    Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
            .background(.white.opacity(isUnlocked ? 0.08 : 0.03), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(mission.isBoss ? Color.orange.opacity(0.6) : .white.opacity(0.1)))
        }
        .buttonStyle(.plain)
        .disabled(!isUnlocked)
        .opacity(isUnlocked ? 1 : 0.5)
    }
}

struct StarRow: View {
    let stars: Int
    var size = 16.0

    var body: some View {
        HStack(spacing: size * 0.25) {
            ForEach(0..<3, id: \.self) { i in
                Image(systemName: i < stars ? "star.fill" : "star")
                    .font(.system(size: size, weight: .bold))
                    .foregroundStyle(i < stars ? .yellow : .white.opacity(0.3))
            }
        }
        .accessibilityElement()
        .accessibilityLabel("\(stars) of 3 stars")
    }
}

struct MissionBriefing: View {
    let mission: Mission
    let difficulty: TourDifficulty
    let progress: TourProgress
    let onDeploy: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("\(mission.chapter.name.uppercased()) · \(mission.isBoss ? "BOSS" : "MISSION \(mission.code)")")
                    .font(.caption.bold())
                    .foregroundStyle(mission.isBoss ? .orange : .secondary)
                Spacer()
                StarRow(stars: progress.stars(for: mission), size: 14)
            }
            Text(mission.title)
                .font(.system(size: 30, weight: .black).width(.expanded))
            Text(mission.briefing)
                .font(.body)
            VStack(alignment: .leading, spacing: 8) {
                Label(objectiveText, systemImage: "scope")
                Label("Par: \(mission.par) shot\(mission.par == 1 ? "" : "s")", systemImage: "flag.fill")
                Label("Stars: win · win under par · win taking 25 damage or less", systemImage: "star.fill")
                Label(mission.tip, systemImage: "lightbulb.fill")
                    .foregroundStyle(.yellow)
            }
            .font(.callout)
            Spacer(minLength: 0)
            Button(action: onDeploy) {
                PlateLabel(title: "Deploy", systemImage: "flame.fill", size: .large)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plate(mission.isBoss ? .orange : .teal, .primary, size: .large))
        }
        .padding(24)
        .preferredColorScheme(.dark)
    }

    private var objectiveText: String {
        switch mission.objective {
        case .destroyAll: "Destroy every enemy"
        case let .survive(turns): "Survive \(turns) enemy turns, or destroy them all"
        case .trickShot: "Destroy the target with only the ammo you're given"
        }
    }
}

/// The mission's objective at the top of the battlefield, with the briefing for the first few seconds.
struct MissionHUD: View {
    let run: MissionRun
    let showsBriefing: Bool
    let canShowHint: Bool
    let onHint: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            if showsBriefing {
                VStack(spacing: 4) {
                    Text("\(run.mission.isBoss ? "BOSS" : run.mission.code) · \(run.mission.title.uppercased())")
                        .font(.system(size: 15, weight: .black).width(.expanded))
                    Text(run.mission.briefing)
                        .font(.callout)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .frame(maxWidth: 520)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            if canShowHint {
                Button(action: onHint) { PlateLabel(title: "Show me a shot", systemImage: "lightbulb.fill", size: .small) }
                    .buttonStyle(.plate(.yellow, .primary, size: .small))
            }
        }
        .foregroundStyle(.white)
        .animation(.easeInOut, value: showsBriefing)
    }
}
