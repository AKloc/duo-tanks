import AVFoundation
import Testing
@testable import DuoTanks

struct MusicTests {
    /// Renders `seconds` of music into a stereo buffer and returns its loudness, or with `brightness`
    /// the energy of the sample-to-sample change, which drums and hi-hats dominate.
    private func render(_ synth: MusicSynth, seconds: Double, brightness: Bool = false) -> Double {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
        let frames = AVAudioFrameCount(seconds * 44_100)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        synth.render(frameCount: Int(frames), buffers: UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList))
        let samples = UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(frames))
        let tail = Array(samples.suffix(Int((brightness ? 3 : 0.5) * 44_100)))
        let values = brightness ? zip(tail.dropFirst(), tail).map { $0 - $1 } : tail
        return (values.reduce(0) { $0 + Double($1 * $1) } / Double(values.count)).squareRoot()
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

    @Test(arguments: WorldTheme.allCases)
    func theSongRunsMuchLongerThanFourBarsBeforeRepeating(_ theme: WorldTheme) {
        for tense in [false, true] {
            let song = (0..<MusicSynth.barsPerSong).map { MusicSynth.chord(forBar: $0, tense: tense, style: .for(theme)) }
            #expect(Array(song[0..<4]) != Array(song[4..<8]))
            #expect(Array(song[0..<8]) != Array(song[8..<16]))
            #expect(Array(song[0..<16]) != Array(song[16..<32]))
        }
    }

    @Test func dangerAddsTheDriveLayer() {
        let normal = MusicSynth(sampleRate: 44_100)
        normal.update(tension: 0.6, enabled: true)
        let danger = MusicSynth(sampleRate: 44_100)
        danger.update(tension: 0.6, enabled: true, danger: true)
        #expect(render(danger, seconds: 6, brightness: true) > render(normal, seconds: 6, brightness: true) * 1.5)
    }

    @Test func theFanfarePlaysAndHandsBackToTheScore() {
        let synth = MusicSynth(sampleRate: 44_100)
        synth.update(tension: 0.1, enabled: true)
        _ = render(synth, seconds: 1)
        synth.playFanfare()
        #expect(render(synth, seconds: 3) > 0.005)
        // Six bars at 112 bpm is under 13 seconds; afterwards the regular music carries on.
        #expect(render(synth, seconds: 14) > 0.002)
    }

    @Test func higherTensionIsLouderAndBusier() {
        let calm = MusicSynth(sampleRate: 44_100)
        calm.update(tension: 0.1, enabled: true)
        let tense = MusicSynth(sampleRate: 44_100)
        tense.update(tension: 1, enabled: true)
        // Tension eases in, so give it time to arrive.
        #expect(render(tense, seconds: 6) > render(calm, seconds: 6))
    }

    @Test(arguments: WorldTheme.allCases)
    func everyWorldHasMusic(_ theme: WorldTheme) {
        let style = MusicStyle.for(theme)
        #expect(style.sections.count == 5 && style.sections.allSatisfy { $0.count == 4 })
        #expect(style.danger.count == 4)
        #expect(style.scale.count == 10 && style.scale == style.scale.sorted())
        let synth = MusicSynth(sampleRate: 44_100)
        synth.update(tension: 0.6, enabled: true, style: style)
        #expect(render(synth, seconds: 3) > 0.005)
    }

    @Test func worldsSoundDifferent() {
        let styles = WorldTheme.allCases.map(MusicStyle.for)
        for (i, a) in styles.enumerated() {
            for b in styles.dropFirst(i + 1) {
                #expect(a.sections != b.sections || a.lead != b.lead)
            }
        }
        #expect(MusicStyle.for(.aerie).lead == .bell)
        #expect(MusicStyle.for(.moon).lead == .theremin)
    }
}
