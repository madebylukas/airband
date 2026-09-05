import AVFoundation

final class AudioEngine {
    private let engine = AVAudioEngine()
    private let reverb = AVAudioUnitReverb()
    private var source: AVAudioSourceNode?
    private var synth: OpaquePointer?
    private(set) var running = false

    func start() throws {
        guard !running else { return }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [])
        try session.setPreferredIOBufferDuration(0.0058)
        try session.setActive(true)
        if source == nil {
            let rate = session.sampleRate
            guard let dsp = ab_create(rate), let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1) else {
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
            engine.attach(node)
            engine.attach(reverb)
            reverb.loadFactoryPreset(.largeHall2)
            reverb.wetDryMix = 27
            engine.connect(node, to: reverb, format: format)
            engine.connect(reverb, to: engine.mainMixerNode, format: format)
            engine.mainMixerNode.outputVolume = 0.8
        }
        try engine.start()
        running = true
    }

    func update(_ state: MusicalState, palette: SoundPalette) {
        guard let synth else { return }
        ab_set(synth, Float(state.frequency), Float(state.volume), Float(state.brightness.clamped), Float(state.vibrato.clamped), Float(state.distortion.clamped), Int32(palette.rawValue))
    }
    func fart() { if let synth, running { ab_fart(synth) } }
    func stop() {
        if let synth { ab_set(synth, 220, 0, 0, 0, 0, 0) }
        engine.stop()
        engine.reset()
        running = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    deinit {
        engine.stop()
        if let synth { ab_destroy(synth) }
    }
}
