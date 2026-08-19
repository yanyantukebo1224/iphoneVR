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
        var newLeft: HandPacketData?
        var newRight: HandPacketData?

        if let observations = results, !observations.isEmpty {
            for observation in observations {
                guard let recognizedPoints = try? observation.recognizedPoints(.all),
                      let wrist = recognizedPoints[.wrist] else { continue }

                let determinedChirality: UInt8 = (wrist.location.x <= 0.5) ? 0 : 1

                if let handData = extract21Joints(from: observation, chirality: determinedChirality, frame: frame) {
                    if determinedChirality == 0 {
                        newLeft = handData
                    } else {
                        newRight = handData
                    }
                }
            }
        }

        // Switch / GameController 接続時の物理コントローラー入力をマージ
        let gcMgr = GameControllerManager.shared
        if gcMgr.isConnected {
            if newLeft == nil {
                var leftDummy = createDefaultHandData(chirality: 0)
                leftDummy.controller = gcMgr.getInputData(for: 0)
                if leftDummy.controller.isConnected == 1 {
                    leftDummy.isTracked = 1
                    newLeft = leftDummy
                }
            } else {
                newLeft?.controller = gcMgr.getInputData(for: 0)
            }

            if newRight == nil {
                var rightDummy = createDefaultHandData(chirality: 1)
                rightDummy.controller = gcMgr.getInputData(for: 1)
                if rightDummy.controller.isConnected == 1 {
                    rightDummy.isTracked = 1
                    newRight = rightDummy
                }
            } else {
                newRight?.controller = gcMgr.getInputData(for: 1)
            }
        }

        DispatchQueue.main.async {
            self.leftHandData = newLeft
            self.rightHandData = newRight
        }

        onTrackingDataUpdated?(headPosition, headRotation, newLeft, newRight)
    }

    private func createDefaultHandData(chirality: UInt8) -> HandPacketData {
        let dummyBone = BoneTransform(position: Vector3f(x: 0, y: 0, z: 0), orientation: Quaternionf(w: 1, x: 0, y: 0, z: 0))
        let tupleJoints = (
            dummyBone, dummyBone, dummyBone, dummyBone, dummyBone,
            dummyBone, dummyBone, dummyBone, dummyBone, dummyBone,
            dummyBone, dummyBone, dummyBone, dummyBone, dummyBone,
            dummyBone, dummyBone, dummyBone, dummyBone, dummyBone, dummyBone
        )
        return HandPacketData(
            chirality: chirality,
            isTracked: 0,
            isPinching: 0,
            pinchDistance: 1.0,
            curls: FingerCurls(),
            splays: FingerSplays(),
            joints: tupleJoints,
            controller: ControllerInputData()
        )
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

        // HMD視野空間における線形正規化3Dマッピング
        let rawWristX = Float(wristPoint.location.x - 0.5) * Float(0.50)
        let rawWristY = Float(0.5 - wristPoint.location.y) * Float(0.50)
        let rawWristZ = Float(0.0)

        // EMA デュアルフィルタ (smooth alpha = 0.28)
        var targetWrist = SIMD3<Float>(rawWristX, rawWristY, rawWristZ)
        let alpha: Float = 0.28
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

        // 🖐️ 各指の個別 Curl（曲がり度合 0.0〜1.0）精密計算
        let computeFingerCurl = { (mcpKey: VNHumanHandPoseObservation.JointName, tipKey: VNHumanHandPoseObservation.JointName) -> Float in
            guard let mcp = recognizedPoints[mcpKey], let tip = recognizedPoints[tipKey] else { return 0.0 }
            let mcpDist = hypot(Float(mcp.location.x - wristPoint.location.x), Float(mcp.location.y - wristPoint.location.y))
            let tipDist = hypot(Float(tip.location.x - wristPoint.location.x), Float(tip.location.y - wristPoint.location.y))
            let maxSpan = mcpDist * 2.1
            let currentSpan = tipDist
            let curl = 1.0 - ((currentSpan - mcpDist) / (maxSpan - mcpDist))
            return max(0.0, min(1.0, curl))
        }

        var curls = FingerCurls()
        curls.thumb = computeFingerCurl(.thumbCMC, .thumbTip)
        curls.index = computeFingerCurl(.indexMCP, .indexTip)
        curls.middle = computeFingerCurl(.middleMCP, .middleTip)
        curls.ring = computeFingerCurl(.ringMCP, .ringTip)
        curls.pinky = computeFingerCurl(.littleMCP, .littleTip)

        if isPinching == 1 {
            curls.thumb = max(curls.thumb, 0.85)
            curls.index = max(curls.index, 0.90)
        }

        // 🖐️ 各指の Splay（指の開き角度 -1.0〜1.0）精密計算
        let computeFingerSplay = { (mcpKey: VNHumanHandPoseObservation.JointName, tipKey: VNHumanHandPoseObservation.JointName, refKey: VNHumanHandPoseObservation.JointName) -> Float in
            guard let tip = recognizedPoints[tipKey], let ref = recognizedPoints[refKey] else { return 0.0 }
            let dx = Float(tip.location.x - ref.location.x)
            let splay = (isLeft ? -1.0 : 1.0) * (dx * 5.0)
            return max(-1.0, min(1.0, splay))
        }

        var splays = FingerSplays()
        splays.thumb = computeFingerSplay(.thumbCMC, .thumbTip, .wrist)
        splays.index = computeFingerSplay(.indexMCP, .indexTip, .middleMCP)
        splays.middle = 0.0
        splays.ring = computeFingerSplay(.ringMCP, .ringTip, .middleMCP)
        splays.pinky = computeFingerSplay(.littleMCP, .littleTip, .ringMCP)

        let tupleJoints = (
            bones[0], bones[1], bones[2], bones[3], bones[4],
            bones[5], bones[6], bones[7], bones[8], bones[9],
            bones[10], bones[11], bones[12], bones[13], bones[14],
            bones[15], bones[16], bones[17], bones[18], bones[19], bones[20]
        )

        let controllerInput = GameControllerManager.shared.getInputData(for: chirality)

        return HandPacketData(
            chirality: chirality,
            isTracked: 1,
            isPinching: isPinching,
            pinchDistance: pinchDist,
            curls: curls,
            splays: splays,
            joints: tupleJoints,
            controller: controllerInput
        )
    }
}


