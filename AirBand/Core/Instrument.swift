import Foundation

enum SoundPalette: Int, CaseIterable, Identifiable {
    case prism, halo, pulse
    var id: Int { rawValue }
    var title: String { ["PRISM", "HALO", "PULSE"][rawValue] }
    var subtitle: String { ["Crystal lead", "Orbital choir", "Neon sequence"][rawValue] }
    var symbol: String { ["diamond", "circle.dotted", "waveform.path"][rawValue] }
}

struct MusicalState {
    var height: Double = 0.5
    var spread: Double = 0.5
    var brightness: Double = 0.25
    var vibrato: Double = 0
    var distortion: Double = 0
    var active = false
    // D minor pentatonic: every gesture stays in key.
    static let notes = [50, 53, 55, 57, 60, 62, 65, 67, 69, 72, 74]
    var midi: Int { Self.notes[Int((height.clamped * Double(Self.notes.count - 1)).rounded())] }
    var frequency: Double { 440 * pow(2, Double(midi - 69) / 12) }
    var volume: Double { active ? 0.12 + spread.clamped * 0.55 : 0 }
    var noteName: String {
        let names = ["C", "C♯", "D", "E♭", "E", "F", "F♯", "G", "A♭", "A", "B♭", "B"]
        return "\(names[midi % 12])\(midi / 12 - 1)"
    }
}

extension Double {
    var clamped: Double { min(1, max(0, isFinite ? self : 0)) }
}

/// Requires a held unilateral eye closure and a fresh open-eye rearm.
/// Bilateral blinks cancel a candidate, even if one eye closes first.
struct WinkDetector {
    private var openSince: Double?
    private var candidateSince: Double?
    private var candidateSide = 0
    private var armed = false
    private var lastFire = -Double.infinity
    mutating func reset() { self = WinkDetector() }
    mutating func update(left: Double, right: Double, time: Double) -> Bool {
        guard left.isFinite, right.isFinite, time.isFinite else { reset(); return false }
        if left < 0.25 && right < 0.25 {
            candidateSince = nil
            candidateSide = 0
            if openSince == nil { openSince = time }
            if time - (openSince ?? time) >= 0.15 { armed = true }
            return false
        }
        openSince = nil
        let side = left > 0.7 && right < 0.25 ? 1 : right > 0.7 && left < 0.25 ? 2 : 0
        guard side != 0 else {
            candidateSince = nil
            candidateSide = 0
            // A blink must fully reopen before another candidate.
            if left > 0.4 && right > 0.4 { armed = false }
            return false
        }
        guard armed, time - lastFire > 0.85 else { return false }
        if candidateSide != side { candidateSide = side; candidateSince = time }
        guard time - (candidateSince ?? time) >= 0.12 else { return false }
        armed = false
        candidateSince = nil
        lastFire = time
        return true
    }
}

/// Palm axis is wrist to middle knuckle in displayed, portrait coordinates.
func palmRotation(wrist: CGPoint, knuckle: CGPoint) -> Double {
    let dx = Double(knuckle.x - wrist.x), dy = Double(wrist.y - knuckle.y)
    guard hypot(dx, dy) > 0.015 else { return 0 }
    return (abs(atan2(dx, dy)) / (.pi / 2)).clamped
}
