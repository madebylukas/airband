import SwiftUI
import AVFoundation

@MainActor
final class StudioModel: ObservableObject {
    @Published var playing = false
    @Published var touchMode = !CameraTracker.supported
    @Published var mode: PerformanceMode = .jam
    private let palette: SoundPalette = .prism
    @Published var music = MusicalState()
    @Published var handPoses: [HandPoseSample] = []
    @Published var handsReady = false
    @Published var activeFingers: Set<FingerKey> = []
    @Published private(set) var hasPlayedFinger = false
    @Published var faceTracked = false
    @Published var error: String?
    @Published var gestureFlash: String?
    @Published var starting = false

    let tracker = CameraTracker()
    private let audio = AudioEngine()
    private var wink = WinkDetector()
    private var scaleLatch = HysteresisQuantizer(count: 5, initial: 2)
    private var octaveLatch = HysteresisQuantizer(count: 3, initial: 1, margin: 0.1)
    private var rootLatch = HysteresisQuantizer(count: 12, initial: 5, margin: 0.08)
    private var leftFingerStrikes = FingerStrikeDetector()
    private var rightFingerStrikes = FingerStrikeDetector()
    private var readySince: Double?
    private var performanceArmed = false
    private var fingerPulseTokens: [FingerKey: UUID] = [:]
    private var lastFrame = Date.distantPast
    private var watchdog: Timer?
    private var startToken = UUID()
    private var flashToken = UUID()
    private var observers: [NSObjectProtocol] = []

