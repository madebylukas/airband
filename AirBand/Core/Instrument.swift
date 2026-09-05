import Foundation

enum SoundPalette: Int { case prism }

enum PerformanceMode: Int, CaseIterable, Identifiable {
    case free, song, drums, jam
    var id: Int { rawValue }
    var title: String { ["Free", "Song", "Drums", "Jam"][rawValue] }
    var symbol: String { ["waveform", "music.note.list", "circle.grid.cross", "hand.raised.fingers.spread"][rawValue] }
}

enum HandSide: String, CaseIterable, Identifiable, Hashable {
    case left, right
    var id: String { rawValue }
}

func performerHandSide(fromObserved side: HandSide?) -> HandSide? {
    switch side {
    case .left: return .right
    case .right: return .left
    case nil: return nil
    }
}

func performerHandSide(atDisplayedX x: CGFloat) -> HandSide {
    x < 0.5 ? .right : .left
}

enum HandJoint: Int, CaseIterable {
    case wrist
    case thumbCMC, thumbMP, thumbIP, thumbTip
    case indexMCP, indexPIP, indexDIP, indexTip
    case middleMCP, middlePIP, middleDIP, middleTip
    case ringMCP, ringPIP, ringDIP, ringTip
    case littleMCP, littlePIP, littleDIP, littleTip
}

enum FingerName: Int, CaseIterable, Identifiable, Hashable {
    case thumb, index, middle, ring, little
    var id: Int { rawValue }
    var tipJoint: HandJoint { [.thumbTip, .indexTip, .middleTip, .ringTip, .littleTip][rawValue] }
    var drumName: String { ["KICK", "SNARE", "HAT", "CRASH", "COWBELL"][rawValue] }
}

struct FingerKey: Hashable {
    let side: HandSide
    let finger: FingerName
}

struct HandPoseSample: Identifiable {
    let side: HandSide
    var points: [CGPoint?]
    var xyRotation: Double
    var zTilt: Double
    var openness: Double
    var fingerCurls: [Double]
    var id: HandSide { side }

