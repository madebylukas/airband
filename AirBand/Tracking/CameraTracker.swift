import ARKit
import Vision
import SwiftUI

struct TrackingSample {
    var hands: [CGPoint] = []
    var rotation: Double = 0
    var smile: Double = 0
    var jaw: Double = 0
    var leftEye: Double = 0
    var rightEye: Double = 0
    var faceTracked = false
    var time: TimeInterval = 0
}

final class CameraTracker: NSObject, ARSessionDelegate, ARSCNViewDelegate {
    let session = ARSession()
    var onSample: ((TrackingSample) -> Void)?
    var onFailure: ((String) -> Void)?
    var viewport = CGSize(width: 390, height: 480)
    private let visionQueue = DispatchQueue(label: "com.airband.hands", qos: .userInitiated)
    private var processing = false
    private var lastVision = 0.0
    private var lastHands = 0.0
    private var rotation = 0.0
    private var hands: [CGPoint] = []
    private var generation = 0
    private var running = false
    static var supported: Bool { ARFaceTrackingConfiguration.isSupported }

    override init() {
        super.init()
        session.delegate = self
        session.delegateQueue = .main
    }
    func start() {
        generation += 1
        hands = []; lastHands = 0
        running = true
        let configuration = ARFaceTrackingConfiguration()
        configuration.isLightEstimationEnabled = true
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }
    func stop() {
        running = false
        generation += 1
        session.pause()
        hands = []
    }
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard running else { return }
        let face = frame.anchors.compactMap { $0 as? ARFaceAnchor }.first
        var sample = TrackingSample()
        sample.time = frame.timestamp
        sample.faceTracked = face?.isTracked == true
        if let face, face.isTracked {
            sample.smile = max(face.blendShapes[.mouthSmileLeft]?.doubleValue ?? 0, face.blendShapes[.mouthSmileRight]?.doubleValue ?? 0)
            sample.jaw = face.blendShapes[.jawOpen]?.doubleValue ?? 0
            sample.leftEye = face.blendShapes[.eyeBlinkLeft]?.doubleValue ?? 0
            sample.rightEye = face.blendShapes[.eyeBlinkRight]?.doubleValue ?? 0
        }
        if frame.timestamp - lastHands > 0.3 { hands = [] }
        sample.hands = hands
        sample.rotation = hands.isEmpty ? 0 : rotation
        onSample?(sample)
        guard !processing, frame.timestamp - lastVision >= 1.0 / 15 else { return }
        processing = true
        lastVision = frame.timestamp
        let pixelBuffer = frame.capturedImage
        let transform = frame.displayTransform(for: .portrait, viewportSize: viewport)
        let selfViewport = viewport
        let timestamp = frame.timestamp
        let token = generation
        visionQueue.async { [weak self] in
            let request = VNDetectHumanHandPoseRequest()
            request.maximumHandCount = 2
            var positions: [CGPoint] = []
            var rotations: [Double] = []
            do {
                // Vision points and AR displayTransform both refer to the original buffer.
                try VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up).perform([request])
                for observation in request.results ?? [] {
                    let point = try observation.recognizedPoint(.indexMCP)
                    guard point.confidence > 0.35 else { continue }
                    let imagePoint = CGPoint(x: point.location.x, y: 1 - point.location.y)
                    let displayed = imagePoint.applying(transform)
                    guard displayed.x >= 0, displayed.x <= 1, displayed.y >= 0, displayed.y <= 1 else { continue }
                    positions.append(displayed)
                    let wrist = try observation.recognizedPoint(.wrist)
                    let knuckle = try observation.recognizedPoint(.middleMCP)
                    if wrist.confidence > 0.35 && knuckle.confidence > 0.35 {
                        let a = CGPoint(x: wrist.location.x, y: 1-wrist.location.y).applying(transform)
                        let b = CGPoint(x: knuckle.location.x, y: 1-knuckle.location.y).applying(transform)
                        // Scale to pixels so portrait aspect ratio does not skew the angle.
                        rotations.append(palmRotation(wrist: CGPoint(x: a.x*selfViewport.width, y: a.y*selfViewport.height), knuckle: CGPoint(x: b.x*selfViewport.width, y: b.y*selfViewport.height)))
                    }
                }
            } catch { positions = [] }
            let roll = rotations.isEmpty ? 0 : rotations.reduce(0, +) / Double(rotations.count)
            let result = positions.sorted { $0.x < $1.x }
            DispatchQueue.main.async {
                guard let self else { return }
                self.processing = false
                guard self.running, self.generation == token else { return }
                self.hands = result
                self.rotation = roll
                self.lastHands = timestamp
            }
        }
    }
    func session(_ session: ARSession, didFailWithError error: Error) {
        onFailure?("Camera tracking stopped. Tap Start to try again.")
    }
    func sessionWasInterrupted(_ session: ARSession) {
        onFailure?("Camera interrupted. Tap Start when you’re ready.")
    }
    func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
        guard anchor is ARFaceAnchor, let device = renderer.device,
              let geometry = ARSCNFaceGeometry(device: device, fillMesh: true) else { return nil }
        let material = geometry.firstMaterial!
        material.fillMode = .lines
        material.diffuse.contents = UIColor.white
        material.emission.contents = UIColor(white: 0.5, alpha: 1)
        material.lightingModel = .constant
        material.transparency = 0.48
        material.isDoubleSided = false
        return SCNNode(geometry: geometry)
    }
    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        guard let face = anchor as? ARFaceAnchor else { return }
        (node.geometry as? ARSCNFaceGeometry)?.update(from: face.geometry)
        node.isHidden = !face.isTracked
    }
}

struct CameraView: UIViewRepresentable {
    let tracker: CameraTracker
    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView(frame: .zero)
        view.session = tracker.session
        view.delegate = tracker
        view.automaticallyUpdatesLighting = false
        view.preferredFramesPerSecond = 30
        view.backgroundColor = .black
        return view
    }
    func updateUIView(_ uiView: ARSCNView, context: Context) {
        DispatchQueue.main.async {
            if uiView.bounds.width > 0 { tracker.viewport = uiView.bounds.size }
        }
    }
}
