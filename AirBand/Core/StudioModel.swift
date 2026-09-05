import SwiftUI
import AVFoundation

@MainActor
final class StudioModel: ObservableObject {
    @Published var playing = false
    @Published var touchMode = !CameraTracker.supported
    @Published var palette: SoundPalette = .prism
    @Published var music = MusicalState()
    @Published var hands: [CGPoint] = []
    @Published var faceTracked = false
    @Published var status = "Your body. The instrument."
    @Published var error: String?
    @Published var winkCount = 0
    @Published var fartFlash = false
    @Published var starting = false
    let tracker = CameraTracker()
    private let audio = AudioEngine()
    private var wink = WinkDetector()
    private var lastFrame = Date.distantPast
    private var watchdog: Timer?
    private var startToken = UUID()
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
            wink.reset(); lastFrame = Date()
            if !touchMode { tracker.start() }
            status = touchMode ? "Touch the field. Make a little future." : "Show your face and raise a hand."
            watchdog = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.playing, !self.touchMode, Date().timeIntervalSince(self.lastFrame) > 0.5 else { return }
                    self.music.active = false; self.hands = []; self.faceTracked = false
                    self.wink.reset(); self.syncAudio()
                    self.status = "Tracking paused. Move back into view."
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
        music.active = false; hands = []; faceTracked = false; wink.reset()
        status = "Your body. The instrument."
    }
    func setMode(_ touch: Bool) { stop(); touchMode = touch }
    func syncAudio() { audio.update(music, palette: palette) }
    func touch(at point: CGPoint) {
        guard playing, touchMode else { return }
        music.height = Double(1-point.y).clamped
        music.spread = Double(point.x).clamped
        music.active = true
        hands = [CGPoint(x: max(0.08, point.x - 0.18), y: point.y), CGPoint(x: min(0.92, point.x + 0.18), y: point.y)]
        syncAudio()
    }
    func endTouch() { music.active = false; hands = []; syncAudio() }
    func triggerFart() {
        guard playing else { return }
        audio.fart(); winkCount += 1; fartFlash = true
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        Task {
            try? await Task.sleep(for: .milliseconds(650))
            fartFlash = false
        }
    }
    private func receive(_ sample: TrackingSample) {
        guard playing, !touchMode else { return }
        lastFrame = Date()
        hands = sample.hands; faceTracked = sample.faceTracked
        if !sample.hands.isEmpty {
            let meanY = sample.hands.map(\.y).reduce(0, +) / CGFloat(sample.hands.count)
            music.height += (Double(1-meanY).clamped - music.height) * 0.3
            let spread = sample.hands.count == 2 ? Double(abs(sample.hands[1].x - sample.hands[0].x) / 0.7).clamped : 0.45
            music.spread += (spread - music.spread) * 0.2
        }
        music.active = !sample.hands.isEmpty
        music.distortion += (sample.rotation - music.distortion) * 0.2
        music.brightness = sample.faceTracked ? max(0.15, sample.smile * 1.5).clamped : 0.25
        music.vibrato = sample.faceTracked ? (sample.jaw * 1.5).clamped : 0
        if sample.faceTracked {
            if wink.update(left: sample.leftEye, right: sample.rightEye, time: sample.time) { triggerFart() }
        } else { wink.reset() }
        status = music.active ? (sample.faceTracked ? "You’re the signal." : "Hands locked. Bring your face into view.") : "Raise a hand to play."
        syncAudio()
    }
}
