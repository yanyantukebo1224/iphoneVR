import Foundation
import ARKit
import Vision
import Combine

class ARHandTrackerManager: NSObject, ARSessionDelegate, ObservableObject {
    let session = ARSession()
    private let handPoseRequest = VNDetectHumanHandPoseRequest()
    private let processingQueue = DispatchQueue(label: "com.iphonevr.vision.processing", qos: .userInteractive)

    @Published var headPosition: SIMD3<Float> = .zero
    @Published var headRotation: simd_quatf = simd_quatf(real: 1, imag: .zero)
    @Published var leftHandData: HandPacketData?
    @Published var rightHandData: HandPacketData?

    private var isLeftPinchingState: Bool = false
    private var isRightPinchingState: Bool = false

    var onTrackingDataUpdated: ((SIMD3<Float>, simd_quatf, HandPacketData?, HandPacketData?) -> Void)?

    override init() {
        super.init()
        handPoseRequest.maximumHandCount = 2
        session.delegate = self
    }

    func startTracking() {
        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravity
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }

    func stopTracking() {
        session.pause()
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let transform = frame.camera.transform
        let position = SIMD3<Float>(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
        let rotation = simd_quaternion(transform)

        DispatchQueue.main.async {
            self.headPosition = position
            self.headRotation = rotation
        }

        let pixelBuffer = frame.capturedImage
        processingQueue.async {
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
            do {
                try handler.perform([self.handPoseRequest])
                self.processHandObservation(results: self.handPoseRequest.results, frame: frame)
            } catch {
                print("Vision Hand Pose Error: \(error)")
            }
        }
    }

    private func processHandObservation(results: [VNHumanHandPoseObservation]?, frame: ARFrame) {
        guard let observations = results, !observations.isEmpty else {
            DispatchQueue.main.async {
                self.leftHandData = nil
                self.rightHandData = nil
            }
            onTrackingDataUpdated?(headPosition, headRotation, nil, nil)
            return
        }

        var newLeft: HandPacketData?
        var newRight: HandPacketData?

        for observation in observations {
            let chirality: UInt8 = (observation.chirality == .left) ? 0 : 1
            if let handData = extract21Joints(from: observation, chirality: chirality) {
                if chirality == 0 {
                    newLeft = handData
                } else {
                    newRight = handData
                }
            }
        }

        DispatchQueue.main.async {
            self.leftHandData = newLeft
            self.rightHandData = newRight
        }

        onTrackingDataUpdated?(headPosition, headRotation, newLeft, newRight)
    }

    private func extract21Joints(from observation: VNHumanHandPoseObservation, chirality: UInt8) -> HandPacketData? {
        guard let recognizedPoints = try? observation.recognizedPoints(.all) else { return nil }

        // ピンチ判定ヒステリシス
        var isPinching: UInt8 = 0
        var pinchDist: Float = 1.0

        let isLeft = (chirality == 0)
        var currentPinchState = isLeft ? isLeftPinchingState : isRightPinchingState

        if let thumbTip = recognizedPoints[.thumbTip], let indexTip = recognizedPoints[.indexTip] {
            let dx = Float(thumbTip.location.x - indexTip.location.x)
            let dy = Float(thumbTip.location.y - indexTip.location.y)
            pinchDist = sqrt(dx*dx + dy*dy)

            if currentPinchState {
                if pinchDist > 0.09 {
                    currentPinchState = false
                }
            } else {
                if pinchDist < 0.065 {
                    currentPinchState = true
                }
            }

            if isLeft {
                isLeftPinchingState = currentPinchState
            } else {
                isRightPinchingState = currentPinchState
            }

            isPinching = currentPinchState ? 1 : 0
        }

        let dummyBone = BoneTransform(position: Vector3f(x: 0, y: 0, z: 0), orientation: Quaternionf(w: 1, x: 0, y: 0, z: 0))
        var bones = Array(repeating: dummyBone, count: 21)

        let jointKeys: [VNHumanHandPoseObservation.JointName] = [
            .wrist,
            .thumbCMC, .thumbMP, .thumbIP, .thumbTip,
            .indexMCP, .indexPIP, .indexDIP, .indexTip,
            .middleMCP, .middlePIP, .middleDIP, .middleTip,
            .ringMCP, .ringPIP, .ringDIP, .ringTip,
            .littleMCP, .littlePIP, .littleDIP, .littleTip
        ]

        // 画面中心 (0.5, 0.5) を原点とした本格ダイナミック実質3D移動スケーリング
        for (idx, key) in jointKeys.enumerated() {
            if let point = recognizedPoints[key], point.confidence > 0.10 {
                let posX = Float(point.location.x - 0.5) * Float(1.8) // 画面左右運動
                let posY = Float(0.5 - point.location.y) * Float(1.8) // 画面上下運動
                let posZ = Float(0.0)

                bones[idx] = BoneTransform(
                    position: Vector3f(x: posX, y: posY, z: posZ),
                    orientation: Quaternionf(w: 1, x: 0, y: 0, z: 0)
                )
            }
        }

        let tupleJoints = (
            bones[0], bones[1], bones[2], bones[3], bones[4],
            bones[5], bones[6], bones[7], bones[8], bones[9],
            bones[10], bones[11], bones[12], bones[13], bones[14],
            bones[15], bones[16], bones[17], bones[18], bones[19], bones[20]
        )

        return HandPacketData(
            chirality: chirality,
            isTracked: 1,
            isPinching: isPinching,
            pinchDistance: pinchDist,
            joints: tupleJoints
        )
    }
}
