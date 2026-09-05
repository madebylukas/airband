import Foundation

enum SoundPalette: Int, CaseIterable, Identifiable {
    case prism, halo, pulse
    var id: Int { rawValue }
    var title: String { ["PRISM", "HALO", "PULSE"][rawValue] }
    var subtitle: String { ["Crystal lead", "Orbital choir", "Neon sequence"][rawValue] }
    var symbol: String { ["diamond", "circle.dotted", "waveform.path"][rawValue] }
}

enum PerformanceMode: Int, CaseIterable, Identifiable {
    case free, song, drums
    var id: Int { rawValue }
    var title: String { ["Free", "Song", "Drums"][rawValue] }
    var symbol: String { ["waveform", "music.note.list", "circle.grid.cross"][rawValue] }
}

enum HandSide: String, CaseIterable, Identifiable {
    case left, right
    var id: String { rawValue }
}

enum HandJoint: Int, CaseIterable {
    case wrist
    case thumbCMC, thumbMP, thumbIP, thumbTip
    case indexMCP, indexPIP, indexDIP, indexTip
    case middleMCP, middlePIP, middleDIP, middleTip
    case ringMCP, ringPIP, ringDIP, ringTip
    case littleMCP, littlePIP, littleDIP, littleTip
}

struct HandPoseSample: Identifiable {
    let side: HandSide
    var points: [CGPoint?]
    var xyRotation: Double
    var zTilt: Double
    var openness: Double
    var id: HandSide { side }

    init(side: HandSide, points: [CGPoint?], xyRotation: Double = 0, zTilt: Double = 0, openness: Double = 0) {
        self.side = side
        self.points = points.count == HandJoint.allCases.count
            ? points
            : Array(points.prefix(HandJoint.allCases.count)) + Array(repeating: nil, count: max(0, HandJoint.allCases.count - points.count))
        self.xyRotation = xyRotation.clamped
        self.zTilt = zTilt.clamped
        self.openness = openness.clamped
    }

    subscript(_ joint: HandJoint) -> CGPoint? {
        points.indices.contains(joint.rawValue) ? points[joint.rawValue] : nil
    }

    var center: CGPoint {
        if let middle = self[.middleMCP] { return middle }
        let visible = points.compactMap { $0 }
        guard !visible.isEmpty else { return CGPoint(x: 0.5, y: 0.5) }
        return CGPoint(
            x: visible.map(\.x).reduce(0, +) / CGFloat(visible.count),
            y: visible.map(\.y).reduce(0, +) / CGFloat(visible.count)
        )
    }
}

struct MusicalState {
    var height: Double = 0.5
    var horizontal: Double = 0.5
    var spread: Double = 0.5
    var brightness: Double = 0.25
    var vibrato: Double = 0
    var distortion: Double = 0
    var muffle: Double = 0
    var space: Double = 0
    var tempo: Double = 108
    var scaleIndex = 2
    var octaveIndex = 1
    var rootIndex = 5
    var active = false

    static let pentatonic = [0, 3, 5, 7, 10]
    var midi: Int { 38 + Self.pentatonic[scaleIndex.clamped(to: 0...4)] + octaveIndex.clamped(to: 0...2) * 12 }
    var songRootMidi: Int { 36 + rootIndex.clamped(to: 0...11) + octaveIndex.clamped(to: 0...2) * 12 }
    var frequency: Double { Self.frequency(for: midi) }
    var songRootFrequency: Double { Self.frequency(for: songRootMidi) }
    var volume: Double { active ? 0.16 + spread.clamped * 0.48 : 0 }
    var noteName: String { Self.noteName(midi) }
    var keyName: String { Self.noteName(songRootMidi).filter { !$0.isNumber } + "m" }

    static func frequency(for midi: Int) -> Double { 440 * pow(2, Double(midi - 69) / 12) }

    private static func noteName(_ midi: Int) -> String {
        let names = ["C", "C♯", "D", "E♭", "E", "F", "F♯", "G", "A♭", "A", "B♭", "B"]
        return "\(names[(midi % 12 + 12) % 12])\(midi / 12 - 1)"
    }
}

