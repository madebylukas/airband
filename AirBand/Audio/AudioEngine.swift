import AVFoundation

enum AudioGesture {
    case fart, ding, rizz, cowbell, kick, snare, cymbal, hat
    case melody(Int)
}

private enum SampleVoice: String, CaseIterable {
    case fart, ding, rizz, cowbell, kick, snare, crash, hat

    var gain: Double {
        switch self {
        case .fart: 0.90
        case .ding: 0.76
        case .rizz: 0.86
        case .cowbell: 0.90
        case .kick: 0.90
        case .snare: 0.88
        case .crash: 0.82
        case .hat: 0.90
        }
    }
}

final class AudioEngine {
    private let engine = AVAudioEngine()
    private let musicMixer = AVAudioMixerNode()
    private let reverb = AVAudioUnitReverb()
    private let samplePlayers = Dictionary(uniqueKeysWithValues: SampleVoice.allCases.map { ($0, AVAudioPlayerNode()) })
    private var sampleBuffers: [SampleVoice: AVAudioPCMBuffer] = [:]
    private var source: AVAudioSourceNode?
    private var synth: OpaquePointer?
    private(set) var running = false

    func start() throws {
        guard !running else { return }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [])
        try session.setPreferredIOBufferDuration(0.0058)
        try session.setActive(true)
        if source == nil { try buildGraph(sampleRate: session.sampleRate) }
        try engine.start()
        for voice in sampleBuffers.keys { samplePlayers[voice]?.play() }
        running = true
    }

    private func buildGraph(sampleRate: Double) throws {
        guard let dsp = ab_create(sampleRate),
              let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else {
            throw NSError(domain: "AirBand", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not create the instrument."])
        }
        synth = dsp

        let node = AVAudioSourceNode { _, _, count, buffers in
            let list = UnsafeMutableAudioBufferListPointer(buffers)
            if let buffer = list.first, let data = buffer.mData {
                ab_render(dsp, data.assumingMemoryBound(to: Float.self), count)
            }
            return noErr
        }
        source = node
        [node, musicMixer, reverb].forEach(engine.attach)
        engine.connect(node, to: musicMixer, format: format)
        for voice in SampleVoice.allCases {
            guard let player = samplePlayers[voice], let buffer = audioBuffer(named: voice.rawValue) else { continue }
            sampleBuffers[voice] = buffer
            engine.attach(player)
            engine.connect(player, to: musicMixer, format: buffer.format)
        }
        reverb.loadFactoryPreset(.largeHall2)
        reverb.wetDryMix = 25
        engine.connect(musicMixer, to: reverb, format: format)
        engine.connect(reverb, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0.82

    }

    private func audioBuffer(named name: String) -> AVAudioPCMBuffer? {
        for ext in ["mp3", "m4a", "wav"] {
            if let url = Bundle.main.url(forResource: name, withExtension: ext),
               let file = try? AVAudioFile(forReading: url) {
                let length = min(file.length, AVAudioFramePosition(UInt32.max))
                guard let buffer = AVAudioPCMBuffer(
                    pcmFormat: file.processingFormat,
                    frameCapacity: AVAudioFrameCount(max(1, length))
                ) else { return nil }
                do {
                    try file.read(into: buffer)
                    return buffer
                } catch {
                    return nil
                }
            }
        }
        return nil
    }

    @discardableResult
    private func play(_ voice: SampleVoice, gain: Double = 1) -> Bool {
        guard let player = samplePlayers[voice], let buffer = sampleBuffers[voice] else { return false }
        player.volume = Float((gain * voice.gain).clamped)
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        if !player.isPlaying { player.play() }
        return true
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
            if !play(.fart) { ab_fart(synth) }
        case .ding:
            if !play(.ding) { ab_ding(synth) }
        case .rizz:
            _ = play(.rizz)
        case .cowbell:
            if !play(.cowbell, gain: gain) { ab_trigger_drum(synth, 0, level) }
        case .kick:
            if !play(.kick, gain: gain) { ab_trigger_drum(synth, 1, level) }
        case .snare:
            if !play(.snare, gain: gain) { ab_trigger_drum(synth, 2, level) }
        case .cymbal:
            if !play(.crash, gain: gain) { ab_trigger_drum(synth, 3, level) }
        case .hat:
            if !play(.hat, gain: gain) { ab_trigger_drum(synth, 4, level) }
        case .melody(let note): ab_trigger_note(synth, Int32(note), level)
        }
    }

    func stop() {
        if let synth {
            ab_set(synth, 220, 0, 0, 0, 0, 0, 220, 108, 0, 0)
            ab_set_performance(synth, 0, 0, 0)
        }
        samplePlayers.values.forEach { $0.stop() }
        engine.stop()
        running = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    deinit {
        engine.stop()
        if let synth { ab_destroy(synth) }
    }
}
