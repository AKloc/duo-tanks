/// A world's sound: its harmony, scale, tempo and instruments. The song structure, tension layers
/// and fanfare are shared, so every world still swells into a fight the same way.
struct MusicStyle: Equatable, Sendable {
    typealias Chord = MusicSynth.Chord

    enum Lead: Sendable {
        /// Soft and breathy, with a little vibrato.
        case flute
        /// Glassy FM chimes.
        case bell
        /// A pure tone that slides between notes with a wide, wavering vibrato.
        case theremin
        /// A music box: bright and quick to fade.
        case pluck
        /// Nasal and buzzy, like a double reed.
        case reed
    }

    /// Five four-bar sections, arranged into songs by `MusicSynth`.
    let sections: [[Chord]]
    /// The loop when someone's nearly dead.
    let danger: [Chord]
    /// Two octaves of the lead's scale, low to high.
    let scale: [Int]
    let lead: Lead
    let baseBPM: Double
    let bpmRange: Double
    /// How far the pad's second voice is detuned from the first; wider sounds more like a chorus.
    let padDetune: Double
    /// Adds an octave above the pad, for air.
    var padShimmer = false
    /// How much the pad's pitch drifts, for an unsettled, alien feel.
    var padWobble = 0.0
    /// How hard the bass is driven into distortion.
    var bassDrive = 2.2
    /// Semitones above the chord the arpeggio plays.
    var arpOctave = 12
    /// The tension the arpeggio comes in at.
    var arpFrom = 0.45
    /// The tension the kick drum comes in at.
    var drumsFrom = 0.35

    static func `for`(_ theme: WorldTheme) -> MusicStyle {
        switch theme {
        case .hills: .terra
        case .aerie: .aerie
        case .forge: .cinder
        case .snow: .glacia
        case .moon: .rift
        case .desert: .desert
        }
    }

    /// Warm and folky, in A minor.
    static let terra: MusicStyle = {
        let am = Chord(bass: 45, tones: [57, 60, 64]), f = Chord(bass: 41, tones: [53, 57, 60])
        let c = Chord(bass: 48, tones: [55, 60, 64]), g = Chord(bass: 43, tones: [55, 59, 62])
        let dm = Chord(bass: 38, tones: [50, 53, 57]), e = Chord(bass: 40, tones: [56, 59, 64])
        let em = Chord(bass: 40, tones: [55, 59, 64])
        // The half-step lurch from A minor up to B♭ is what makes the danger loop sound like trouble.
        let bb = Chord(bass: 46, tones: [58, 62, 65])
        return MusicStyle(
            sections: [[am, f, c, g], [f, g, em, am], [dm, am, e, am], [c, g, am, f], [am, dm, f, e]],
            danger: [am, bb, am, e],
            scale: [57, 60, 62, 64, 67, 69, 72, 74, 76, 79],
            lead: .flute, baseBPM: 80, bpmRange: 50, padDetune: 1.004
        )
    }()

    /// Floating islands: dreamy D Lydian, shimmering pads and chimes.
    static let aerie: MusicStyle = {
        let dmaj7 = Chord(bass: 38, tones: [57, 61, 66]), e = Chord(bass: 40, tones: [56, 59, 64])
        let bm = Chord(bass: 35, tones: [54, 59, 62]), fsm = Chord(bass: 42, tones: [54, 57, 61])
        let a = Chord(bass: 45, tones: [57, 61, 64]), c = Chord(bass: 48, tones: [55, 60, 64])
        let fs = Chord(bass: 42, tones: [54, 58, 61])
        return MusicStyle(
            sections: [[dmaj7, e, dmaj7, e], [bm, e, dmaj7, a], [fsm, bm, e, e], [dmaj7, a, bm, e], [bm, fsm, c, e]],
            danger: [bm, c, bm, fs],
            scale: [62, 64, 66, 68, 69, 71, 73, 74, 76, 78],
            lead: .bell, baseBPM: 72, bpmRange: 44, padDetune: 1.007,
            padShimmer: true, padWobble: 0.002, bassDrive: 1.2, arpOctave: 24, arpFrom: 0.15
        )
    }()

