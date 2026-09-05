import ARKit
import Vision
import SwiftUI

struct TrackingSample {
    var hands: [HandPoseSample] = []
    var smile: Double = 0
    var jaw: Double = 0
    var leftEye: Double = 0
    var rightEye: Double = 0
    var faceTracked = false
    var time: TimeInterval = 0

    func hand(_ side: HandSide) -> HandPoseSample? { hands.first { $0.side == side } }
}

final class CameraTracker: NSObject, ARSessionDelegate, ARSCNViewDelegate {
    let session = ARSession()
    var onSample: ((TrackingSample) -> Void)?
    var onFailure: ((String) -> Void)?
    var viewport = CGSize(width: 390, height: 700)

    private let visionQueue = DispatchQueue(label: "com.airband.hands", qos: .userInitiated)
    private var processing = false
    private var lastVision = 0.0
    private var lastHands = 0.0
    private var hands: [HandPoseSample] = []
    private var filters = Dictionary(uniqueKeysWithValues: HandSide.allCases.map {
        ($0, Array(repeating: OneEuroPointFilter(), count: HandJoint.allCases.count))
    })
    private var lastFilteredPoints = Dictionary(uniqueKeysWithValues: HandSide.allCases.map {
        ($0, Array<CGPoint?>(repeating: nil, count: HandJoint.allCases.count))
    })
    private var lastJointSeen = Dictionary(uniqueKeysWithValues: HandSide.allCases.map {
        ($0, Array(repeating: -Double.infinity, count: HandJoint.allCases.count))
    })
    private var generation = 0
    private var running = false
    static var supported: Bool { ARFaceTrackingConfiguration.isSupported }

    private static let visionJoints: [VNHumanHandPoseObservation.JointName] = [
        .wrist,
        .thumbCMC, .thumbMP, .thumbIP, .thumbTip,
        .indexMCP, .indexPIP, .indexDIP, .indexTip,
        .middleMCP, .middlePIP, .middleDIP, .middleTip,
        .ringMCP, .ringPIP, .ringDIP, .ringTip,
        .littleMCP, .littlePIP, .littleDIP, .littleTip
    ]

    override init() {
        super.init()
        session.delegate = self
        session.delegateQueue = .main
    }

