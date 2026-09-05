import AVFoundation

enum AudioGesture {
    case fart, ding, kick, cymbal
}

final class AudioEngine {
    var onWaveform: (([Float]) -> Void)?

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

        var tapCounter = 0
        engine.mainMixerNode.installTap(onBus: 0, bufferSize: 512, format: nil) { [weak self] buffer, _ in
            tapCounter += 1
            guard tapCounter.isMultiple(of: 4), let channel = buffer.floatChannelData?.pointee else { return }
            let frameCount = Int(buffer.frameLength)
            guard frameCount > 0 else { return }
            let buckets = 56
            let stride = max(1, frameCount / buckets)
            var values = [Float]()
            values.reserveCapacity(buckets)
            for bucket in 0..<buckets {
                let start = min(frameCount - 1, bucket * stride)
                let end = min(frameCount, start + stride)
                var peak: Float = 0
                for index in start..<end { peak = max(peak, abs(channel[index])) }
                values.append(min(1, peak))
            }
            DispatchQueue.main.async { self?.onWaveform?(values) }
        }
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
        ab_set(
            synth,
            Float(state.frequency), Float(state.volume), Float(state.brightness.clamped),
            Float(state.vibrato.clamped), Float(state.distortion.clamped), Float(state.muffle.clamped),
            Float(state.songRootFrequency), Float(min(176, max(62, state.tempo))),
            Int32(mode.rawValue), Int32(palette.rawValue)
        )
    }

    func trigger(_ gesture: AudioGesture) {
        guard let synth, running else { return }
        switch gesture {
        case .fart:
            if let fartFile { fartPlayer.scheduleFile(fartFile, at: nil); if !fartPlayer.isPlaying { fartPlayer.play() } }
            else { ab_fart(synth) }
        case .ding:
            if let dingFile { dingPlayer.scheduleFile(dingFile, at: nil); if !dingPlayer.isPlaying { dingPlayer.play() } }
            else { ab_ding(synth) }
        case .kick: ab_kick(synth)
        case .cymbal: ab_cymbal(synth)
        }
    }

    func stop() {
        if let synth { ab_set(synth, 220, 0, 0, 0, 0, 0, 220, 108, 0, 0) }
        fartPlayer.stop()
        dingPlayer.stop()
        engine.stop()
        running = false
        onWaveform?(Array(repeating: 0, count: 56))
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    deinit {
        engine.mainMixerNode.removeTap(onBus: 0)
        engine.stop()
        if let synth { ab_destroy(synth) }
    }
}