    /// Lava and forges: heavy E Phrygian dominant, a growling bass and early drums.
    static let cinder: MusicStyle = {
        let e = Chord(bass: 40, tones: [52, 56, 59]), f = Chord(bass: 41, tones: [53, 57, 60])
        let am = Chord(bass: 45, tones: [52, 57, 60]), dm = Chord(bass: 38, tones: [50, 53, 57])
        let g = Chord(bass: 43, tones: [55, 59, 62])
        return MusicStyle(
            sections: [[e, f, e, e], [am, f, e, e], [dm, e, f, e], [am, dm, f, e], [e, f, dm, e]],
            danger: [e, f, e, g],
            scale: [52, 53, 56, 57, 59, 60, 62, 64, 65, 68],
            lead: .reed, baseBPM: 68, bpmRange: 52, padDetune: 1.003,
            bassDrive: 4.5, drumsFrom: 0.15
        )
    }()

    /// Ice: a music box in E minor over glassy, still chords.
    static let glacia: MusicStyle = {
        let em = Chord(bass: 40, tones: [59, 64, 67]), cmaj7 = Chord(bass: 36, tones: [59, 64, 67])
        let g = Chord(bass: 43, tones: [59, 62, 67]), d = Chord(bass: 38, tones: [57, 62, 66])
        let am = Chord(bass: 45, tones: [60, 64, 69]), bm = Chord(bass: 47, tones: [59, 62, 66])
        let f = Chord(bass: 41, tones: [57, 60, 65]), b = Chord(bass: 47, tones: [59, 63, 66])
        return MusicStyle(
            sections: [[em, cmaj7, g, d], [am, em, cmaj7, bm], [em, d, cmaj7, cmaj7], [g, d, am, em], [am, bm, cmaj7, bm]],
            danger: [em, f, em, b],
            scale: [64, 67, 69, 71, 74, 76, 79, 81, 83, 86],
            lead: .pluck, baseBPM: 76, bpmRange: 46, padDetune: 1.002,
            padShimmer: true, bassDrive: 1.4, arpOctave: 24, arpFrom: 0.1
        )
    }()

    /// Deep space: C minor lurching to far-off chords, a theremin and drifting pads.
    static let rift: MusicStyle = {
        let cm = Chord(bass: 36, tones: [55, 60, 63]), ab = Chord(bass: 44, tones: [56, 60, 63])
        let fm = Chord(bass: 41, tones: [56, 60, 65]), e = Chord(bass: 40, tones: [56, 59, 64])
        let abm = Chord(bass: 44, tones: [56, 59, 63]), g = Chord(bass: 43, tones: [55, 59, 62])
        let db = Chord(bass: 37, tones: [56, 61, 65])
        return MusicStyle(
            sections: [[cm, ab, cm, e], [fm, abm, cm, g], [cm, e, ab, abm], [fm, e, cm, cm], [ab, e, fm, g]],
            danger: [cm, db, cm, g],
            scale: [60, 62, 63, 66, 67, 70, 72, 74, 75, 78],
            lead: .theremin, baseBPM: 66, bpmRange: 48, padDetune: 1.01,
            padWobble: 0.008, bassDrive: 1.8, arpFrom: 0.35
        )
    }()

    /// Desert dusk: D Hijaz, with a reedy lead.
    static let desert: MusicStyle = {
        let d = Chord(bass: 38, tones: [54, 57, 62]), eb = Chord(bass: 39, tones: [55, 58, 63])
        let gm = Chord(bass: 43, tones: [55, 58, 62]), cm = Chord(bass: 36, tones: [55, 60, 63])
        return MusicStyle(
            sections: [[d, eb, d, d], [gm, cm, eb, d], [d, gm, eb, d], [cm, eb, d, gm], [gm, eb, cm, d]],
            danger: [d, eb, d, eb],
            scale: [62, 63, 66, 67, 69, 70, 72, 74, 75, 78],
            lead: .reed, baseBPM: 78, bpmRange: 50, padDetune: 1.005, drumsFrom: 0.25
        )
    }()
}
