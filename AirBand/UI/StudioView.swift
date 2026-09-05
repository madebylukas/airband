import SwiftUI

private let ink = Color(red: 0.015, green: 0.017, blue: 0.022)

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
                    if !model.playing {
                        Text("Music.\nIn your hands.")
                            .font(.system(size: landscape ? 34 : 43, weight: .light)).tracking(-1.8)
                            .multilineTextAlignment(.center)
                            .padding(.bottom, landscape ? 10 : geo.size.height * 0.12)
                            .allowsHitTesting(false)
                    }
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
                                .accessibilityLabel("Right hand distortion")
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
                Button("Use Touch mode") { model.setInputMode(touch: true) }
                Button("Settings") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
            }
        } message: { Text(model.error ?? "") }
        .onChange(of: scenePhase) { _, phase in if phase != .active { model.stop() } }
        .onChange(of: model.palette) { _, _ in model.syncAudio() }
        .onChange(of: model.mode) { _, _ in model.syncAudio() }
    }

    private var readout: String {
        switch model.mode {
        case .free: return model.music.active ? model.music.noteName : "—"
        case .song: return "\(model.music.keyName)  ·  \(Int(model.music.tempo)) BPM"
        case .drums: return "\(Int(model.music.tempo)) BPM"
        }
    }

    private var header: some View {
        HStack {
            Text("airband").font(.system(size: 23, weight: .medium, design: .rounded)).tracking(-0.9)
            if model.playing && !model.touchMode {
                Circle().fill(model.faceTracked ? .white : .white.opacity(0.3)).frame(width: 5, height: 5)
                    .accessibilityLabel(model.faceTracked ? "Face tracking active" : "Looking for your face")
            }
            Spacer()
            Menu {
                Picker("Performance", selection: $model.mode) {
                    ForEach(PerformanceMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.symbol).tag(mode)
                    }
                }
                Divider()
                Button {
                    model.setInputMode(touch: !model.touchMode)
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
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !model.playing)) { timeline in
                    SignalCanvas(
                        time: timeline.date.timeIntervalSinceReferenceDate,
                        playing: model.playing,
                        active: model.music.active,
                        demo: model.touchMode || !model.playing,
                        hands: model.handPoses,
                        mode: model.mode,
                        brightness: model.music.brightness + model.music.distortion + model.music.space * 0.5
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
            Menu {
                Picker("Sound", selection: $model.palette) {
                    ForEach(SoundPalette.allCases) { palette in
                        Label(palette.title.capitalized, systemImage: palette.symbol).tag(palette)
                    }
                }
            } label: {
                VStack(spacing: 7) {
                    Image(systemName: model.palette.symbol).font(.system(size: 23, weight: .ultraLight))
                    Text(model.palette.title.capitalized).font(.system(size: 11, weight: .medium))
                }.frame(width: satellite, height: satellite)
            }.airGlass(Circle()).accessibilityLabel("Sound: \(model.palette.title.capitalized)")
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
            if model.touchMode {
                Button { model.triggerWink(.left) } label: {
                    Image(systemName: model.mode == .drums ? "burst" : "eye")
                        .font(.system(size: 24, weight: .ultraLight)).frame(width: satellite, height: satellite)
                }.airGlass(Circle()).opacity(model.playing ? 1 : 0.35).disabled(!model.playing)
                    .accessibilityLabel(model.mode == .drums ? "Play cymbal" : "Play fart sample")
            } else {
                HStack(alignment: .center, spacing: 4) {
                    ForEach(0..<7) { _ in
                        Capsule().fill(.white.opacity(model.music.active ? 0.8 : 0.18))
                            .frame(width: 2, height: model.music.active ? 24 : 4)
                    }
                }.frame(width: satellite, height: satellite).accessibilityLabel(model.music.active ? "Sound active" : "Raise a hand to play")
            }
        }
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
                guideRow("hand.raised", "Left hand", "Height chooses the note or song key. Move sideways for octave. Angle the knuckles to muffle.")
                guideRow("hand.raised.fingers.spread", "Right hand", "Height controls tempo in Song and Drums. Angle the knuckles for distortion.")
                guideRow("viewfinder", "Palm plane", "Start flat and level to set neutral. Flip a palm upward to open the space effect.")
                guideRow("face.smiling", "Face", "Smile for shimmer. Open your mouth for vibrato.")
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

private struct SignalCanvas: View {
    let time: Double
    let playing: Bool
    let active: Bool
    let demo: Bool
    let hands: [HandPoseSample]
    let mode: PerformanceMode
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
            let color = Color.white
            let landscape = size.width > size.height
            let center = CGPoint(x: size.width / 2, y: size.height * (landscape ? 0.22 : 0.39))
            if demo { drawIdleField(context: &context, size: size, center: center, color: color) }

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
            context.fill(plane, with: .color(.white.opacity(0.025 + hand.zTilt * 0.09)))
            var axis = Path()
            axis.move(to: screen(index)); axis.addLine(to: screen(little))
            context.stroke(axis, with: .color(.white.opacity(0.5 + hand.xyRotation * 0.38)), lineWidth: 1.6)
        }
        for chain in fingerChains {
            var path = Path()
            var drawing = false
            for joint in chain {
                guard let point = hand[joint] else { drawing = false; continue }
                let p = screen(point)
                if drawing { path.addLine(to: p) } else { path.move(to: p); drawing = true }
            }
            context.stroke(path, with: .color(.white.opacity(0.72)), lineWidth: 1.05)
        }
        for joint in HandJoint.allCases {
            guard let point = hand[joint] else { continue }
            let p = screen(point)
            let tip = [.thumbTip, .indexTip, .middleTip, .ringTip, .littleTip].contains(joint)
            let radius: CGFloat = tip ? 2.8 : 1.45
            context.fill(Path(ellipseIn: CGRect(x: p.x-radius, y: p.y-radius, width: radius*2, height: radius*2)), with: .color(.white.opacity(tip ? 0.95 : 0.65)))
        }
        let position = screen(hand.center)
        let haloRadius = CGFloat(7 + hand.zTilt * 18)
        context.stroke(
            Path(ellipseIn: CGRect(x: position.x - haloRadius, y: position.y - haloRadius, width: haloRadius * 2, height: haloRadius * 2)),
            with: .color(.white.opacity(0.12 + hand.zTilt * 0.34)),
            lineWidth: 0.8
        )
        let label = handLabel(hand.side)
        context.draw(
            Text(label).font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(1.5).foregroundColor(.white),
            at: CGPoint(x: position.x, y: max(30, position.y - 54))
        )
    }

    private func handLabel(_ side: HandSide) -> String {
        switch mode {
        case .free: return side == .left ? "MELODY" : "DISTORT"
        case .song: return side == .left ? "MELODY" : "BASS · BEAT"
        case .drums: return side == .left ? "CYMBAL" : "KICK"
        }
    }

    private func drawIdleField(context: inout GraphicsContext, size: CGSize, center: CGPoint, color: Color) {
        let unit = min(size.width, size.height)
        for row in 0..<19 {
            let latitude = Double(row) / 18 * .pi
            let radius = sin(latitude)
            var line = Path()
            for col in 0...28 {
                let longitude = Double(col) / 28 * .pi
                let x = center.x + CGFloat(cos(longitude) * radius) * unit * 0.25
                let y = center.y + CGFloat(cos(latitude)) * unit * 0.21 + CGFloat(sin(longitude) * radius) * unit * 0.035
                let point = CGPoint(x: x, y: y)
                if col == 0 { line.move(to: point) } else { line.addLine(to: point) }
                if col.isMultiple(of: 2) {
                    context.fill(Path(ellipseIn: CGRect(x: x-0.7, y: y-0.7, width: 1.4, height: 1.4)), with: .color(color.opacity(playing ? 0.65 : 0.5)))
                }
            }
            context.stroke(line, with: .color(color.opacity(0.14)), lineWidth: 0.5)
        }
        for col in 0...14 {
            let longitude = Double(col) / 14 * .pi
            var line = Path()
            for row in 0...36 {
                let latitude = Double(row) / 36 * .pi
                let point = CGPoint(
                    x: center.x + CGFloat(cos(longitude) * sin(latitude)) * unit * 0.25,
                    y: center.y + CGFloat(cos(latitude)) * unit * 0.21 + CGFloat(sin(longitude) * sin(latitude)) * unit * 0.035
                )
                if row == 0 { line.move(to: point) } else { line.addLine(to: point) }
            }
            context.stroke(line, with: .color(color.opacity(0.12)), lineWidth: 0.5)
        }
    }
}
