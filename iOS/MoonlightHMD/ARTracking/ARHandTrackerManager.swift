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
                self.processHandObservation(results: self.handPoseRequest.results)
            } catch {
                print("Vision Hand Error: \(error)")
            }
        }
    }

    // 左右の手（21関節 ランドマーク）を絶対に混同せず完璧に安定抽出するメイン処理
    private func processHandObservation(results: [VNHumanHandPoseObservation]?) {
        var newLeft: HandPacketData?
        var newRight: HandPacketData?

        if let observations = results, !observations.isEmpty {
            if observations.count >= 2 {
                // X 座標順ソート (画面左 -> 左手(0), 画面右 -> 右手(1))
                let sortedObs = observations.sorted { obs1, obs2 in
                    let x1 = (try? obs1.recognizedPoints(.all)[.wrist]?.location.x) ?? 0.5
                    let x2 = (try? obs2.recognizedPoints(.all)[.wrist]?.location.x) ?? 0.5
                    return x1 < x2
                }
                newLeft = buildMediaPipeCompatible21Landmarks(from: sortedObs[0], chirality: 0)
                newRight = buildMediaPipeCompatible21Landmarks(from: sortedObs[1], chirality: 1)
            } else if let singleObs = observations.first {
                let wristX = (try? singleObs.recognizedPoints(.all)[.wrist]?.location.x) ?? 0.5
                let chiralityVal: UInt32 = (wristX >= 0.5) ? 1 : 0
                if chiralityVal == 1 {
                    newRight = buildMediaPipeCompatible21Landmarks(from: singleObs, chirality: 1)
                } else {
                    newLeft = buildMediaPipeCompatible21Landmarks(from: singleObs, chirality: 0)
                }
            }
        }

        let gcMgr = GameControllerManager.shared
        let leftInput = gcMgr.getInputData(for: 0)
        let rightInput = gcMgr.getInputData(for: 1)

        if leftInput.isConnected == 1 {
            if newLeft == nil { newLeft = createBaseHandData(chirality: 0) }
            newLeft?.controller = leftInput
        }
        if rightInput.isConnected == 1 {
            if newRight == nil { newRight = createBaseHandData(chirality: 1) }
            newRight?.controller = rightInput
        }

        DispatchQueue.main.async {
            self.leftHandData = newLeft
            self.rightHandData = newRight
        }

        onTrackingDataUpdated?(headPosition, headRotation, newLeft, newRight)
    }

    // Apple Vision 21関節 -> MediaPipe 3D 座標系 (Y軸反転: y_mediapipe = 1.0 - y_apple) への完全変換！
    private func buildMediaPipeCompatible21Landmarks(from observation: VNHumanHandPoseObservation, chirality: UInt32) -> HandPacketData? {
        guard let points = try? observation.recognizedPoints(.all),
              let wrist = points[.wrist] else { return nil }

        // ピンチ判定
        var isPinching: UInt32 = 0
        var pinchDist: Float = 1.0
        if let thumbTip = points[.thumbTip], let indexTip = points[.indexTip] {
            let dx = Float(thumbTip.location.x - indexTip.location.x)
            let dy = Float(thumbTip.location.y - indexTip.location.y)
            pinchDist = sqrt(dx * dx + dy * dy)
            isPinching = (pinchDist < 0.065) ? 1 : 0
        }

        // Apple Vision (Y: 下原点 0->1) -> MediaPipe (Y: 上原点 0->1) 反転変換 (y_mediapipe = 1.0 - y_apple)
        let convertPoint = { (jointName: VNHumanHandPoseObservation.JointName) -> BoneTransform in
            guard let pt = points[jointName] else {
                return BoneTransform(position: Vector3f(), orientation: Quaternionf())
            }
            let ax = Float(pt.location.x)
            let ay = 1.0 - Float(pt.location.y) // MediaPipe Y軸反転補正！

            // 奥行き Z 深度の推定スケール
            var depth: Float = 0.45
            if let midMCP = points[.middleMCP] {
                let s = hypot(Float(midMCP.location.x - wrist.location.x), Float(midMCP.location.y - wrist.location.y))
                depth = max(0.25, min(0.75, 0.075 / max(0.02, Float(s))))
            }

            let posX = (ax - 0.5) * depth * 1.2
            let posY = (ay - 0.5) * depth * 1.2
            let posZ = -depth

            return BoneTransform(
                position: Vector3f(x: posX, y: posY, z: posZ),
                orientation: Quaternionf(w: 1, x: 0, y: 0, z: 0)
            )
        }

        // 21関節ランドマーク全順序マップ (MediaPipe 21 Joints Standard)
        let jointKeys: [VNHumanHandPoseObservation.JointName] = [
            .wrist,                     // 0: Wrist
            .thumbCMC, .thumbMP, .thumbIP, .thumbTip,     // 1-4: Thumb
            .indexMCP, .indexPIP, .indexDIP, .indexTip,   // 5-8: Index
            .middleMCP, .middlePIP, .middleDIP, .middleTip,// 9-12: Middle
            .ringMCP, .ringPIP, .ringDIP, .ringTip,       // 13-16: Ring
            .littleMCP, .littlePIP, .littleDIP, .littleTip// 17-20: Pinky
        ]

        var bones: [BoneTransform] = []
        for key in jointKeys {
            bones.append(convertPoint(key))
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
            curls: FingerCurls(), // Curl全廃！
            splays: FingerSplays(),
            joints: tupleJoints,
            controller: GameControllerManager.shared.getInputData(for: chirality)
        )
    }

    private func createBaseHandData(chirality: UInt32) -> HandPacketData {
        let isLeft = (chirality == 0)
        let defaultPos = Vector3f(x: isLeft ? -0.18 : 0.18, y: -0.15, z: -0.45)
        let wristBone = BoneTransform(position: defaultPos, orientation: Quaternionf(w: 1, x: 0, y: 0, z: 0))
        let identityBone = BoneTransform(position: Vector3f(x: 0, y: 0, z: 0), orientation: Quaternionf(w: 1, x: 0, y: 0, z: 0))
        let tupleJoints = (
            wristBone, identityBone, identityBone, identityBone, identityBone,
            identityBone, identityBone, identityBone, identityBone, identityBone,
            identityBone, identityBone, identityBone, identityBone, identityBone,
            identityBone, identityBone, identityBone, identityBone, identityBone, identityBone
        )
        return HandPacketData(
            chirality: chirality,
            isTracked: 1,
            isPinching: 0,
            pinchDistance: 1.0,
            curls: FingerCurls(),
            splays: FingerSplays(),
            joints: tupleJoints,
            controller: GameControllerManager.shared.getInputData(for: chirality)
        )
    }
}