struct HysteresisQuantizer {
    private(set) var index: Int
    let count: Int
    let margin: Double

    init(count: Int, initial: Int, margin: Double = 0.07) {
        self.count = max(1, count)
        self.index = initial.clamped(to: 0...max(0, count - 1))
        self.margin = max(0, margin)
    }

    mutating func update(_ value: Double) -> Int {
        let unit = value.clamped * Double(count)
        if unit < Double(index) - margin || unit > Double(index + 1) + margin {
            index = min(count - 1, max(0, Int(unit)))
        }
        return index
    }
}

private struct OneEuroScalar {
    var filtered: Double?
    var derivative: Double = 0
    var raw: Double?
    var time: Double?

    mutating func update(_ value: Double, time newTime: Double, minCutoff: Double, beta: Double) -> Double {
        guard let oldTime = time, let oldRaw = raw, let oldFiltered = filtered else {
            filtered = value; raw = value; time = newTime
            return value
        }
        let dt = min(0.2, max(1.0 / 120.0, newTime - oldTime))
        let rawDerivative = (value - oldRaw) / dt
        derivative = lowPass(rawDerivative, previous: derivative, alpha: alpha(cutoff: 1, dt: dt))
        let cutoff = minCutoff + beta * abs(derivative)
        let result = lowPass(value, previous: oldFiltered, alpha: alpha(cutoff: cutoff, dt: dt))
        filtered = result; raw = value; time = newTime
        return result
    }

    private func alpha(cutoff: Double, dt: Double) -> Double {
        let tau = 1 / (2 * Double.pi * cutoff)
        return 1 / (1 + tau / dt)
    }

    private func lowPass(_ value: Double, previous: Double, alpha: Double) -> Double {
        alpha * value + (1 - alpha) * previous
    }
}

struct OneEuroPointFilter {
    private var x = OneEuroScalar()
    private var y = OneEuroScalar()

    mutating func update(_ point: CGPoint, time: Double) -> CGPoint {
        CGPoint(
            x: x.update(Double(point.x), time: time, minCutoff: 1.7, beta: 0.14),
            y: y.update(Double(point.y), time: time, minCutoff: 1.7, beta: 0.14)
        )
    }
}

enum WinkSide: Equatable { case left, right }

struct WinkDetector {
    private var openSince: Double?
    private var candidateSince: Double?
    private var candidateSide: WinkSide?
    private var armed = false
    private var lastFire = -Double.infinity

    mutating func reset() { self = WinkDetector() }

    mutating func update(left: Double, right: Double, time: Double) -> WinkSide? {
        guard left.isFinite, right.isFinite, time.isFinite else { reset(); return nil }
        if left < 0.25 && right < 0.25 {
            candidateSince = nil; candidateSide = nil
            if openSince == nil { openSince = time }
            if time - (openSince ?? time) >= 0.15 { armed = true }
            return nil
        }
        openSince = nil
        let side: WinkSide? = left > 0.7 && right < 0.25 ? .left : right > 0.7 && left < 0.25 ? .right : nil
        guard let side else {
            candidateSince = nil; candidateSide = nil
            if left > 0.4 && right > 0.4 { armed = false }
            return nil
        }
        guard armed, time - lastFire > 0.85 else { return nil }
        if candidateSide != side { candidateSide = side; candidateSince = time }
        guard time - (candidateSince ?? time) >= 0.12 else { return nil }
        armed = false; candidateSince = nil; candidateSide = nil; lastFire = time
        return side
    }
}

func palmXYRotation(indexKnuckle: CGPoint, littleKnuckle: CGPoint) -> Double {
    let dx = Double(littleKnuckle.x - indexKnuckle.x)
    let dy = Double(littleKnuckle.y - indexKnuckle.y)
    guard hypot(dx, dy) > 0.015 else { return 0 }
    var angle = abs(atan2(dy, dx))
    if angle > .pi / 2 { angle = .pi - angle }
    return (angle / (.pi / 2)).clamped
}

extension Double {
    var clamped: Double { min(1, max(0, isFinite ? self : 0)) }
}

extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(range.upperBound, Swift.max(range.lowerBound, self))
    }
}
