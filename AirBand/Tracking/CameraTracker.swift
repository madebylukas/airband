import ARKit
import AVFoundation
import simd
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
    var interfaceOrientation: UIInterfaceOrientation = .portrait

    private let visionQueue = DispatchQueue(label: "com.airband.hands", qos: .userInitiated)
    private let handRequest = VNDetectHumanHandPoseRequest()
    private let sequenceHandler = VNSequenceRequestHandler()
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
    private var velocities = Dictionary(uniqueKeysWithValues: HandSide.allCases.map {
        ($0, Array(repeating: CGVector.zero, count: HandJoint.allCases.count))
    })
    private var lastPoseTimes = Dictionary(uniqueKeysWithValues: HandSide.allCases.map { ($0, -Double.infinity) })
    private var zTilts = Dictionary(uniqueKeysWithValues: HandSide.allCases.map { ($0, 0.0) })
    private var lastDepthSeen = Dictionary(uniqueKeysWithValues: HandSide.allCases.map { ($0, -Double.infinity) })
    private var neutralPalmNormals: [HandSide: SIMD3<Float>] = [:]
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
        handRequest.maximumHandCount = 2
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
        velocities = Dictionary(uniqueKeysWithValues: HandSide.allCases.map {
            ($0, Array(repeating: CGVector.zero, count: HandJoint.allCases.count))
        })
        lastPoseTimes = Dictionary(uniqueKeysWithValues: HandSide.allCases.map { ($0, -Double.infinity) })
        zTilts = Dictionary(uniqueKeysWithValues: HandSide.allCases.map { ($0, 0.0) })
        lastDepthSeen = Dictionary(uniqueKeysWithValues: HandSide.allCases.map { ($0, -Double.infinity) })
        neutralPalmNormals = [:]
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

        guard !processing, frame.timestamp - lastVision >= 1.0 / 30 else { return }
        processing = true
        lastVision = frame.timestamp
        let pixelBuffer = frame.capturedImage
        let depthData = frame.capturedDepthData
        let size = viewport
        let orientation = interfaceOrientation == .unknown ? UIInterfaceOrientation.portrait : interfaceOrientation
        let transform = frame.displayTransform(for: orientation, viewportSize: size)
        let timestamp = frame.timestamp
        let token = generation

        visionQueue.async { [weak self] in
            guard let self else { return }
            var candidates: [(side: HandSide?, points: [CGPoint?], rawPoints: [CGPoint?], confidence: Float)] = []
            do {
                try self.sequenceHandler.perform([self.handRequest], on: pixelBuffer, orientation: .up)
                for observation in self.handRequest.results ?? [] {
                    var points = Array<CGPoint?>(repeating: nil, count: HandJoint.allCases.count)
                    var rawPoints = Array<CGPoint?>(repeating: nil, count: HandJoint.allCases.count)
                    var confidence: Float = 0
                    for (index, name) in Self.visionJoints.enumerated() {
                        guard let point = try? observation.recognizedPoint(name), point.confidence > 0.28 else { continue }
                        let imagePoint = CGPoint(x: point.location.x, y: 1 - point.location.y)
                        rawPoints[index] = imagePoint
                        let displayed = imagePoint.applying(transform)
                        guard displayed.x >= -0.06, displayed.x <= 1.06, displayed.y >= -0.06, displayed.y <= 1.06 else { continue }
                        points[index] = displayed
                        confidence += point.confidence
                    }
                    guard points.compactMap({ $0 }).count >= 7 else { continue }
                    let side: HandSide? = observation.chirality == .left ? .left : observation.chirality == .right ? .right : nil
                    candidates.append((side, points, rawPoints, confidence))
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
                      var seenTimes = self.lastJointSeen[candidate.side],
                      var sideVelocities = self.velocities[candidate.side] else { continue }
                let previousTime = self.lastPoseTimes[candidate.side] ?? -Double.infinity
                let dt = timestamp - previousTime
                for index in smoothed.indices {
                    if let point = smoothed[index] {
                        let filtered = sideFilters[index].update(point, time: timestamp)
                        if let previous = previousPoints[index], dt > 0, dt < 0.2 {
                            let measured = CGVector(
                                dx: (filtered.x - previous.x) / CGFloat(dt),
                                dy: (filtered.y - previous.y) / CGFloat(dt)
                            )
                            sideVelocities[index].dx = sideVelocities[index].dx * 0.58 + measured.dx * 0.42
                            sideVelocities[index].dy = sideVelocities[index].dy * 0.58 + measured.dy * 0.42
                            smoothed[index] = Self.predicted(filtered, velocity: sideVelocities[index], lead: min(0.028, dt * 0.55))
                        } else {
                            sideVelocities[index] = .zero
                            smoothed[index] = filtered
                        }
                        previousPoints[index] = filtered
                        seenTimes[index] = timestamp
                    } else if timestamp - seenTimes[index] < 0.14 {
                        smoothed[index] = previousPoints[index]
                    }
                }
                self.filters[candidate.side] = sideFilters
                self.lastFilteredPoints[candidate.side] = previousPoints
                self.lastJointSeen[candidate.side] = seenTimes
                self.velocities[candidate.side] = sideVelocities
                self.lastPoseTimes[candidate.side] = timestamp
                let indexKnuckle = smoothed[HandJoint.indexMCP.rawValue]
                let littleKnuckle = smoothed[HandJoint.littleMCP.rawValue]
                let xyRotation: Double
                if let indexKnuckle, let littleKnuckle {
                    xyRotation = palmXYRotation(
                        indexKnuckle: CGPoint(x: indexKnuckle.x * size.width, y: indexKnuckle.y * size.height),
                        littleKnuckle: CGPoint(x: littleKnuckle.x * size.width, y: littleKnuckle.y * size.height)
                    )
                } else {
                    xyRotation = 0
                }
                let openness = Self.openness(of: smoothed)
                var zTilt = self.zTilts[candidate.side] ?? 0
                if openness > 0.35,
                   let palmNormal = Self.palmNormal(rawPoints: candidate.rawPoints, depthData: depthData) {
                    if let neutral = self.neutralPalmNormals[candidate.side] {
                        let measured = relativePalmZTilt(normal: palmNormal, neutral: neutral)
                        zTilt += (measured - zTilt) * 0.32
                        self.lastDepthSeen[candidate.side] = timestamp
                    } else {
                        self.neutralPalmNormals[candidate.side] = palmNormal
                        zTilt = 0
                        self.lastDepthSeen[candidate.side] = timestamp
                    }
                } else if timestamp - (self.lastDepthSeen[candidate.side] ?? -Double.infinity) > 0.35 {
                    zTilt *= 0.9
                }
                self.zTilts[candidate.side] = zTilt
                output.append(HandPoseSample(
                    side: candidate.side,
                    points: smoothed,
                    xyRotation: xyRotation * (0.35 + 0.65 * openness),
                    zTilt: zTilt,
                    openness: openness
                ))
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

    private static func assignSides(
        _ candidates: [(side: HandSide?, points: [CGPoint?], rawPoints: [CGPoint?], confidence: Float)]
    ) -> [(side: HandSide, points: [CGPoint?], rawPoints: [CGPoint?])] {
        let strongest = candidates.sorted { $0.confidence > $1.confidence }.prefix(2)
        if strongest.count == 2,
           let left = strongest.first(where: { $0.side == .left }),
           let right = strongest.first(where: { $0.side == .right }) {
            return [(.left, left.points, left.rawPoints), (.right, right.points, right.rawPoints)]
        }
        let sorted = strongest.sorted { centerX($0.points) < centerX($1.points) }
        if sorted.count == 2 {
            return [(.left, sorted[0].points, sorted[0].rawPoints), (.right, sorted[1].points, sorted[1].rawPoints)]
        }
        guard let only = sorted.first else { return [] }
        let side = only.side ?? (centerX(only.points) < 0.5 ? .left : .right)
        return [(side, only.points, only.rawPoints)]
    }

    private static func predicted(_ point: CGPoint, velocity: CGVector, lead: Double) -> CGPoint {
        var dx = velocity.dx * CGFloat(lead)
        var dy = velocity.dy * CGFloat(lead)
        let distance = hypot(dx, dy)
        if distance > 0.035 {
            let scale = 0.035 / distance
            dx *= scale; dy *= scale
        }
        return CGPoint(
            x: min(1.06, max(-0.06, point.x + dx)),
            y: min(1.06, max(-0.06, point.y + dy))
        )
    }

    private static func palmNormal(rawPoints: [CGPoint?], depthData: AVDepthData?) -> SIMD3<Float>? {
        guard let depthData,
              let calibration = depthData.cameraCalibrationData,
              let wrist = rawPoints[HandJoint.wrist.rawValue],
              let index = rawPoints[HandJoint.indexMCP.rawValue],
              let middle = rawPoints[HandJoint.middleMCP.rawValue],
              let little = rawPoints[HandJoint.littleMCP.rawValue] else { return nil }

        let converted = depthData.depthDataType == kCVPixelFormatType_DepthFloat32
            ? depthData
            : depthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
        let map = converted.depthDataMap
        CVPixelBufferLockBaseAddress(map, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(map, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(map) else { return nil }
        let width = CVPixelBufferGetWidth(map)
        let height = CVPixelBufferGetHeight(map)
        let rowBytes = CVPixelBufferGetBytesPerRow(map)

        func depth(at point: CGPoint) -> Float? {
            let centerX = min(width - 1, max(0, Int(point.x * CGFloat(width))))
            let centerY = min(height - 1, max(0, Int(point.y * CGFloat(height))))
            var values: [Float] = []
            for y in max(0, centerY - 1)...min(height - 1, centerY + 1) {
                let row = base.advanced(by: y * rowBytes).assumingMemoryBound(to: Float.self)
                for x in max(0, centerX - 1)...min(width - 1, centerX + 1) {
                    let value = row[x]
                    if value.isFinite, value > 0.05, value < 4 { values.append(value) }
                }
            }
            guard !values.isEmpty else { return nil }
            values.sort()
            return values[values.count / 2]
        }

        let intrinsics = calibration.intrinsicMatrix
        let reference = calibration.intrinsicMatrixReferenceDimensions
        let fx = intrinsics.columns.0.x
        let fy = intrinsics.columns.1.y
        let cx = intrinsics.columns.2.x
        let cy = intrinsics.columns.2.y
        guard fx > 0, fy > 0, reference.width > 0, reference.height > 0 else { return nil }

        func point3D(_ point: CGPoint) -> SIMD3<Float>? {
            guard let z = depth(at: point) else { return nil }
            let u = Float(point.x * reference.width)
            let v = Float(point.y * reference.height)
            return SIMD3((u - cx) / fx * z, (v - cy) / fy * z, z)
        }

        guard let wrist3D = point3D(wrist),
              let index3D = point3D(index),
              let middle3D = point3D(middle),
              let little3D = point3D(little) else { return nil }
        let normal = simd_cross(little3D - index3D, middle3D - wrist3D)
        let length = simd_length(normal)
        guard length > 0.00001 else { return nil }
        return normal / length
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
            if let orientation = uiView.window?.windowScene?.interfaceOrientation, orientation != .unknown {
                tracker.interfaceOrientation = orientation
            }
        }
    }
}
