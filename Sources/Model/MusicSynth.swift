import AVFoundation
import Synchronization

/// Something that fills stereo audio buffers on the render thread.
protocol AudioRenderer: Sendable {
    func render(frameCount: Int, buffers: UnsafeMutableAudioBufferListPointer)
}

/// A small generative score. `tension` (0...1) raises the tempo, darkens the chords
/// and layers in drums, bass syncopation, an arpeggio and hi-hats.
final class MusicSynth: AudioRenderer {
    private struct Chord {
        let bass: Int
        let tones: [Int]
    }

    private static let calm = [Chord(bass: 45, tones: [57, 60, 64]), Chord(bass: 41, tones: [53, 57, 60]),
                               Chord(bass: 48, tones: [55, 60, 64]), Chord(bass: 43, tones: [55, 59, 62])]
    private static let tense = [Chord(bass: 45, tones: [57, 60, 64]), Chord(bass: 41, tones: [53, 57, 60]),
                                Chord(bass: 38, tones: [50, 53, 57]), Chord(bass: 40, tones: [56, 59, 64])]
    private static let stepsPerBar = 16

    private struct State {
        var tension = 0.2
        var targetTension = 0.2
        var gain = 0.0
        var targetGain = 0.0
        var untilNextStep = 0.0
        var step = 0
        var padPhases = [Double](repeating: 0, count: 6)
        var padFrequencies = [Double](repeating: 220, count: 6)
        var lfo = 0.0
        var bassPhase = 0.0, bassFrequency = 110.0, bassEnvelope = 0.0
        var kickPhase = 0.0, kickEnvelope = 0.0
        var hatEnvelope = 0.0, lastNoise = 0.0, noiseSeed: UInt32 = 22_222
        var arpPhase = 0.0, arpFrequency = 440.0, arpEnvelope = 0.0, arpIndex = 0
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

                let arpPan = s.arpIndex % 2 == 0 ? 0.35 : 0.65
                let center = pad + bass + kick
                left[frame] = Float((center + hat * 0.4 + arp * (1 - arpPan)) * s.gain)
                right[frame] = Float((center + hat * 0.6 + arp * arpPan) * s.gain)
            }
        }
    }

    private func trigger(_ s: inout State) {
        let progression = s.tension > 0.65 ? Self.tense : Self.calm
        let bar = s.step / Self.stepsPerBar
        let beat = s.step % Self.stepsPerBar
        let chord = progression[bar % progression.count]

        if beat == 0 {
            for (i, tone) in chord.tones.enumerated() {
                s.padFrequencies[i] = frequency(tone)
                s.padFrequencies[i + 3] = frequency(tone) * 1.004
            }
        }

        let bassBeats: Set<Int> = s.tension > 0.6 ? [0, 3, 6, 8, 11, 14] : [0, 8]
        if bassBeats.contains(beat) {
            s.bassFrequency = frequency(chord.bass + (s.tension > 0.6 && beat % 3 == 0 && beat > 0 ? 12 : 0))
            s.bassEnvelope = 1
        }

        if s.tension > 0.35, beat % (s.tension > 0.6 ? 4 : 8) == 0 {
            s.kickEnvelope = 1
            s.kickPhase = 0
        }

        if s.tension > 0.55, beat % 2 == 0, s.tension > 0.75 || beat % 4 == 2 {
            s.hatEnvelope = 1
        }

        if s.tension > 0.45, beat % (s.tension > 0.8 ? 1 : 2) == 0 {
            let tones = chord.tones.map { $0 + 12 }
            s.arpIndex += 1
            s.arpFrequency = frequency(tones[s.arpIndex % tones.count])
            s.arpEnvelope = 1
        }

        s.step = (s.step + 1) % (Self.stepsPerBar * progression.count)
    }

    private func frequency(_ midi: Int) -> Double {
        440 * pow(2, Double(midi - 69) / 12)
    }
}
