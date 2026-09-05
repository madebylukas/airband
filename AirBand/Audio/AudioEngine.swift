import AVFoundation

enum AudioGesture {
    case fart, ding, subKick, kick, snare, cymbal, hat
    case melody(Int)
}

final class AudioEngine {
    private let engine = AVAudioEngine()
    private let musicMixer = AVAudioMixerNode()
    private let reverb = AVAudioUnitReverb()
    private let fartPlayer = AVAudioPlayerNode()
    private let dingPlayer = AVAudioPlayerNode()
    private var source: AVAudioSourceNode?
    private var synth: OpaquePointer?
    private var fartFile: AVAudioFile?
    private var dingFile: AVAudioFile?
    private(set) var running = false

    func start() throws {
        guard !running else { return }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [])
        try session.setPreferredIOBufferDuration(0.0058)
        try session.setActive(true)
        if source == nil { try buildGraph(sampleRate: session.sampleRate) }
        try engine.start()
        fartPlayer.play()
        dingPlayer.play()
        running = true
    }

    private func buildGraph(sampleRate: Double) throws {
        guard let dsp = ab_create(sampleRate),
              let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else {
            throw NSError(domain: "AirBand", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not create the instrument."])
        }
        synth = dsp
        fartFile = audioFile(named: "fart")
        dingFile = audioFile(named: "ding")

        let node = AVAudioSourceNode { _, _, count, buffers in
            let list = UnsafeMutableAudioBufferListPointer(buffers)
            if let buffer = list.first, let data = buffer.mData {
                ab_render(dsp, data.assumingMemoryBound(to: Float.self), count)
            }
            return noErr
        }
        source = node
        [node, musicMixer, reverb, fartPlayer, dingPlayer].forEach(engine.attach)
        engine.connect(node, to: musicMixer, format: format)
        engine.connect(fartPlayer, to: musicMixer, format: fartFile?.processingFormat)
        engine.connect(dingPlayer, to: musicMixer, format: dingFile?.processingFormat)
        reverb.loadFactoryPreset(.largeHall2)
        reverb.wetDryMix = 25
        engine.connect(musicMixer, to: reverb, format: format)
        engine.connect(reverb, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0.82

    }

    private func audioFile(named name: String) -> AVAudioFile? {
        for ext in ["mp3", "m4a", "wav"] {
            if let url = Bundle.main.url(forResource: name, withExtension: ext),
               let file = try? AVAudioFile(forReading: url) { return file }
        }
        return nil
    }

    func update(_ state: MusicalState, mode: PerformanceMode, palette: SoundPalette) {
        guard let synth else { return }
        reverb.wetDryMix = Float(18 + state.space.clamped * 48)
        ab_set(
            synth,
            Float(state.frequency), Float(state.volume), Float(state.brightness.clamped),
            Float(state.vibrato.clamped), Float(state.distortion.clamped), Float(state.muffle.clamped),
            Float(state.songRootFrequency), Float(min(176, max(62, state.tempo))),
            Int32(mode.rawValue), Int32(palette.rawValue)
        )
        ab_set_performance(
            synth,
            Float(state.drumVolume.clamped),
            Float(state.melodyVolume.clamped),
            state.metronomeEnabled ? 1 : 0
        )
    }

    func trigger(_ gesture: AudioGesture, gain: Double = 1) {
        guard let synth, running else { return }
        let level = Float(gain.clamped)
        switch gesture {
        case .fart:
            if let fartFile { fartPlayer.scheduleFile(fartFile, at: nil); if !fartPlayer.isPlaying { fartPlayer.play() } }
            else { ab_fart(synth) }
        case .ding:
            if let dingFile { dingPlayer.scheduleFile(dingFile, at: nil); if !dingPlayer.isPlaying { dingPlayer.play() } }
            else { ab_ding(synth) }
        case .subKick: ab_trigger_drum(synth, 0, level)
        case .kick: ab_trigger_drum(synth, 1, level)
        case .snare: ab_trigger_drum(synth, 2, level)
        case .cymbal: ab_trigger_drum(synth, 3, level)
        case .hat: ab_trigger_drum(synth, 4, level)
        case .melody(let note): ab_trigger_note(synth, Int32(note), level)
        }
    }

    func stop() {
        if let synth {
            ab_set(synth, 220, 0, 0, 0, 0, 0, 220, 108, 0, 0)
            ab_set_performance(synth, 0, 0, 0)
        }
        fartPlayer.stop()
        dingPlayer.stop()
        engine.stop()
        running = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    deinit {
        engine.stop()
        if let synth { ab_destroy(synth) }
    }
}