    init(
        side: HandSide,
        points: [CGPoint?],
        xyRotation: Double = 0,
        zTilt: Double = 0,
        openness: Double = 0,
        fingerCurls: [Double] = []
    ) {
        self.side = side
        self.points = points.count == HandJoint.allCases.count
            ? points
            : Array(points.prefix(HandJoint.allCases.count)) + Array(repeating: nil, count: max(0, HandJoint.allCases.count - points.count))
        self.xyRotation = xyRotation.clamped
        self.zTilt = zTilt.clamped
        self.openness = openness.clamped
        self.fingerCurls = FingerName.allCases.indices.map { index in
            fingerCurls.indices.contains(index) ? fingerCurls[index].clamped : 0
        }
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

    func curl(_ finger: FingerName) -> Double { fingerCurls[finger.rawValue] }
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
    var drumVolume: Double = 0.72
    var melodyVolume: Double = 0.72
    var metronomeEnabled = false
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

struct FingerStrikeDetector {
    private var armed = Array(repeating: false, count: FingerName.allCases.count)
    private var previous = Array(repeating: 0.0, count: FingerName.allCases.count)
    private var lastFire = Array(repeating: -Double.infinity, count: FingerName.allCases.count)
    private var previousTime: Double?
    private(set) var held: Set<FingerName> = []

    mutating func reset() { self = FingerStrikeDetector() }

    mutating func update(curls: [Double], enabled: Bool, time: Double) -> [FingerName] {
        guard time.isFinite else { reset(); return [] }
        if !enabled { held.removeAll() }
        let dt = previousTime.map { min(0.2, max(1.0 / 120.0, time - $0)) }
        var strikes: [FingerName] = []
        for finger in FingerName.allCases {
            let index = finger.rawValue
            let curl = curls.indices.contains(index) ? curls[index].clamped : 0
            let delta = curl - previous[index]
            let velocity = dt.map { delta / $0 } ?? 0
            let fastCurl = curl >= 0.38 && previous[index] < 0.38 && delta >= 0.12 && velocity >= 2.0
            let deliberateCurl = curl >= 0.48 && previous[index] < 0.48
            if curl < 0.30 {
                armed[index] = true
                held.remove(finger)
            }
            if enabled, armed[index], fastCurl || deliberateCurl, time - lastFire[index] > 0.11 {
                armed[index] = false
                lastFire[index] = time
                held.insert(finger)
                strikes.append(finger)
            }
            previous[index] = curl
        }
        previousTime = time
        return strikes
    }
}

func mouthExpression(_ jaw: Double) -> Double {
    sqrt(((jaw - 0.08) / 0.54).clamped)
}

func fistDistortion(_ curls: [Double]) -> Double {
    let fingers = curls.prefix(FingerName.allCases.count)
    guard fingers.count >= 3 else { return 0 }
    let average = fingers.map(\.clamped).reduce(0, +) / Double(fingers.count)
    return pow(((average - 0.22) / 0.70).clamped, 1.3)
}

struct MouthOpenDetector {
    private var armed = false
    private var candidateSince: Double?
    private var lastFire = -Double.infinity

    mutating func reset() { self = MouthOpenDetector() }

    mutating func update(openness: Double, time: Double) -> Bool {
        guard openness.isFinite, time.isFinite else { reset(); return false }
        if openness < 0.20 {
            armed = true
            candidateSince = nil
            return false
        }
        guard armed, openness > 0.36, time - lastFire > 0.65 else {
            if openness < 0.30 { candidateSince = nil }
            return false
        }
        if candidateSince == nil { candidateSince = time }
        guard time - (candidateSince ?? time) >= 0.04 else { return false }
        armed = false
        candidateSince = nil
        lastFire = time
        return true
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
        if left < 0.36 && right < 0.36 {
            candidateSince = nil; candidateSide = nil
            if openSince == nil { openSince = time }
            if time - (openSince ?? time) >= 0.08 { armed = true }
            return nil
        }
        openSince = nil
        if left > 0.48, right > 0.48 {
            candidateSince = nil; candidateSide = nil
            armed = false
            return nil
        }
        let side: WinkSide? = left > 0.52 && right < 0.42 && left - right > 0.25
            ? .left
            : right > 0.52 && left < 0.42 && right - left > 0.25 ? .right : nil
        guard let side else {
            candidateSince = nil; candidateSide = nil
            return nil
        }
        guard armed, time - lastFire > 0.55 else { return nil }
        if candidateSide != side { candidateSide = side; candidateSince = time }
        guard time - (candidateSince ?? time) >= 0.045 else { return nil }
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

func relativePalmZTilt(normal: SIMD3<Float>, neutral: SIMD3<Float>) -> Double {
    let normalLength = sqrt(normal.x * normal.x + normal.y * normal.y + normal.z * normal.z)
    let neutralLength = sqrt(neutral.x * neutral.x + neutral.y * neutral.y + neutral.z * neutral.z)
    guard normalLength > 0.00001, neutralLength > 0.00001 else { return 0 }
    let dot = (normal.x * neutral.x + normal.y * neutral.y + normal.z * neutral.z) / (normalLength * neutralLength)
    return ((1 - Double(min(1, max(-1, dot)))) * 0.5).clamped
}

func normalizedFingerCurl(_ points: [CGPoint]) -> Double {
    guard points.count == 4 else { return 0 }
    func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
        Double(hypot(a.x - b.x, a.y - b.y))
    }
    func bend(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> Double {
        let first = CGVector(dx: a.x - b.x, dy: a.y - b.y)
        let second = CGVector(dx: c.x - b.x, dy: c.y - b.y)
        let denominator = hypot(first.dx, first.dy) * hypot(second.dx, second.dy)
        guard denominator > 0.001 else { return 0 }
        let cosine = min(1, max(-1, (first.dx * second.dx + first.dy * second.dy) / denominator))
        return 1 - Double(acos(cosine) / .pi)
    }
    let strongestBend = max(bend(points[0], points[1], points[2]), bend(points[1], points[2], points[3]))
    let pathLength = distance(points[0], points[1]) + distance(points[1], points[2]) + distance(points[2], points[3])
    let compression = pathLength > 0.001 ? 1 - distance(points[0], points[3]) / pathLength : 0
    return ((max(strongestBend, compression * 1.25) - 0.08) / 0.55).clamped
}

extension Double {
    var clamped: Double { min(1, max(0, isFinite ? self : 0)) }
}

extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(range.upperBound, Swift.max(range.lowerBound, self))
    }
}
