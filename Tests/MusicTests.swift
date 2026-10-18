import AVFoundation
import Testing
@testable import DuoTanks

struct MusicTests {
    /// Renders `seconds` of music into a stereo buffer and returns its loudness.
    private func render(_ synth: MusicSynth, seconds: Double) -> Double {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
        let frames = AVAudioFrameCount(seconds * 44_100)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        synth.render(frameCount: Int(frames), buffers: UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList))
        let samples = UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(frames))
        let tail = samples.suffix(Int(0.5 * 44_100))
        return (tail.reduce(0) { $0 + Double($1 * $1) } / Double(tail.count)).squareRoot()
    }

    @Test func musicPlaysWhenEnabled() {
        let synth = MusicSynth(sampleRate: 44_100)
        synth.update(tension: 0.8, enabled: true)
        #expect(render(synth, seconds: 3) > 0.005)
    }

    @Test func musicFadesToSilenceWhenTurnedOff() {
        let synth = MusicSynth(sampleRate: 44_100)
        synth.update(tension: 0.8, enabled: true)
        _ = render(synth, seconds: 2)
        synth.update(tension: 0.8, enabled: false)
        #expect(render(synth, seconds: 4) < 0.0005)
    }

    @Test func higherTensionIsLouderAndBusier() {
        let calm = MusicSynth(sampleRate: 44_100)
        calm.update(tension: 0.1, enabled: true)
        let tense = MusicSynth(sampleRate: 44_100)
        tense.update(tension: 1, enabled: true)
        // Tension eases in, so give it time to arrive.
        #expect(render(tense, seconds: 6) > render(calm, seconds: 6))
    }
}
