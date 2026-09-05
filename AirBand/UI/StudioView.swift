import SwiftUI

private let ink = Color(red: 0.015, green: 0.017, blue: 0.022)
private let readyGreen = Color(red: 0.30, green: 1.0, blue: 0.55)

struct StudioView: View {
    @StateObject private var model = StudioModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var showGuide = false

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            ZStack {
                ink.ignoresSafeArea()
                field.ignoresSafeArea(edges: .bottom)
                if model.playing && !model.touchMode {
                    controlGuides(in: geo.size, landscape: landscape)
                }
                if model.playing && !model.touchMode && model.mode == .jam && (!model.handsReady || !model.hasPlayedFinger) {
                    launchInstruction(landscape: landscape)
                }
                VStack(spacing: 0) {
                    header
                    HStack {
                        Spacer()
                        if model.playing {
                            Text(readout)
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.72))
                                .contentTransition(.numericText())
                        }
                    }.frame(height: 25).padding(.top, landscape ? 2 : 10)
                    Spacer()
                    if let flash = model.gestureFlash {
                        Text(flash)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced)).tracking(3)
                            .padding(.horizontal, 18).frame(height: 46)
                            .airGlass(Capsule())
                            .transition(.scale.combined(with: .opacity))
                            .padding(.bottom, 22)
                    }
                    if model.playing && model.touchMode {
                        HStack(spacing: 14) {
                            Image(systemName: "rotate.right").font(.system(size: 14, weight: .light)).foregroundStyle(.white.opacity(0.55))
                            Slider(value: $model.music.distortion, in: 0...1).tint(.white)
                                .accessibilityLabel("Distortion")
                                .onChange(of: model.music.distortion) { _, _ in model.syncAudio() }
                        }.padding(.horizontal, landscape ? geo.size.width * 0.25 : 70).padding(.bottom, landscape ? 7 : 12)
                    }
                    controls(compact: landscape).padding(.bottom, landscape ? 8 : 22)
                }.padding(.horizontal, landscape ? 34 : 26).padding(.top, landscape ? 2 : 8)
            }
        }
        .foregroundStyle(.white).preferredColorScheme(.dark)
        .sheet(isPresented: $showGuide) { guide }
        .alert("Session paused", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK", role: .cancel) { model.error = nil }
            if !model.touchMode {
                Button("Use Touch mode") {
                    model.setInputMode(touch: true)
                    Task { await model.start() }
                }
                Button("Settings") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
            }
        } message: { Text(model.error ?? "") }
        .task { await model.start() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.start() } }
            else { model.stop() }
        }
    }

    private var readout: String {
        switch model.mode {
        case .free: return model.music.active ? model.music.noteName : "—"
        case .song: return "\(model.music.keyName)  ·  \(Int(model.music.tempo)) BPM"
        case .drums: return "\(Int(model.music.tempo)) BPM"
        case .jam: return model.touchMode ? model.music.noteName : model.handsReady ? "READY" : "—"
        }
    }

    private var header: some View {
        HStack {
            Text("airband").font(.system(size: 23, weight: .medium, design: .rounded)).tracking(-0.9)
            if model.playing && !model.touchMode {
                Circle()
                    .fill(model.mode == .jam && model.handsReady ? readyGreen : .white.opacity(model.faceTracked ? 0.42 : 0.2))
                    .frame(width: model.handsReady ? 7 : 5, height: model.handsReady ? 7 : 5)
                    .shadow(color: model.handsReady ? readyGreen.opacity(0.8) : .clear, radius: 7)
                    .accessibilityLabel(model.handsReady ? "Hands ready" : "Waiting for both open hands")
                    .animation(.easeOut(duration: 0.16), value: model.handsReady)
            }
            Spacer()
            Menu {
                ForEach(PerformanceMode.allCases) { mode in
                    Button { model.selectMode(mode) } label: {
                        Label(mode.title, systemImage: model.mode == mode ? "checkmark.circle.fill" : mode.symbol)
                    }
                }
                Divider()
                Button {
                    model.setInputMode(touch: !model.touchMode)
                    Task { await model.start() }
                } label: {
                    Label(model.touchMode ? "Use Camera" : "Use Touch", systemImage: model.touchMode ? "camera" : "hand.draw")
                }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: model.mode.symbol)
                    Text(model.mode.title).font(.system(size: 12, weight: .medium))
                }.padding(.horizontal, 15).frame(height: 44)
            }.airGlass(Capsule()).accessibilityLabel("Mode: \(model.mode.title)")
            Button { showGuide = true } label: {
                Image(systemName: "questionmark").font(.system(size: 14, weight: .medium)).frame(width: 44, height: 44)
            }.airGlass(Circle()).accessibilityLabel("How to play")
        }
    }

    private var field: some View {
        GeometryReader { geo in
            ZStack {
                if !model.touchMode && model.playing {
                    CameraView(tracker: model.tracker)
                        .saturation(0)
                        .overlay(.black.opacity(0.18))
                } else {
                    RadialGradient(colors: [Color(white: 0.12), ink], center: UnitPoint(x: 0.5, y: 0.4), startRadius: 5, endRadius: geo.size.height * 0.55)
                }
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
                    SignalCanvas(
                        time: timeline.date.timeIntervalSinceReferenceDate,
                        active: model.music.active,
                        demo: model.touchMode || !model.playing,
                        hands: model.handPoses,
                        mode: model.mode,
                        ready: model.handsReady,
                        activeFingers: model.activeFingers.union(model.heldSynthFingers),
                        brightness: model.music.brightness + model.music.distortion + model.music.space * 0.5 + model.music.vibrato * 0.3
                    )
                }.allowsHitTesting(false)
                LinearGradient(colors: [.black.opacity(0.08), .clear, ink.opacity(0.95)], startPoint: .top, endPoint: .bottom).allowsHitTesting(false)
                if model.touchMode {
                    Color.clear.contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                model.touch(at: CGPoint(
                                    x: min(1, max(0, value.location.x / geo.size.width)),
                                    y: min(1, max(0, value.location.y / geo.size.height))
                                ))
                            }.onEnded { _ in model.endTouch() })
                        .accessibilityLabel("Instrument touch field")
                        .accessibilityHint("After starting, drag vertically for pitch and horizontally for octave.")
                }
            }
        }
    }

    private func controls(compact: Bool) -> some View {
        let satellite: CGFloat = compact ? 62 : 76
        let transportRing: CGFloat = compact ? 74 : 88
        let transport: CGFloat = compact ? 62 : 72
        return HStack(spacing: compact ? 22 : 26) {
            Button {
                if model.playing { model.stop() } else { Task { await model.start() } }
            } label: {
                ZStack {
                    Circle().stroke(.white.opacity(0.3), lineWidth: 1).frame(width: transportRing, height: transportRing)
                    Circle().fill(.white).frame(width: transport, height: transport)
                    if model.starting { ProgressView().tint(.black) }
                    else {
                        Image(systemName: model.playing ? "stop.fill" : "play.fill")
                            .font(.system(size: 23, weight: .medium)).foregroundStyle(.black)
                            .offset(x: model.playing ? 0 : 2)
                    }
                }
            }.disabled(model.starting).accessibilityIdentifier("transport")
                .accessibilityLabel(model.playing ? "Stop session" : "Start playing")
            Button { model.toggleMetronome() } label: {
                ZStack(alignment: .bottom) {
                    Image(systemName: "metronome").font(.system(size: 24, weight: .ultraLight))
                    Capsule().fill(.white.opacity(model.music.metronomeEnabled ? 0.95 : 0.16))
                        .frame(width: model.music.metronomeEnabled ? 18 : 5, height: 2)
                        .offset(y: -11)
                }.frame(width: satellite, height: satellite)
            }.airGlass(Circle()).accessibilityLabel(model.music.metronomeEnabled ? "Turn metronome off" : "Turn metronome on")
        }
    }

    private func controlGuides(in size: CGSize, landscape: Bool) -> some View {
        let railHeight = min(landscape ? 98 : 205, size.height * (landscape ? 0.27 : 0.27))
        let detected = !model.handPoses.isEmpty
        let tempoLevel = ((model.music.tempo - 64) / 112).clamped
        let left: ControlGuideSpec?
        let right: ControlGuideSpec?
        switch model.mode {
        case .jam:
            left = ControlGuideSpec(
                title: "SYNTH", top: "LOUDER", bottom: "QUIETER", value: model.music.melodyVolume,
                hints: [
                    ControlHint(symbol: "arrow.left.and.right", title: "OCTAVE"),
                    ControlHint(symbol: "rotate.right", title: "MUFFLE"),
                    ControlHint(symbol: "hand.raised.fill", title: "FIST · DISTORT")
                ]
            )
            right = ControlGuideSpec(title: "DRUMS", top: "LOUDER", bottom: "QUIETER", value: model.music.drumVolume)
        case .song:
            left = ControlGuideSpec(
                title: "KEY", top: "HIGHER", bottom: "LOWER", value: model.music.height,
                hints: [
                    ControlHint(symbol: "arrow.left.and.right", title: "OCTAVE"),
                    ControlHint(symbol: "rotate.right", title: "MUFFLE")
                ]
            )
            right = ControlGuideSpec(
                title: "TEMPO", top: "FASTER", bottom: "SLOWER", value: tempoLevel,
                hints: [ControlHint(symbol: "rotate.right", title: "DISTORT")]
            )
        case .drums:
            left = nil
            right = ControlGuideSpec(
                title: "TEMPO", top: "FASTER", bottom: "SLOWER", value: tempoLevel,
                hints: [ControlHint(symbol: "rotate.right", title: "DISTORT")]
            )
        case .free:
            left = ControlGuideSpec(
                title: "PITCH", top: "HIGHER", bottom: "LOWER", value: model.music.height,
                hints: [
                    ControlHint(symbol: "arrow.left.and.right", title: "OCTAVE"),
                    ControlHint(symbol: "rotate.right", title: "MUFFLE")
                ]
            )
            right = ControlGuideSpec(
                hints: [ControlHint(symbol: "rotate.right", title: "DISTORT")]
            )
        }
        return HStack {
            if let left { ControlGuide(spec: left, active: model.mode == .jam ? model.handsReady : detected, railHeight: railHeight) }
            Spacer()
            if let right { ControlGuide(spec: right, active: model.mode == .jam ? model.handsReady : detected, railHeight: railHeight) }
        }
        .padding(.horizontal, landscape ? 18 : 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .offset(y: landscape ? 3 : -5)
        .allowsHitTesting(false)
    }

    private func launchInstruction(landscape: Bool) -> some View {
        VStack(spacing: 0) {
            Spacer()
            HStack(spacing: 12) {
                Image(systemName: model.handsReady ? "hand.point.down.fill" : "hand.raised.fingers.spread")
                    .font(.system(size: 17, weight: .light))
                    .foregroundStyle(model.handsReady ? readyGreen : .white.opacity(0.8))
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.handsReady ? "CURL A FINGER" : "GET IN POSITION")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .tracking(1.7)
                    Text(model.handsReady ? "LEFT SYNTH  ·  RIGHT DRUMS" : "PALMS UP  ·  OPEN BOTH HANDS")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .tracking(0.9)
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .padding(.horizontal, 18)
            .frame(height: 58)
            .airGlass(Capsule())
            .animation(.easeOut(duration: 0.16), value: model.handsReady)
            Spacer()
        }
        .padding(.top, landscape ? 44 : 80)
        .padding(.bottom, landscape ? 66 : 108)
        .allowsHitTesting(false)
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }

    private var guide: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                HStack {
                    Text("Move.\nMake noise.").font(.system(size: 31, weight: .light)).tracking(-0.8)
                    Spacer()
                    Button { showGuide = false } label: { Image(systemName: "xmark").frame(width: 40, height: 40) }
                        .airGlass(Circle()).accessibilityLabel("Close guide")
                }
                Text("Prop your iPhone up in portrait or landscape, an arm’s length away. Keep both open hands and your face in view.")
                    .font(.system(size: 14)).foregroundStyle(.secondary)
                guideRow("hand.raised", "Jam position", "Show both open hands, palms up. The light turns green when the finger triggers are armed.")
                guideRow("music.quarternote.3", "Left fingers", "Curl to start a note, hold to sustain it, and reopen to release. Close the whole fist to distort.")
                guideRow("circle.grid.cross", "Right fingers", "Thumb: kick. Index: snare. Middle: hi-hat. Ring: crash. Little: cowbell.")
                guideRow("arrow.up.and.down", "Hand height", "Raise the left hand for louder synth. Raise the right hand for louder drums.")
                guideRow("viewfinder", "Palm plane", "Start flat and level to set neutral. Flip a palm upward to open the space effect.")
                guideRow("face.smiling", "Face", "Smile for shimmer. Open your mouth for vibrato and rizz.")
                guideRow("eye", "Winks", "Left plays your fart; right plays the ding. In Drums they become cymbal and kick.")
                guideRow("music.note.list", "Song", "A pentatonic melody, bass line, and beat stay harmonically locked while your hands reshape them.")
                Label("Camera data stays on your iPhone.", systemImage: "lock.shield")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }.padding(28)
        }.background(ink).presentationDragIndicator(.visible)
    }

    private func guideRow(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 20) {
            Image(systemName: symbol).font(.system(size: 21, weight: .light)).frame(width: 26)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 16, weight: .medium))
                Text(detail).font(.system(size: 13)).foregroundStyle(.secondary)
            }
        }
    }
}

