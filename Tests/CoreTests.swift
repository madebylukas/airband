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
        state.active = true; state.height = -8
        expect(state.midi == 50, "pitch clamps below frame")
        state.height = 9
        expect(state.midi == 74, "pitch clamps above frame")
        state.height = .nan
        expect(state.frequency.isFinite, "invalid coordinate stays finite")
        state.height = 0.5
        expect(state.noteName == "D4", "middle pitch is D4")
        expect(abs(state.frequency - 293.6648) < 0.001, "D4 tuning is accurate")
        state.spread = 10
        expect(state.volume <= 0.67, "gain stays bounded")
        expect(palmRotation(wrist: CGPoint(x: 0.5, y: 0.8), knuckle: CGPoint(x: 0.5, y: 0.3)) == 0, "upright palm is clean")
        expect(palmRotation(wrist: CGPoint(x: 0.3, y: 0.5), knuckle: CGPoint(x: 0.8, y: 0.5)) == 1, "sideways palm has full distortion")
        expect(abs(palmRotation(wrist: CGPoint(x: 0.2, y: 0.8), knuckle: CGPoint(x: 0.5, y: 0.5)) - 0.5) < 0.001, "palm rotation maps smoothly")
        var detector = WinkDetector()
        func arm(_ at: Double) {
            _ = detector.update(left: 0, right: 0, time: at)
            _ = detector.update(left: 0, right: 0, time: at + 0.2)
        }
        arm(0)
        expect(!detector.update(left: 1, right: 0, time: 0.3), "single frame does not trigger")
        expect(detector.update(left: 1, right: 0, time: 0.44), "held left wink triggers")
        expect(!detector.update(left: 1, right: 0, time: 2), "held wink cannot repeat")
        arm(2.1)
        expect(!detector.update(left: 0, right: 1, time: 2.4), "right wink begins candidate")
        expect(detector.update(left: 0, right: 1, time: 2.54), "right wink triggers")
        arm(3)
        _ = detector.update(left: 1, right: 0, time: 3.3)
        expect(!detector.update(left: 1, right: 1, time: 3.35), "bilateral blink cancels candidate")
        expect(!detector.update(left: 1, right: 0, time: 3.5), "asymmetric blink reopening rejected")
        detector.reset()
        expect(!detector.update(left: 1, right: 0, time: 5), "tracking reacquisition needs open eyes")
        arm(6)
        _ = detector.update(left: 1, right: 0, time: 6.3)
        _ = detector.update(left: 1, right: 0, time: 6.44)
        arm(6.5)
        _ = detector.update(left: 1, right: 0, time: 6.75)
        expect(!detector.update(left: 1, right: 0, time: 6.9), "cooldown prevents rapid double fire")
        print("\(checks) core checks passed")
    }
}
