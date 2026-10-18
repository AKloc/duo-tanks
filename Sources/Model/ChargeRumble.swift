import CoreHaptics

/// A low continuous rumble while the fire button is held, growing with power.
/// Capped well below full strength so it's felt in the hand without rattling the table.
@MainActor
final class ChargeRumble {
    private static let baseIntensity: Float = 0.5
    /// Effective intensity runs from 0.5 × 0.25 to 0.5 × 0.85, so roughly 0.13 to 0.43.
    private static let controlRange: ClosedRange<Float> = 0.25...0.85

    private let engine: CHHapticEngine?
    private var player: CHHapticAdvancedPatternPlayer?

    init() {
        engine = CHHapticEngine.capabilitiesForHardware().supportsHaptics ? try? CHHapticEngine() : nil
        engine?.isAutoShutdownEnabled = true
    }

    func start() {
        guard let engine else { return }
        do {
            try engine.start()
            let rumble = CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: ChargeRumble.baseIntensity),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.05),
                ],
                relativeTime: 0.08,
                duration: 30
            )
            player = try engine.makeAdvancedPlayer(with: CHHapticPattern(events: [rumble], parameters: []))
            update(fraction: 0)
            try player?.start(atTime: CHHapticTimeImmediate)
        } catch {
            player = nil
        }
    }

    func update(fraction: Double) {
        let f = Float(min(max(fraction, 0), 1))
        let range = ChargeRumble.controlRange
        try? player?.sendParameters([
            CHHapticDynamicParameter(parameterID: .hapticIntensityControl, value: range.lowerBound + (range.upperBound - range.lowerBound) * f, relativeTime: 0),
            CHHapticDynamicParameter(parameterID: .hapticSharpnessControl, value: 0.25 * f, relativeTime: 0),
        ], atTime: CHHapticTimeImmediate)
    }

    func stop() {
        try? player?.stop(atTime: CHHapticTimeImmediate)
        player = nil
    }
}
