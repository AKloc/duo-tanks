import AVFoundation
import Synchronization

/// Synthesized sound effects, panned to where they happen on the battlefield.
@MainActor
final class SoundEngine {
    private static let sampleRate = 44_100.0

    private let engine = AVAudioEngine()
    private let mono = AVAudioFormat(standardFormatWithSampleRate: SoundEngine.sampleRate, channels: 1)!
    private let whistles = WhistleSynth(sampleRate: SoundEngine.sampleRate)
    private var players: [AVAudioPlayerNode] = []
    private var nextPlayer = 0
    private var explosionBuffers: [Int: AVAudioPCMBuffer] = [:]
    private lazy var launchBuffer = makeBuffer(duration: 0.5) { t, noise in
        noise.lowPass(0.15) * exp(-t * 14) + sin(2 * .pi * (120 - 70 * t) * t) * exp(-t * 8)
    }
    private lazy var dirtBuffer = makeBuffer(duration: 0.5) { t, noise in
        noise.lowPass(0.05) * exp(-t * 9) * 1.6
    }
    private lazy var thunderBuffer = makeBuffer(duration: 3.2) { t, noise in
        let crack = t < 0.08 ? noise.lowPass(0.5) * (1 - t / 0.08) * 0.8 : 0
        let roll = noise.lowPass(0.02) * 4 * (1 - exp(-t * 12)) * exp(-t * 1.3) * (0.75 + 0.25 * sin(t * 9))
        return crack + roll
    }

    private lazy var laserBuffer = makeBuffer(duration: 0.45) { t, noise in
        let sweep = 2400 * exp(-t * 5) + 260
        return sin(2 * .pi * sweep * t) * exp(-t * 4) + noise.lowPass(0.4) * 0.25 * exp(-t * 10)
    }

    var volume = 0.8 {
        didSet { engine.mainMixerNode.outputVolume = Float(volume) }
    }

    init() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient)
        for _ in 0..<12 {
            let player = AVAudioPlayerNode()
            engine.attach(player)
            try? engine.connectNode(player, to: engine.mainMixerNode, format: mono)
            players.append(player)
        }
        let stereo = AVAudioFormat(standardFormatWithSampleRate: SoundEngine.sampleRate, channels: 2)!
        let source = SoundEngine.makeSourceNode(format: stereo, synth: whistles)
        engine.attach(source)
        try? engine.connectNode(source, to: engine.mainMixerNode, format: stereo)
        try? engine.start()
    }

    func launch(atX x: Double) {
        play(launchBuffer, atX: x, volume: 0.8)
    }

    func explosion(atX x: Double, radius: Double) {
        let key = Int(radius)
        let buffer = explosionBuffers[key] ?? makeExplosion(radius: radius)
        explosionBuffers[key] = buffer
        play(buffer, atX: x, volume: Float(min(1, 0.55 + radius / 120)))
    }

    func laser(atX x: Double) {
        play(laserBuffer, atX: x, volume: 0.7)
    }

    func thunder(atX x: Double) {
        play(thunderBuffer, atX: x, volume: 0.9)
    }

    func dirt(atX x: Double) {
        play(dirtBuffer, atX: x, volume: 0.9)
    }

    /// Keeps one whistle per shell in flight, pitched by its vertical speed so falling shells whistle down.
    func updateFlights(_ projectiles: [Projectile]) {
        whistles.update(projectiles.map { p in
            WhistleSynth.Target(
                id: p.id,
                frequency: min(max(950 + p.velocity.y * 0.9, 350), 1500),
                pan: SoundEngine.pan(forX: p.position.x)
            )
        })
    }

    private func play(_ buffer: AVAudioPCMBuffer, atX x: Double, volume: Float) {
        guard engine.isRunning else { return }
        let player = players[nextPlayer]
        nextPlayer = (nextPlayer + 1) % players.count
        player.stop()
        player.pan = Float(SoundEngine.pan(forX: x))
        player.volume = volume
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        try? player.playAudio()
    }

    private func makeExplosion(radius: Double) -> AVAudioPCMBuffer {
        let decay = max(2.2, 8 - radius / 16)
        let cutoff = max(0.04, 0.3 - radius / 400)
        return makeBuffer(duration: 0.5 + radius / 50) { t, noise in
            let crack = t < 0.02 ? noise.raw * (1 - t / 0.02) : 0
            let body = noise.lowPass(cutoff) * 2.5 * exp(-t * decay)
            let rumble = sin(2 * .pi * (55 - 15 * t) * t) * 0.6 * exp(-t * decay * 0.7)
            return crack + body + rumble
        }
    }

    private func makeBuffer(duration: Double, _ sample: (Double, inout Noise) -> Double) -> AVAudioPCMBuffer {
        let frames = AVAudioFrameCount(duration * SoundEngine.sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: mono, frameCapacity: frames)!
        buffer.frameLength = frames
        let data = buffer.floatChannelData![0]
        var noise = Noise()
        var peak = 0.0001
        for i in 0..<Int(frames) {
            noise.next()
            let value = sample(Double(i) / SoundEngine.sampleRate, &noise)
            data[i] = Float(value)
            peak = max(peak, abs(value))
        }
        let gain = Float(0.9 / peak)
        for i in 0..<Int(frames) { data[i] *= gain }
        return buffer
    }

    private static func pan(forX x: Double) -> Double {
        min(max((x / Game.worldSize.x) * 2 - 1, -1), 1) * 0.95
    }

    /// Built outside the main actor so the render block isn't main-actor isolated.
    private nonisolated static func makeSourceNode(format: AVAudioFormat, synth: WhistleSynth) -> AVAudioSourceNode {
        AVAudioSourceNode(format: format) { _, _, frameCount, bufferList in
            synth.render(frameCount: Int(frameCount), buffers: UnsafeMutableAudioBufferListPointer(bufferList))
            return noErr
        }
    }
}

