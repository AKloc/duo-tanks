import AVFoundation
import Synchronization

/// Something that fills stereo audio buffers on the render thread.
protocol AudioRenderer: Sendable {
    func render(frameCount: Int, buffers: UnsafeMutableAudioBufferListPointer)
}

/// A small generative score. `tension` (0...1) raises the tempo, darkens the chords
/// and layers in drums, bass syncopation, an arpeggio and hi-hats.
final class MusicSynth: AudioRenderer {
    struct Chord: Equatable {
        let bass: Int
        let tones: [Int]
    }

    private static let am = Chord(bass: 45, tones: [57, 60, 64]), f = Chord(bass: 41, tones: [53, 57, 60])
    private static let c = Chord(bass: 48, tones: [55, 60, 64]), g = Chord(bass: 43, tones: [55, 59, 62])
    private static let dm = Chord(bass: 38, tones: [50, 53, 57]), e = Chord(bass: 40, tones: [56, 59, 64])
    private static let em = Chord(bass: 40, tones: [55, 59, 64])

    /// Four-bar sections, arranged into 32-bar songs so nothing repeats too soon.
    private static let sections: [[Chord]] = [
        [am, f, c, g],
        [f, g, em, am],
        [dm, am, e, am],
        [c, g, am, f],
        [am, dm, f, e],
    ]
    private static let calmSong = [0, 1, 0, 3, 1, 3, 0, 2]
    private static let tenseSong = [0, 4, 2, 4, 1, 2, 4, 2]
    /// A minor pentatonic across two octaves, for the lead.
    private static let scale = [57, 60, 62, 64, 67, 69, 72, 74, 76, 79]
    /// Rhythms for the lead, one per bar; `true` starts a note on that sixteenth.
    private static let rhythms: [[Bool]] = [
        [true, false, false, false, true, false, false, false, true, false, true, false, false, false, false, false],
        [true, false, false, true, false, false, true, false, false, false, true, false, true, false, false, false],
        [false, false, true, false, true, false, false, false, false, false, true, false, false, true, false, false],
        [true, false, false, false, false, false, false, false, true, false, false, false, false, false, false, false],
        [true, false, true, false, true, false, false, false, true, false, true, false, true, false, true, false],
    ]
    private static let stepsPerBar = 16
    static let barsPerSong = 32

    static func chord(forBar bar: Int, tense: Bool) -> Chord {
        let song = tense ? tenseSong : calmSong
        let section = sections[song[(bar / 4) % song.count]]
        return section[bar % 4]
    }

    private struct State {
        var tension = 0.2
        var targetTension = 0.2
        var gain = 0.0
        var targetGain = 0.0
        var untilNextStep = 0.0
        var step = 0
        var bar = 0
        var songsPlayed = 0
        var padPhases = [Double](repeating: 0, count: 6)
        var padFrequencies = [Double](repeating: 220, count: 6)
        var lfo = 0.0
        var bassPhase = 0.0, bassFrequency = 110.0, bassEnvelope = 0.0
        var kickPhase = 0.0, kickEnvelope = 0.0
        var hatEnvelope = 0.0, lastNoise = 0.0, noiseSeed: UInt32 = 22_222
        var arpPhase = 0.0, arpFrequency = 440.0, arpEnvelope = 0.0, arpIndex = 0
        var leadPhase = 0.0, leadFrequency = 440.0, leadTarget = 440.0, leadEnvelope = 0.0, leadNote = 5
        var barRhythm = 0
        var melodySeed: UInt32 = 7
    }

