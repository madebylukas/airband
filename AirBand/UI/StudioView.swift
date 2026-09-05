import SwiftUI

private let ink = Color(red: 0.015, green: 0.017, blue: 0.022)

struct StudioView: View {
    @StateObject private var model = StudioModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var showGuide = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ink.ignoresSafeArea()
                field.ignoresSafeArea(edges: .bottom)
                VStack(spacing: 0) {
                    header
                    Spacer()
                    if !model.playing {
                        VStack(spacing: 12) {
                            Text("Music.\nIn your hands.")
                                .font(.system(size: 43, weight: .light)).tracking(-1.8)
                                .multilineTextAlignment(.center)
                        }.padding(.bottom, geo.size.height * 0.10).allowsHitTesting(false)
                    }
                    if model.fartFlash {
                        Image(systemName: "wind").font(.system(size: 32, weight: .ultraLight))
                            .padding(20).airGlass(Circle()).transition(.scale.combined(with: .opacity))
                            .padding(.bottom, 22)
                    }
                    if model.music.active {
                        Text(model.music.noteName).font(.system(size: 28, weight: .ultraLight, design: .rounded))
                            .contentTransition(.numericText()).padding(.bottom, 24).allowsHitTesting(false)
                    }
                    if model.playing && model.touchMode {
                        HStack(spacing: 14) {
                            Image(systemName: "rotate.right").font(.system(size: 14, weight: .light)).foregroundStyle(.white.opacity(0.55))
                            Slider(value: $model.music.distortion, in: 0...1).tint(.white)
                                .accessibilityLabel("Hand rotation distortion")
                                .onChange(of: model.music.distortion) { _, _ in model.syncAudio() }
                        }.padding(.horizontal, 70).padding(.bottom, 12)
                    }
                    controls.padding(.bottom, 22)
                }.padding(.horizontal, 26).padding(.top, 8)
            }
        }
        .foregroundStyle(.white).preferredColorScheme(.dark)
        .sheet(isPresented: $showGuide) { guide }
        .alert("Session paused", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK", role: .cancel) { model.error = nil }
            if !model.touchMode {
                Button("Use Touch mode") { model.setMode(true) }
                Button("Settings") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
            }
        } message: { Text(model.error ?? "") }
        .onChange(of: scenePhase) { _, phase in if phase != .active { model.stop() } }
        .onChange(of: model.palette) { _, _ in model.syncAudio() }
    }

    private var header: some View {
        HStack {
            Text("airband").font(.system(size: 23, weight: .medium, design: .rounded)).tracking(-0.9)
            if model.playing && !model.touchMode {
                Circle().fill(model.faceTracked ? .white : .white.opacity(0.3)).frame(width: 5, height: 5)
                    .accessibilityLabel(model.faceTracked ? "Face tracking active" : "Looking for your face")
            }
            Spacer()
            Button { model.setMode(!model.touchMode) } label: {
                Image(systemName: model.touchMode ? "hand.draw" : "camera")
                    .font(.system(size: 17, weight: .regular)).frame(width: 44, height: 44)
            }.airGlass(Circle()).accessibilityLabel(model.touchMode ? "Touch mode. Switch to camera" : "Camera mode. Switch to touch")
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
                    RadialGradient(colors: [Color(white: 0.12), ink], center: UnitPoint(x: 0.5, y: 0.37), startRadius: 5, endRadius: geo.size.height*0.5)
                }
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !model.playing)) { timeline in
                    SignalCanvas(time: timeline.date.timeIntervalSinceReferenceDate,
                                 playing: model.playing, active: model.music.active,
                                 demo: model.touchMode || !model.playing,
                                 hands: model.hands, brightness: model.music.brightness + model.music.distortion,
                                 flash: model.fartFlash)
                }.allowsHitTesting(false)
                LinearGradient(colors: [.black.opacity(0.12), .clear, ink.opacity(0.95)], startPoint: .top, endPoint: .bottom).allowsHitTesting(false)
                if model.touchMode {
                    Color.clear.contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                model.touch(at: CGPoint(x: min(1, max(0, value.location.x / geo.size.width)), y: min(1, max(0, value.location.y / geo.size.height))))
                            }.onEnded { _ in model.endTouch() })
                        .accessibilityLabel("Instrument touch field")
                        .accessibilityHint("After starting, drag up for pitch and right for volume.")
                }
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 26) {
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
                }.frame(width: 76, height: 76)
            }.airGlass(Circle()).accessibilityLabel("Sound: \(model.palette.title.capitalized)")
            Button {
                if model.playing { model.stop() } else { Task { await model.start() } }
            } label: {
                ZStack {
                    Circle().stroke(.white.opacity(0.3), lineWidth: 1).frame(width: 88, height: 88)
                    Circle().fill(.white).frame(width: 72, height: 72)
                    if model.starting { ProgressView().tint(.black) }
                    else { Image(systemName: model.playing ? "stop.fill" : "play.fill")
                            .font(.system(size: 23, weight: .medium)).foregroundStyle(.black)
                            .offset(x: model.playing ? 0 : 2) }
                }
            }.disabled(model.starting).accessibilityIdentifier("transport")
                .accessibilityLabel(model.playing ? "Stop session" : "Start playing")
            if model.touchMode {
                Button { model.triggerFart() } label: {
                    Image(systemName: "eye").font(.system(size: 24, weight: .ultraLight)).frame(width: 76, height: 76)
                }.airGlass(Circle()).opacity(model.playing ? 1 : 0.35).disabled(!model.playing)
                    .accessibilityLabel("Wink: play fart sound")
            } else {
                // A passive meter balances the transport without another button.
                HStack(alignment: .center, spacing: 4) {
                    ForEach(0..<7) { index in
                        Capsule().fill(.white.opacity(model.music.active ? 0.8 : 0.18))
                            .frame(width: 2, height: model.music.active ? CGFloat(8 + Int(model.music.volume * 35) * (4-abs(index-3))/4) : 4)
                    }
                }.frame(width: 76, height: 76).accessibilityLabel(model.music.active ? "Sound active" : "Raise a hand to play")
            }
        }
    }

    private var guide: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 27) {
                HStack {
                    Text("A little movement.\nA lot of possibility.").font(.system(size: 29, weight: .light)).tracking(-0.6)
                    Spacer()
                    Button { showGuide = false } label: { Image(systemName: "xmark").frame(width: 40, height: 40) }.airGlass(Circle()).accessibilityLabel("Close guide")
                }
                Text("Prop your iPhone upright, an arm’s length away. Keep your face and hands in view, with light in front of you.")
                    .font(.system(size: 14)).foregroundStyle(.secondary)
                guideRow("hand.raised", "Raise", "Higher hands, higher notes. Always in key.")
                guideRow("arrow.left.and.right", "Spread", "Two hands apart for volume. Hands away for silence.")
                guideRow("rotate.right", "Rotate", "Tilt your palm sideways to add smooth distortion.")
                guideRow("face.smiling", "Express", "Smile for shimmer. Open your mouth for vibrato.")
                guideRow("eye", "Wink", "One eye closed. One deeply unserious sound.")
                Text("Touch mode: drag up for pitch, right for volume. The slider simulates palm rotation; the eye button simulates a wink.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                Label("Camera data stays on your iPhone.", systemImage: "lock.shield").font(.system(size: 11)).foregroundStyle(.secondary)
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
    let hands: [CGPoint]
    let brightness: Double
    let flash: Bool
    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            let color = flash ? Color(red: 1, green: 1, blue: 1) : Color.white
            let center = CGPoint(x: w/2, y: h*0.32)
            if demo {
                // Procedural sculpture in standby/touch mode. Actual face mesh is ARKit.
                for row in 0..<19 {
                    let latitude = Double(row) / 18 * .pi
                    let radius = sin(latitude)
                    var line = Path()
                    for col in 0...28 {
                        let longitude = Double(col) / 28 * .pi
                        let x = center.x + CGFloat(cos(longitude) * radius) * w * 0.21
                        let y = center.y + CGFloat(cos(latitude)) * h * 0.20 + CGFloat(sin(longitude)*radius) * h * 0.035
                        let p = CGPoint(x: x, y: y)
                        if col == 0 { line.move(to: p) } else { line.addLine(to: p) }
                        if col % 2 == 0 {
                            context.fill(Path(ellipseIn: CGRect(x: x-0.7, y: y-0.7, width: 1.4, height: 1.4)), with: .color(color.opacity(playing ? 0.65 : 0.5)))
                        }
                    }
                    context.stroke(line, with: .color(color.opacity(0.16)), lineWidth: 0.5)
                }
                for col in 0...14 {
                    let longitude = Double(col) / 14 * .pi
                    var line = Path()
                    for row in 0...36 {
                        let latitude = Double(row)/36 * .pi
                        let p = CGPoint(x: center.x + CGFloat(cos(longitude)*sin(latitude))*w*0.21,
                                        y: center.y + CGFloat(cos(latitude))*h*0.20 + CGFloat(sin(longitude)*sin(latitude))*h*0.035)
                        if row == 0 { line.move(to: p) } else { line.addLine(to: p) }
                    }
                    context.stroke(line, with: .color(color.opacity(0.14)), lineWidth: 0.5)
                }
                let ring = CGRect(x: center.x-w*0.32, y: center.y-h*0.25, width: w*0.64, height: h*0.50)
                context.stroke(Path(ellipseIn: ring), with: .color(color.opacity(0.12)), style: StrokeStyle(lineWidth: 0.6, dash: [3, 9]))
            }
            let start = hands.first.map { CGPoint(x: $0.x*w, y: $0.y*h) } ?? CGPoint(x: w*0.12, y: h*0.64)
            let end = hands.last.map { CGPoint(x: $0.x*w, y: $0.y*h) } ?? CGPoint(x: w*0.88, y: h*0.64)
            if hands.count >= 2 || demo {
                for strand in 0..<7 {
                    var path = Path()
                    for step in 0...100 {
                        let t = Double(step)/100
                        let amplitude = (active ? 22.0 + brightness*16 : 6) * sin(t * .pi)
                        let offset = sin(t*12 + (playing ? time*3 : 0) + Double(strand)*0.5)*amplitude
                        let p = CGPoint(x: start.x + (end.x-start.x)*t, y: start.y + (end.y-start.y)*t + offset)
                        if step == 0 { path.move(to: p) } else { path.addLine(to: p) }
                    }
                    context.stroke(path, with: .color(color.opacity(active ? 0.32 : 0.1)), lineWidth: strand == 3 ? 1.5 : 0.6)
                }
            }
            for hand in hands {
                let p = CGPoint(x: hand.x*w, y: hand.y*h)
                context.fill(Path(ellipseIn: CGRect(x: p.x-4, y: p.y-4, width: 8, height: 8)), with: .color(.white))
                for radius in [13.0, 22.0] {
                    context.stroke(Path(ellipseIn: CGRect(x: p.x-radius, y: p.y-radius, width: radius*2, height: radius*2)), with: .color(color.opacity(0.5)), lineWidth: 0.7)
                }
            }

        }
    }
}