/// White noise plus a few one-pole low-pass filters, advanced once per sample.
struct Noise {
    private(set) var raw = 0.0
    private var filtered: [Double: Double] = [:]

    mutating func next() {
        raw = Double.random(in: -1...1)
    }

    mutating func lowPass(_ amount: Double) -> Double {
        let value = filtered[amount, default: 0] + amount * (raw - filtered[amount, default: 0])
        filtered[amount] = value
        return value
    }
}

/// Mixes the in-flight whistles on the audio render thread.
final class WhistleSynth: Sendable {
    struct Target: Sendable {
        let id: UUID
        let frequency: Double
        let pan: Double
    }

    private struct Voice {
        var frequency: Double
        var targetFrequency: Double
        var pan: Double
        var amplitude = 0.0
        var targetAmplitude = 0.0
        var phase = 0.0
    }

    private let sampleRate: Double
    private let voices = Mutex<[UUID: Voice]>([:])

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
    }

    func update(_ targets: [Target]) {
        let amplitude = targets.isEmpty ? 0 : 0.07 / Double(targets.count).squareRoot()
        let live = Set(targets.map(\.id))
        voices.withLock { voices in
            for id in voices.keys where !live.contains(id) {
                voices[id]?.targetAmplitude = 0
            }
            for target in targets {
                var voice = voices[target.id] ?? Voice(frequency: target.frequency, targetFrequency: target.frequency, pan: target.pan)
                voice.targetFrequency = target.frequency
                voice.pan = target.pan
                voice.targetAmplitude = amplitude
                voices[target.id] = voice
            }
        }
    }

    func render(frameCount: Int, buffers: UnsafeMutableAudioBufferListPointer) {
        guard buffers.count >= 2,
              let left = buffers[0].mData?.assumingMemoryBound(to: Float.self),
              let right = buffers[1].mData?.assumingMemoryBound(to: Float.self) else { return }
        for frame in 0..<frameCount {
            left[frame] = 0
            right[frame] = 0
        }
        voices.withLock { voices in
            for id in Array(voices.keys) {
                guard var voice = voices[id] else { continue }
                let angle = (voice.pan + 1) * .pi / 4
                let leftGain = Float(cos(angle))
                let rightGain = Float(sin(angle))
                for frame in 0..<frameCount {
                    voice.frequency += (voice.targetFrequency - voice.frequency) * 0.002
                    voice.amplitude += (voice.targetAmplitude - voice.amplitude) * 0.002
                    voice.phase += voice.frequency / sampleRate
                    if voice.phase >= 1 { voice.phase -= 1 }
                    let sample = Float((sin(2 * .pi * voice.phase) + 0.25 * sin(4 * .pi * voice.phase)) * voice.amplitude)
                    left[frame] += sample * leftGain
                    right[frame] += sample * rightGain
                }
                voices[id] = voice.targetAmplitude == 0 && voice.amplitude < 0.0005 ? nil : voice
            }
        }
    }
}