    init() {
        tracker.onSample = { [weak self] sample in self?.receive(sample) }
        tracker.onFailure = { [weak self] message in
            self?.stop(); self?.error = message
        }
        observers.append(NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.stop() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] notification in
            guard let value = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  AVAudioSession.RouteChangeReason(rawValue: value) == .oldDeviceUnavailable else { return }
            Task { @MainActor in self?.stop() }
        })
    }

    func start() async {
        guard !playing, !starting else { return }
        starting = true
        let token = UUID(); startToken = token
        if !touchMode {
            guard CameraTracker.supported else {
                starting = false; error = "Face tracking isn’t available on this device. Use Touch mode to play."; return
            }
            let allowed = await AVCaptureDevice.requestAccess(for: .video)
            guard token == startToken else { return }
            guard allowed else {
                starting = false
                error = "Allow camera access in Settings to play with gestures, or switch to Touch mode."
                return
            }
        }
        guard token == startToken else { return }
        do {
            try audio.start()
            playing = true; starting = false; error = nil
            wink.reset(); hasPlayedFinger = false; resetFingerPerformance(); lastFrame = Date()
            if !touchMode { tracker.start() }
            syncAudio()
            watchdog = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.playing, !self.touchMode, Date().timeIntervalSince(self.lastFrame) > 0.55 else { return }
                    self.music.active = false; self.handPoses = []; self.faceTracked = false
                    self.wink.reset(); self.resetFingerPerformance(); self.syncAudio()
                }
            }
        } catch {
            audio.stop(); starting = false
            self.error = "Audio couldn’t start: \(error.localizedDescription)"
        }
    }

    func stop() {
        startToken = UUID(); starting = false
        watchdog?.invalidate(); watchdog = nil
        tracker.stop(); audio.stop(); playing = false
        music.active = false; handPoses = []; faceTracked = false; wink.reset(); resetFingerPerformance()
        gestureFlash = nil
    }

    func setInputMode(touch: Bool) { stop(); touchMode = touch }

    func syncAudio() {
        let audioMode: PerformanceMode = touchMode && mode == .jam ? .free : mode
        audio.update(music, mode: audioMode, palette: palette)
    }

    func modeDidChange() {
        if mode == .jam { hasPlayedFinger = false }
        resetFingerPerformance()
        syncAudio()
    }

    func toggleMetronome() {
        music.metronomeEnabled.toggle()
        syncAudio()
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.65)
    }

    func touch(at point: CGPoint) {
        guard playing, touchMode else { return }
        music.height = Double(1 - point.y).clamped
        music.horizontal = Double(point.x).clamped
        music.scaleIndex = scaleLatch.update(music.height)
        music.rootIndex = rootLatch.update(music.height)
        music.octaveIndex = octaveLatch.update(music.horizontal)
        music.tempo = 64 + music.height * 112
        music.spread = 0.72
        music.active = true
        syncAudio()
    }

    func endTouch() {
        music.active = false
        syncAudio()
    }

    func triggerWink(_ side: WinkSide) {
        guard playing else { return }
        let gesture: AudioGesture
        let label: String
        if mode == .drums {
            gesture = side == .left ? .cymbal : .kick
            label = side == .left ? "CYMBAL" : "KICK"
        } else {
            gesture = side == .left ? .fart : .ding
            label = side == .left ? "PFFT" : "DING"
        }
        audio.trigger(gesture)
        flash(label)
        UIImpactFeedbackGenerator(style: mode == .drums ? .rigid : .soft).impactOccurred()
    }

    private func flash(_ label: String) {
        let token = UUID(); flashToken = token
        withAnimation(.spring(response: 0.24, dampingFraction: 0.72)) { gestureFlash = label }
        Task {
            try? await Task.sleep(for: .milliseconds(650))
            guard flashToken == token else { return }
            withAnimation(.easeOut(duration: 0.18)) { gestureFlash = nil }
        }
    }

    private func receive(_ sample: TrackingSample) {
        guard playing, !touchMode else { return }
        lastFrame = Date()
        handPoses = sample.hands
        faceTracked = sample.faceTracked
        let left = sample.hand(.left)
        let right = sample.hand(.right)
        if mode == .jam {
            music.rootIndex = 2
            if let left {
                let height = Double(1 - left.center.y).clamped
                music.drumVolume += (pow(height, 1.2) - music.drumVolume) * 0.42
            } else {
                music.drumVolume *= 0.88
            }
            if let right {
                let height = Double(1 - right.center.y).clamped
                music.melodyVolume += (pow(height, 1.2) - music.melodyVolume) * 0.42
                music.octaveIndex = octaveLatch.update(Double(right.center.x).clamped)
            } else {
                music.melodyVolume *= 0.88
            }
        } else if let lead = left ?? right {
            let targetHeight = Double(1 - lead.center.y).clamped
            let targetHorizontal = Double(lead.center.x).clamped
            music.height += (targetHeight - music.height) * 0.34
            music.horizontal += (targetHorizontal - music.horizontal) * 0.28
            music.scaleIndex = scaleLatch.update(music.height)
            music.rootIndex = rootLatch.update(music.height)
            music.octaveIndex = octaveLatch.update(music.horizontal)
        }
        if let left { music.muffle += (left.xyRotation - music.muffle) * 0.34 }
        else { music.muffle *= 0.88 }
        if let right {
            music.distortion += (right.xyRotation - music.distortion) * 0.34
            if mode != .jam {
                let tempo = 64 + Double(1 - right.center.y).clamped * 112
                music.tempo += (tempo - music.tempo) * 0.22
            }
        } else {
            music.distortion *= 0.88
        }
        let zTarget = sample.hands.isEmpty
            ? 0
            : sample.hands.map(\.zTilt).reduce(0, +) / Double(sample.hands.count)
        music.space += (zTarget - music.space) * 0.24
        if let left, let right {
            let distance = Double(abs(right.center.x - left.center.x) / 0.72).clamped
            music.spread += (distance - music.spread) * 0.22
        } else {
            music.spread += (0.62 - music.spread) * 0.15
        }
        music.active = !sample.hands.isEmpty
        music.brightness = sample.faceTracked ? max(0.12, sample.smile * 1.5).clamped : 0.24
        music.vibrato = sample.faceTracked ? (sample.jaw * 1.45).clamped : 0
        updateFingerPerformance(left: left, right: right, time: sample.time)
        if sample.faceTracked, let side = wink.update(left: sample.leftEye, right: sample.rightEye, time: sample.time) {
            triggerWink(side)
        } else if !sample.faceTracked {
            wink.reset()
        }
        syncAudio()
    }

    private func updateFingerPerformance(left: HandPoseSample?, right: HandPoseSample?, time: Double) {
        guard mode == .jam else {
            if handsReady || performanceArmed { resetFingerPerformance() }
            return
        }
        let bothVisible = left != nil && right != nil
        let readyPose = left.map(isReadyPose) == true && right.map(isReadyPose) == true
        if !performanceArmed {
            if readyPose {
                if readySince == nil { readySince = time }
                if time - (readySince ?? time) >= 0.10 {
                    performanceArmed = true
                    handsReady = true
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            } else {
                readySince = nil
            }
        } else if !bothVisible {
            resetFingerPerformance()
        }

        let enabled = performanceArmed && bothVisible
        let leftHits = leftFingerStrikes.update(curls: left?.fingerCurls ?? [], enabled: enabled, time: time)
        let rightHits = rightFingerStrikes.update(curls: right?.fingerCurls ?? [], enabled: enabled, time: time)
        for finger in leftHits { triggerFinger(.init(side: .left, finger: finger)) }
        for finger in rightHits { triggerFinger(.init(side: .right, finger: finger)) }
    }

    private func isReadyPose(_ hand: HandPoseSample) -> Bool {
        let visibleTips = FingerName.allCases.compactMap { hand[$0.tipJoint] }.count
        return visibleTips >= 4 && hand.fingerCurls.filter { $0 < 0.36 }.count >= 4
    }

    private func triggerFinger(_ key: FingerKey) {
        withAnimation(.easeOut(duration: 0.22)) { hasPlayedFinger = true }
        let gesture: AudioGesture
        let label: String
        if key.side == .left {
            gesture = [.subKick, .kick, .snare, .cymbal, .hat][key.finger.rawValue]
            label = key.finger.drumName
            audio.trigger(gesture, gain: music.drumVolume)
        } else {
            gesture = .melody(key.finger.rawValue)
            label = ["D", "F", "G", "A", "C"][key.finger.rawValue]
            audio.trigger(gesture, gain: music.melodyVolume)
        }
        pulse(key)
        flash(label)
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.48)
    }

    private func pulse(_ key: FingerKey) {
        let token = UUID()
        fingerPulseTokens[key] = token
        activeFingers.insert(key)
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            guard fingerPulseTokens[key] == token else { return }
            activeFingers.remove(key)
            fingerPulseTokens[key] = nil
        }
    }

    private func resetFingerPerformance() {
        readySince = nil
        performanceArmed = false
        handsReady = false
        leftFingerStrikes.reset()
        rightFingerStrikes.reset()
        activeFingers = []
        fingerPulseTokens = [:]
    }
}