    func start() {
        generation += 1
        hands = []; lastHands = 0
        filters = Dictionary(uniqueKeysWithValues: HandSide.allCases.map {
            ($0, Array(repeating: OneEuroPointFilter(), count: HandJoint.allCases.count))
        })
        lastFilteredPoints = Dictionary(uniqueKeysWithValues: HandSide.allCases.map {
            ($0, Array<CGPoint?>(repeating: nil, count: HandJoint.allCases.count))
        })
        lastJointSeen = Dictionary(uniqueKeysWithValues: HandSide.allCases.map {
            ($0, Array(repeating: -Double.infinity, count: HandJoint.allCases.count))
        })
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
        if frame.timestamp - lastHands > 0.32 { hands = [] }
        sample.hands = hands
        onSample?(sample)

        guard !processing, frame.timestamp - lastVision >= 1.0 / 20 else { return }
        processing = true
        lastVision = frame.timestamp
        let pixelBuffer = frame.capturedImage
        let size = viewport
        let transform = frame.displayTransform(for: .portrait, viewportSize: size)
        let timestamp = frame.timestamp
        let token = generation

        visionQueue.async { [weak self] in
            guard let self else { return }
            let request = VNDetectHumanHandPoseRequest()
            request.maximumHandCount = 2
            var candidates: [(side: HandSide?, points: [CGPoint?], confidence: Float)] = []
            do {
                try VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up).perform([request])
                for observation in request.results ?? [] {
                    var points = Array<CGPoint?>(repeating: nil, count: HandJoint.allCases.count)
                    var confidence: Float = 0
                    for (index, name) in Self.visionJoints.enumerated() {
                        guard let point = try? observation.recognizedPoint(name), point.confidence > 0.28 else { continue }
                        let imagePoint = CGPoint(x: point.location.x, y: 1 - point.location.y)
                        let displayed = imagePoint.applying(transform)
                        guard displayed.x >= -0.06, displayed.x <= 1.06, displayed.y >= -0.06, displayed.y <= 1.06 else { continue }
                        points[index] = displayed
                        confidence += point.confidence
                    }
                    guard points.compactMap({ $0 }).count >= 7 else { continue }
                    let side: HandSide? = observation.chirality == .left ? .left : observation.chirality == .right ? .right : nil
                    candidates.append((side, points, confidence))
                }
            } catch {
                candidates = []
            }

            let assigned = Self.assignSides(candidates)
            var output: [HandPoseSample] = []
            for candidate in assigned {
                var smoothed = candidate.points
                guard var sideFilters = self.filters[candidate.side],
                      var previousPoints = self.lastFilteredPoints[candidate.side],
                      var seenTimes = self.lastJointSeen[candidate.side] else { continue }
                for index in smoothed.indices {
                    if let point = smoothed[index] {
                        smoothed[index] = sideFilters[index].update(point, time: timestamp)
                        previousPoints[index] = smoothed[index]
                        seenTimes[index] = timestamp
                    } else if timestamp - seenTimes[index] < 0.14 {
                        smoothed[index] = previousPoints[index]
                    }
                }
                self.filters[candidate.side] = sideFilters
                self.lastFilteredPoints[candidate.side] = previousPoints
                self.lastJointSeen[candidate.side] = seenTimes
                let wrist = smoothed[HandJoint.wrist.rawValue]
                let middle = smoothed[HandJoint.middleMCP.rawValue]
                let rawRotation: Double
                if let wrist, let middle {
                    rawRotation = palmRotation(
                        wrist: CGPoint(x: wrist.x * size.width, y: wrist.y * size.height),
                        knuckle: CGPoint(x: middle.x * size.width, y: middle.y * size.height)
                    )
                } else {
                    rawRotation = 0
                }
                let openness = Self.openness(of: smoothed)
                let expressiveRotation = rawRotation * (0.35 + 0.65 * openness)
                output.append(HandPoseSample(side: candidate.side, points: smoothed, rotation: expressiveRotation, openness: openness))
            }
            output.sort { $0.side == .left && $1.side == .right }

            DispatchQueue.main.async {
                self.processing = false
                guard self.running, self.generation == token else { return }
                if output.isEmpty {
                    if timestamp - self.lastHands > 0.32 { self.hands = [] }
                } else {
                    self.hands = output
                    self.lastHands = timestamp
                }
            }
        }
    }

    private static func assignSides(_ candidates: [(side: HandSide?, points: [CGPoint?], confidence: Float)]) -> [(side: HandSide, points: [CGPoint?])] {
        let strongest = candidates.sorted { $0.confidence > $1.confidence }.prefix(2)
        if strongest.count == 2,
           let left = strongest.first(where: { $0.side == .left }),
           let right = strongest.first(where: { $0.side == .right }) {
            return [(.left, left.points), (.right, right.points)]
        }
        let sorted = strongest.sorted { centerX($0.points) < centerX($1.points) }
        if sorted.count == 2 { return [(.left, sorted[0].points), (.right, sorted[1].points)] }
        guard let only = sorted.first else { return [] }
        let side = only.side ?? (centerX(only.points) < 0.5 ? .left : .right)
        return [(side, only.points)]
    }

    private static func centerX(_ points: [CGPoint?]) -> CGFloat {
        let visible = points.compactMap { $0 }
        return visible.isEmpty ? 0.5 : visible.map(\.x).reduce(0, +) / CGFloat(visible.count)
    }

    private static func openness(of points: [CGPoint?]) -> Double {
        guard let wrist = points[HandJoint.wrist.rawValue], let middle = points[HandJoint.middleMCP.rawValue] else { return 0 }
        let palm = max(0.01, hypot(middle.x - wrist.x, middle.y - wrist.y))
        let tips = [HandJoint.thumbTip, .indexTip, .middleTip, .ringTip, .littleTip].compactMap { points[$0.rawValue] }
        guard tips.count >= 3 else { return 0 }
        let extensionRatio = tips.map { hypot($0.x - wrist.x, $0.y - wrist.y) / palm }.reduce(0, +) / CGFloat(tips.count)
        return Double((extensionRatio - 1.35) / 1.25).clamped
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
        material.transparency = 0.45
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
