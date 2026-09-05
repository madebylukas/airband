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

        var detector = WinkDetector()
        func arm(_ at: Double) {
            _ = detector.update(left: 0, right: 0, time: at)
            _ = detector.update(left: 0, right: 0, time: at + 0.2)
        }
        arm(0)
        expect(detector.update(left: 1, right: 0, time: 0.3) == nil, "single frame does not trigger")
        expect(detector.update(left: 1, right: 0, time: 0.44) == .left, "held left wink triggers left sample")
        expect(detector.update(left: 1, right: 0, time: 2) == nil, "held wink cannot repeat")
        arm(2.1)
        _ = detector.update(left: 0, right: 1, time: 2.4)
        expect(detector.update(left: 0, right: 1, time: 2.54) == .right, "held right wink triggers right sample")
        arm(3)
        _ = detector.update(left: 1, right: 0, time: 3.3)
        expect(detector.update(left: 1, right: 1, time: 3.35) == nil, "bilateral blink cancels candidate")
        expect(detector.update(left: 1, right: 0, time: 3.5) == nil, "asymmetric blink reopening is rejected")
        detector.reset()
        expect(detector.update(left: 1, right: 0, time: 5) == nil, "tracking reacquisition needs open eyes")
        print("\(checks) core checks passed")
    }
}