private extension View {
    @ViewBuilder func airGlass<S: Shape>(_ shape: S) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(.white.opacity(0.12), lineWidth: 0.7))
        }
    }
}

private struct ControlHint {
    let symbol: String
    let title: String
}

private struct ControlGuideSpec {
    var title: String?
    var top: String?
    var bottom: String?
    var value: Double
    var hints: [ControlHint]

    init(title: String? = nil, top: String? = nil, bottom: String? = nil, value: Double = 0, hints: [ControlHint] = []) {
        self.title = title
        self.top = top
        self.bottom = bottom
        self.value = value
        self.hints = hints
    }
}

private struct ControlGuide: View {
    let spec: ControlGuideSpec
    let active: Bool
    let railHeight: CGFloat

    private var level: CGFloat { CGFloat(min(1, max(0, spec.value))) }
    private var color: Color { active ? readyGreen : .white }

    var body: some View {
        VStack(spacing: 7) {
            if let title = spec.title, let top = spec.top, let bottom = spec.bottom {
                Text(title)
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .tracking(1.3)
                Text(top)
                    .font(.system(size: 7, weight: .medium, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(.white.opacity(0.46))
                GeometryReader { geo in
                    ZStack(alignment: .bottom) {
                        Capsule().fill(.white.opacity(0.15)).frame(width: 2)
                        Capsule().fill(color.opacity(0.72)).frame(width: 2, height: max(2, geo.size.height * level))
                        Circle()
                            .fill(color)
                            .frame(width: 7, height: 7)
                            .shadow(color: color.opacity(0.65), radius: active ? 5 : 2)
                            .position(x: geo.size.width / 2, y: max(3.5, (1 - level) * (geo.size.height - 7) + 3.5))
                    }
                }
                .frame(width: 12, height: railHeight)
                Text(bottom)
                    .font(.system(size: 7, weight: .medium, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(.white.opacity(0.46))
            }
            ForEach(Array(spec.hints.enumerated()), id: \.offset) { _, hint in
                HStack(spacing: 4) {
                    Image(systemName: hint.symbol)
                    Text(hint.title)
                }
                .font(.system(size: 7, weight: .semibold, design: .monospaced))
                .tracking(0.45)
                .foregroundStyle(.white.opacity(0.56))
                .lineLimit(1)
            }
        }
        .frame(width: 82)
        .foregroundStyle(.white.opacity(0.72))
        .animation(.linear(duration: 0.08), value: spec.value)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityValue("\(Int(level * 100)) percent")
    }

    private var accessibilityDescription: String {
        let vertical = [spec.title, spec.top.map { "up means \($0.lowercased())" }, spec.bottom.map { "down means \($0.lowercased())" }]
            .compactMap { $0 }.joined(separator: ". ")
        let hints = spec.hints.map(\.title).joined(separator: ". ")
        return [vertical, hints].filter { !$0.isEmpty }.joined(separator: ". ")
    }
}

private struct SignalCanvas: View {
    let time: Double
    let active: Bool
    let demo: Bool
    let hands: [HandPoseSample]
    let mode: PerformanceMode
    let ready: Bool
    let activeFingers: Set<FingerKey>
    let brightness: Double

    private let fingerChains: [[HandJoint]] = [
        [.wrist, .thumbCMC, .thumbMP, .thumbIP, .thumbTip],
        [.wrist, .indexMCP, .indexPIP, .indexDIP, .indexTip],
        [.wrist, .middleMCP, .middlePIP, .middleDIP, .middleTip],
        [.wrist, .ringMCP, .ringPIP, .ringDIP, .ringTip],
        [.wrist, .littleMCP, .littlePIP, .littleDIP, .littleTip],
        [.indexMCP, .middleMCP, .ringMCP, .littleMCP]
    ]

    var body: some View {
        Canvas { context, size in
            let color = ready ? readyGreen : Color.white
            if demo { drawAmbientField(context: &context, size: size, color: color) }

            let centers = hands.map { CGPoint(x: $0.center.x * size.width, y: $0.center.y * size.height) }
            if centers.count == 2 {
                for strand in 0..<7 {
                    var path = Path()
                    for step in 0...90 {
                        let t = Double(step) / 90
                        let amplitude = (active ? 20 + brightness * 18 : 5) * sin(t * .pi)
                        let offset = sin(t * 12 + time * 3 + Double(strand) * 0.55) * amplitude
                        let point = CGPoint(
                            x: centers[0].x + (centers[1].x - centers[0].x) * t,
                            y: centers[0].y + (centers[1].y - centers[0].y) * t + offset
                        )
                        if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
                    }
                    context.stroke(path, with: .color(color.opacity(0.22)), lineWidth: strand == 3 ? 1.5 : 0.55)
                }
            }

            for hand in hands { draw(hand: hand, context: &context, size: size) }
        }
    }

    private func draw(hand: HandPoseSample, context: inout GraphicsContext, size: CGSize) {
        func screen(_ point: CGPoint) -> CGPoint { CGPoint(x: point.x * size.width, y: point.y * size.height) }
        if let wrist = hand[.wrist], let index = hand[.indexMCP],
           let middle = hand[.middleMCP], let little = hand[.littleMCP] {
            var plane = Path()
            plane.move(to: screen(wrist))
            plane.addLine(to: screen(index))
            plane.addLine(to: screen(middle))
            plane.addLine(to: screen(little))
            plane.closeSubpath()
            context.fill(plane, with: .color((ready ? readyGreen : .white).opacity(0.025 + hand.zTilt * 0.09)))
            var axis = Path()
            axis.move(to: screen(index)); axis.addLine(to: screen(little))
            context.stroke(axis, with: .color((ready ? readyGreen : .white).opacity(0.5 + hand.xyRotation * 0.38)), lineWidth: 1.6)
        }
        for chain in fingerChains {
            var path = Path()
            var drawing = false
            for joint in chain {
                guard let point = hand[joint] else { drawing = false; continue }
                let p = screen(point)
                if drawing { path.addLine(to: p) } else { path.move(to: p); drawing = true }
            }
            context.stroke(path, with: .color((ready ? readyGreen : .white).opacity(0.72)), lineWidth: 1.05)
        }
        for joint in HandJoint.allCases {
            guard let point = hand[joint] else { continue }
            let p = screen(point)
            let finger = FingerName.allCases.first { $0.tipJoint == joint }
            let pulsing = finger.map { activeFingers.contains(FingerKey(side: hand.side, finger: $0)) } == true
            let radius: CGFloat = pulsing ? 8 : finger == nil ? 1.45 : 2.8
            let dotColor = pulsing ? readyGreen : ready ? readyGreen : .white
            context.fill(Path(ellipseIn: CGRect(x: p.x-radius, y: p.y-radius, width: radius*2, height: radius*2)), with: .color(dotColor.opacity(finger == nil ? 0.65 : 0.95)))
        }
        let position = screen(hand.center)
        let haloRadius = CGFloat(7 + hand.zTilt * 18)
        context.stroke(
            Path(ellipseIn: CGRect(x: position.x - haloRadius, y: position.y - haloRadius, width: haloRadius * 2, height: haloRadius * 2)),
            with: .color((ready ? readyGreen : .white).opacity(0.12 + hand.zTilt * 0.34)),
            lineWidth: 0.8
        )
        let label = handLabel(hand.side)
        if !label.isEmpty {
            context.draw(
                Text(label).font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(1.5).foregroundColor(.white),
                at: CGPoint(x: position.x, y: max(30, position.y - 54))
            )
        }
    }

    private func handLabel(_ side: HandSide) -> String {
        switch mode {
        case .free: return side == .left ? "MELODY" : "DISTORT"
        case .song: return side == .left ? "MELODY" : "BASS · BEAT"
        case .drums: return ""
        case .jam: return side == .left ? "SYNTH" : "DRUMS"
        }
    }

    private func drawAmbientField(context: inout GraphicsContext, size: CGSize, color: Color) {
        let amplitude = min(size.width, size.height) * 0.035
        for strand in 0..<9 {
            let baseline = size.height * (0.31 + CGFloat(strand) * 0.045)
            var path = Path()
            for step in 0...100 {
                let progress = Double(step) / 100
                let x = CGFloat(progress) * size.width
                let envelope = sin(progress * .pi)
                let wave = sin(progress * 15 + time * 1.8 + Double(strand) * 0.58)
                let drift = sin(progress * 4 - time * 0.55 + Double(strand)) * 0.35
                let y = baseline + CGFloat((wave + drift) * envelope) * amplitude
                if step == 0 { path.move(to: CGPoint(x: x, y: y)) }
                else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            context.stroke(path, with: .color(color.opacity(strand == 4 ? 0.34 : 0.12)), lineWidth: strand == 4 ? 1.25 : 0.55)
        }
    }
}
