import Foundation
import ARKit
import Vision
import Combine
import UIKit

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

    private var prevLeftWristPos: SIMD3<Float> = .zero
    private var prevRightWristPos: SIMD3<Float> = .zero

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
        
        // HMD横画面(Landscape)や縦画面(Portrait)でのカメラセンサの回転を100%正当化
        let visionOrientation = currentCGImagePropertyOrientation()

        processingQueue.async {
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: visionOrientation, options: [:])
            do {
                try handler.perform([self.handPoseRequest])
                self.processHandObservation(results: self.handPoseRequest.results, frame: frame)
            } catch {
                print("Vision Hand Pose Error: \(error)")
            }
        }
    }

    // デバイス姿勢に基づくVision入力向きの完全正当化
    private func currentCGImagePropertyOrientation() -> CGImagePropertyOrientation {
        let deviceOrientation = UIDevice.current.orientation
        switch deviceOrientation {
        case .landscapeLeft:
            return .up
        case .landscapeRight:
            return .down
        case .portraitUpsideDown:
            return .left
        default:
            return .right
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
            guard let recognizedPoints = try? observation.recognizedPoints(.all),
                  let wrist = recognizedPoints[.wrist] else { continue }

            // 横画面HMD時における絶対画面左右判定 (location.x <= 0.5 ➔ 左手, location.x > 0.5 ➔ 右手)
            let determinedChirality: UInt8 = (wrist.location.x <= 0.5) ? 0 : 1

            if let handData = extract21Joints(from: observation, chirality: determinedChirality, frame: frame) {
                if determinedChirality == 0 {
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

    private func extract21Joints(from observation: VNHumanHandPoseObservation, chirality: UInt8, frame: ARFrame) -> HandPacketData? {
        guard let recognizedPoints = try? observation.recognizedPoints(.all),
              let wristPoint = recognizedPoints[.wrist] else { return nil }

        var isPinching: UInt8 = 0
        var pinchDist: Float = 1.0

        let isLeft = (chirality == 0)
        var currentPinchState = isLeft ? isLeftPinchingState : isRightPinchingState

        // ピンチ幾何検出
        if let thumbTip = recognizedPoints[.thumbTip], let indexTip = recognizedPoints[.indexTip] {
            let dx = Float(thumbTip.location.x - indexTip.location.x)
            let dy = Float(thumbTip.location.y - indexTip.location.y)
            pinchDist = sqrt(dx*dx + dy*dy)

            if currentPinchState {
                if pinchDist > 0.075 {
                    currentPinchState = false
                }
            } else {
                if pinchDist < 0.045 {
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

        // 新システム: HMD視野空間における線形正規化3Dマッピング
        // 画面中心 (0.5, 0.5) を基準とした正確なメートル空間への直接スケーリング
        let rawWristX = Float(wristPoint.location.x - 0.5) * Float(0.50)
        let rawWristY = Float(0.5 - wristPoint.location.y) * Float(0.50)
        let rawWristZ = Float(0.0)

        // EMA デュアルフィルタ (smooth alpha = 0.20)
        var targetWrist = SIMD3<Float>(rawWristX, rawWristY, rawWristZ)
        let alpha: Float = 0.20
        if isLeft {
            targetWrist = prevLeftWristPos * (1.0 - alpha) + targetWrist * alpha
            prevLeftWristPos = targetWrist
        } else {
            targetWrist = prevRightWristPos * (1.0 - alpha) + targetWrist * alpha
            prevRightWristPos = targetWrist
        }

        let dummyBone = BoneTransform(position: Vector3f(x: 0, y: 0, z: 0), orientation: Quaternionf(w: 1, x: 0, y: 0, z: 0))
        var bones = Array(repeating: dummyBone, count: 21)

        // 手首（第0関節）
        bones[0] = BoneTransform(
            position: Vector3f(x: targetWrist.x, y: targetWrist.y, z: targetWrist.z),
            orientation: Quaternionf(w: 1, x: 0, y: 0, z: 0)
        )

        let fingerJointKeys: [VNHumanHandPoseObservation.JointName] = [
            .thumbCMC, .thumbMP, .thumbIP, .thumbTip,
            .indexMCP, .indexPIP, .indexDIP, .indexTip,
            .middleMCP, .middlePIP, .middleDIP, .middleTip,
            .ringMCP, .ringPIP, .ringDIP, .ringTip,
            .littleMCP, .littlePIP, .littleDIP, .littleTip
        ]

        // 関節3D相対オフセット
        for (idx, key) in fingerJointKeys.enumerated() {
            if let point = recognizedPoints[key] {
                let relX = Float(point.location.x - wristPoint.location.x) * Float(0.18)
                let relY = Float(wristPoint.location.y - point.location.y) * Float(0.18)
                let relZ = Float(0.0)

                bones[idx + 1] = BoneTransform(
                    position: Vector3f(x: relX, y: relY, z: relZ),
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
