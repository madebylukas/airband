import Foundation

@main
struct CoreTests {
    static func main() {
        var checks = 0
        func expect(_ value: @autoclosure () -> Bool, _ label: String) {
            checks += 1
            guard value() else { fatalError("FAILED: \(label)") }
            print("PASS \(label)")
        }

        var state = MusicalState()
        expect(state.volume == 0, "inactive state is silent")
        state.active = true
        state.scaleIndex = 0; state.octaveIndex = 0
        expect(state.midi == 38, "free mode starts from D2")
        state.scaleIndex = 4; state.octaveIndex = 2
        expect(state.midi == 72, "free mode remains inside its musical range")
        state.rootIndex = 0; state.octaveIndex = 1
        expect(state.songRootMidi == 48 && state.keyName == "Cm", "song key and octave map together")
        expect(abs(MusicalState.frequency(for: 69) - 440) < 0.001, "concert A tuning is accurate")
        state.spread = 10
        expect(state.volume <= 0.64, "gain stays bounded")

        var latch = HysteresisQuantizer(count: 5, initial: 2)
        expect(latch.update(0.59) == 2, "pitch latch rejects boundary jitter")
        expect(latch.update(0.7) == 3, "pitch latch accepts deliberate movement")

        var filter = OneEuroPointFilter()
        let start = filter.update(CGPoint(x: 0.5, y: 0.5), time: 0)
        let jitter = filter.update(CGPoint(x: 0.51, y: 0.49), time: 0.05)
        expect(start.x == 0.5 && start.y == 0.5, "point filter preserves first sample")
        expect(jitter.x < 0.51 && jitter.y > 0.49, "point filter damps small jitter")
        let movement = filter.update(CGPoint(x: 0.9, y: 0.2), time: 0.10)
        expect(movement.x > jitter.x, "point filter follows intentional movement")

        expect(palmXYRotation(indexKnuckle: CGPoint(x: 100, y: 200), littleKnuckle: CGPoint(x: 300, y: 200)) == 0, "horizontal knuckle axis is neutral")
        expect(palmXYRotation(indexKnuckle: CGPoint(x: 100, y: 100), littleKnuckle: CGPoint(x: 100, y: 300)) == 1, "vertical knuckle axis has full effect")
        let diagonal = palmXYRotation(indexKnuckle: CGPoint(x: 100, y: 100), littleKnuckle: CGPoint(x: 300, y: 300))
        expect(abs(diagonal - 0.5) < 0.001, "diagonal knuckle axis has half effect")
        let neutralNormal = SIMD3<Float>(0, 1, 0)
        expect(relativePalmZTilt(normal: neutralNormal, neutral: neutralNormal) == 0, "flat starting palm is neutral in depth")
        expect(relativePalmZTilt(normal: SIMD3<Float>(0, 0, 1), neutral: neutralNormal) == 0.5, "quarter palm flip has half depth effect")
        expect(relativePalmZTilt(normal: SIMD3<Float>(0, -1, 0), neutral: neutralNormal) == 1, "upward palm flip has full depth effect")
        let straightFinger = [CGPoint(x: 0, y: 3), CGPoint(x: 0, y: 2), CGPoint(x: 0, y: 1), CGPoint(x: 0, y: 0)]
        let curledFinger = [CGPoint(x: 0, y: 3), CGPoint(x: 0, y: 2), CGPoint(x: 1, y: 2), CGPoint(x: 1, y: 3)]
        expect(normalizedFingerCurl(straightFinger) < 0.1, "straight finger reads open")
        expect(normalizedFingerCurl(curledFinger) > 0.9, "bent finger reads down")

        var fingerStrikes = FingerStrikeDetector()
        expect(fingerStrikes.update(curls: [0, 0, 0, 0, 0], enabled: false, time: 0).isEmpty, "open fingers arm without firing")
        expect(fingerStrikes.update(curls: [0, 0.6, 0, 0, 0], enabled: true, time: 0.1) == [.index], "finger curl crossing fires its own trigger")
        expect(fingerStrikes.held == Set([.index]), "curled finger holds its note gate")
        expect(fingerStrikes.update(curls: [0, 0.8, 0, 0, 0], enabled: true, time: 0.2).isEmpty, "held finger cannot machine-gun")
        expect(fingerStrikes.held == Set([.index]), "held note gate stays active without retriggering")
        _ = fingerStrikes.update(curls: [0, 0.1, 0, 0, 0], enabled: true, time: 0.3)
        expect(fingerStrikes.held.isEmpty, "reopening finger releases its note gate")
        expect(fingerStrikes.update(curls: [0, 0.7, 0, 0, 0], enabled: true, time: 0.5) == [.index], "reopened finger can strike again")
        var fastFinger = FingerStrikeDetector()
        _ = fastFinger.update(curls: [0, 0.18, 0, 0, 0], enabled: true, time: 0)
        expect(fastFinger.update(curls: [0, 0.40, 0, 0, 0], enabled: true, time: 0.04) == [.index], "fast curl fires before full closure")
        var jitterFinger = FingerStrikeDetector()
        _ = jitterFinger.update(curls: [0, 0.28, 0, 0, 0], enabled: true, time: 0)
        expect(jitterFinger.update(curls: [0, 0.37, 0, 0, 0], enabled: true, time: 0.04).isEmpty, "small curl jitter does not fire early")

        expect(mouthExpression(0.08) == 0, "closed mouth has no expression effect")
        expect(mouthExpression(0.20) > 0.4, "small mouth movement is expressive")
        var mouth = MouthOpenDetector()
        expect(!mouth.update(openness: 0.1, time: 0), "closed mouth arms trigger")
        expect(!mouth.update(openness: 0.42, time: 0.1), "single mouth frame does not trigger")
        expect(mouth.update(openness: 0.42, time: 0.15), "deliberate mouth opening triggers")
        expect(!mouth.update(openness: 0.7, time: 0.3), "held mouth cannot repeat")
        expect(FingerName.thumb.drumName == "KICK" && FingerName.index.drumName == "SNARE", "thumb and index drum labels match supplied samples")
        expect(FingerName.middle.drumName == "HAT" && FingerName.little.drumName == "COWBELL", "middle and little drum labels match supplied samples")
        expect(fistDistortion([1, 0, 0, 0, 0]) < 0.05, "one synth finger stays clean")
        expect(fistDistortion([1, 1, 1, 1, 1]) > 0.95, "closed synth fist reaches full distortion")

        var detector = WinkDetector()
        func arm(_ at: Double) {
            _ = detector.update(left: 0, right: 0, time: at)
            _ = detector.update(left: 0, right: 0, time: at + 0.2)
        }
        arm(0)
        expect(detector.update(left: 1, right: 0, time: 0.3) == nil, "single frame does not trigger")
        expect(detector.update(left: 1, right: 0, time: 0.36) == .left, "brief left wink triggers left sample")
        expect(detector.update(left: 1, right: 0, time: 2) == nil, "held wink cannot repeat")
        arm(2.1)
        _ = detector.update(left: 0, right: 1, time: 2.4)
        expect(detector.update(left: 0, right: 1, time: 2.46) == .right, "brief right wink triggers right sample")
        arm(3)
        _ = detector.update(left: 1, right: 0, time: 3.3)
        expect(detector.update(left: 1, right: 1, time: 3.35) == nil, "bilateral blink cancels candidate")
        expect(detector.update(left: 1, right: 0, time: 3.5) == nil, "asymmetric blink reopening is rejected")
        expect(detector.update(left: 1, right: 0, time: 3.56) == nil, "ordinary blink cannot become a delayed wink")
        detector.reset()
        expect(detector.update(left: 1, right: 0, time: 5) == nil, "tracking reacquisition needs open eyes")
        print("\(checks) core checks passed")
    }
}