    private let sampleRate: Double
    private let state = Mutex(State())

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
    }

    func update(tension: Double, enabled: Bool, level: Double = 0.55) {
        state.withLock {
            $0.targetTension = min(max(tension, 0), 1)
            $0.targetGain = enabled ? level : 0
        }
    }

    func render(frameCount: Int, buffers: UnsafeMutableAudioBufferListPointer) {
        guard buffers.count >= 2,
              let left = buffers[0].mData?.assumingMemoryBound(to: Float.self),
              let right = buffers[1].mData?.assumingMemoryBound(to: Float.self) else { return }
        state.withLock { s in
            for frame in 0..<frameCount {
                s.gain += (s.targetGain - s.gain) * 0.00004
                s.tension += (s.targetTension - s.tension) * 0.00002
                guard s.gain > 0.0005 || s.targetGain > 0 else {
                    left[frame] = 0
                    right[frame] = 0
                    continue
                }

                s.untilNextStep -= 1
                if s.untilNextStep <= 0 {
                    trigger(&s)
                    let bpm = 80 + 50 * s.tension
                    s.untilNextStep += sampleRate * 60 / bpm / 4
                }

                let dt = 1 / sampleRate
                s.lfo += dt * 0.25
                var pad = 0.0
                for i in s.padPhases.indices {
                    s.padPhases[i] = (s.padPhases[i] + s.padFrequencies[i] * dt).truncatingRemainder(dividingBy: 1)
                    pad += sin(2 * .pi * s.padPhases[i]) * (i < 3 ? 1 : 0.5)
                }
                pad *= 0.035 * (1 - 0.35 * s.tension) * (0.85 + 0.15 * sin(2 * .pi * s.lfo))

                s.bassPhase = (s.bassPhase + s.bassFrequency * dt).truncatingRemainder(dividingBy: 1)
                let bass = tanh(2.2 * sin(2 * .pi * s.bassPhase)) * s.bassEnvelope * 0.16
                s.bassEnvelope *= 0.99985

                let kickFrequency = 45 + 110 * s.kickEnvelope * s.kickEnvelope
                s.kickPhase = (s.kickPhase + kickFrequency * dt).truncatingRemainder(dividingBy: 1)
                let kick = sin(2 * .pi * s.kickPhase) * s.kickEnvelope * 0.5
                s.kickEnvelope *= 0.9993

                s.noiseSeed = s.noiseSeed &* 1_664_525 &+ 1_013_904_223
                let noise = Double(s.noiseSeed) / Double(UInt32.max) * 2 - 1
                let hat = (noise - s.lastNoise) * s.hatEnvelope * 0.05
                s.lastNoise = noise
                s.hatEnvelope *= 0.994

                s.arpPhase = (s.arpPhase + s.arpFrequency * dt).truncatingRemainder(dividingBy: 1)
                let arp = sin(2 * .pi * s.arpPhase) * s.arpEnvelope * 0.07
                s.arpEnvelope *= 0.99965

                s.leadFrequency += (s.leadTarget - s.leadFrequency) * 0.002
                let vibrato = 1 + 0.004 * sin(2 * .pi * s.lfo * 22)
                s.leadPhase = (s.leadPhase + s.leadFrequency * vibrato * dt).truncatingRemainder(dividingBy: 1)
                let leadWave = sin(2 * .pi * s.leadPhase) + 0.25 * sin(6 * .pi * s.leadPhase)
                let lead = leadWave * s.leadEnvelope * 0.055 * (1 - 0.4 * s.tension)
                s.leadEnvelope *= 0.99993

                let arpPan = s.arpIndex % 2 == 0 ? 0.35 : 0.65
                let center = pad + bass + kick + lead
                left[frame] = Float((center + hat * 0.4 + arp * (1 - arpPan)) * s.gain)
                right[frame] = Float((center + hat * 0.6 + arp * arpPan) * s.gain)
            }
        }
    }

    private func trigger(_ s: inout State) {
        let tense = s.tension > 0.65
        let beat = s.step
        let chord = Self.chord(forBar: s.bar, tense: tense)
        let isSectionEnd = s.bar % 4 == 3

        if beat == 0 {
            for (i, tone) in chord.tones.enumerated() {
                s.padFrequencies[i] = frequency(tone)
                s.padFrequencies[i + 3] = frequency(tone) * 1.004
            }
            // A new lead rhythm each bar, drawn from a seed that changes every time the song comes around.
            s.melodySeed = UInt32(truncatingIfNeeded: s.bar &* 2_654_435_761 &+ s.songsPlayed &* 40_503 &+ 1)
            s.barRhythm = Int(next(&s.melodySeed) % UInt32(Self.rhythms.count))
        }

        let bassBeats: Set<Int> = s.tension > 0.6 ? [0, 3, 6, 8, 11, 14] : (s.bar % 2 == 0 ? [0, 8] : [0, 6, 8])
        if bassBeats.contains(beat) {
            s.bassFrequency = frequency(chord.bass + (s.tension > 0.6 && beat % 3 == 0 && beat > 0 ? 12 : 0))
            s.bassEnvelope = 1
        }

        let fill = isSectionEnd && beat >= 12 && s.tension > 0.5
        if s.tension > 0.35, beat % (s.tension > 0.6 ? 4 : 8) == 0 || fill {
            s.kickEnvelope = fill ? 0.8 : 1
            s.kickPhase = 0
        }
        if s.tension > 0.55, beat % 2 == 0 && (s.tension > 0.75 || beat % 4 == 2) || fill {
            s.hatEnvelope = 1
        }

        if s.tension > 0.45, beat % (s.tension > 0.8 ? 1 : 2) == 0 {
            let tones = chord.tones.map { $0 + 12 }
            s.arpIndex += 1
            // Up, down, or up-and-back depending on the section.
            let pattern = (s.bar / 4) % 3
            let position = s.arpIndex % (tones.count * 2 - 2)
            let index = switch pattern {
            case 0: s.arpIndex % tones.count
            case 1: tones.count - 1 - s.arpIndex % tones.count
            default: position < tones.count ? position : tones.count * 2 - 2 - position
            }
            s.arpFrequency = frequency(tones[index])
            s.arpEnvelope = 1
        }

        // Lead: a wandering pentatonic line that leans toward the chord, quieter as the drums take over.
        if Self.rhythms[s.barRhythm][beat], s.bar % 8 < 6 || s.tension < 0.5 {
            let leap = Int(next(&s.melodySeed) % 5) - 2
            var note = min(max(s.leadNote + leap, 0), Self.scale.count - 1)
            if beat == 0, let nearest = Self.scale.indices.min(by: { abs(Self.scale[$0] - chord.tones[0] - 12) < abs(Self.scale[$1] - chord.tones[0] - 12) }) {
                note = nearest
            }
            s.leadNote = note
            s.leadTarget = frequency(Self.scale[note])
            s.leadEnvelope = 1
        }

        s.step += 1
        if s.step == Self.stepsPerBar {
            s.step = 0
            s.bar += 1
            if s.bar == Self.barsPerSong {
                s.bar = 0
                s.songsPlayed += 1
            }
        }
    }

    private func next(_ seed: inout UInt32) -> UInt32 {
        seed = seed &* 1_664_525 &+ 1_013_904_223
        return seed >> 8
    }

    private func frequency(_ midi: Int) -> Double {
        440 * pow(2, Double(midi - 69) / 12)
    }
}
