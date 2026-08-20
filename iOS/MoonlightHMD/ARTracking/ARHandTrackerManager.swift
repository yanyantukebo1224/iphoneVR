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
            // 一人称視点での確実な左右判定 (画面右側 = 右手, 画面左側 = 左手)
            if observations.count >= 2 {
                let sortedObs = observations.sorted { obs1, obs2 in
                    let x1 = (try? obs1.recognizedPoints(.all)[.wrist]?.location.x) ?? 0.5
                    let x2 = (try? obs2.recognizedPoints(.all)[.wrist]?.location.x) ?? 0.5
                    return x1 < x2
                }
                // Xが小さい方 (画面左) = 左手 (0), Xが大きい方 (画面右) = 右手 (1)
                newLeft = extract21Joints(from: sortedObs[0], chirality: 0)
                newRight = extract21Joints(from: sortedObs[1], chirality: 1)
            } else if let singleObs = observations.first {
                let wristX = (try? singleObs.recognizedPoints(.all)[.wrist]?.location.x) ?? 0.5
                let chirality: UInt32 = (wristX >= 0.5) ? 1 : 0
                if chirality == 1 {
                    newRight = extract21Joints(from: singleObs, chirality: 1)
                } else {
                    newLeft = extract21Joints(from: singleObs, chirality: 0)
                }
            }
        }

        // Switch / GameController 接続時の物理コントローラー入力をマージ
        let gcMgr = GameControllerManager.shared
        let leftInput = gcMgr.getInputData(for: 0)
        let rightInput = gcMgr.getInputData(for: 1)

        if newLeft == nil {
            var leftDummy = createDefaultHandData(chirality: 0)
            leftDummy.controller = leftInput
            leftDummy.isTracked = (leftInput.isConnected == 1) ? 1 : 0
            newLeft = leftDummy
        } else {
            newLeft?.controller = leftInput
        }

        if newRight == nil {
            var rightDummy = createDefaultHandData(chirality: 1)
            rightDummy.controller = rightInput
            rightDummy.isTracked = (rightInput.isConnected == 1) ? 1 : 0
            newRight = rightDummy
        } else {
            newRight?.controller = rightInput
        }

        DispatchQueue.main.async {
            self.leftHandData = newLeft
            self.rightHandData = newRight
        }

        onTrackingDataUpdated?(headPosition, headRotation, newLeft, newRight)
    }

    private func createDefaultHandData(chirality: UInt32) -> HandPacketData {
        let isLeft = (chirality == 0)
        let defaultPos = Vector3f(
            x: isLeft ? -0.18 : 0.18,
            y: -0.15,
            z: -0.42
        )
        let wristBone = BoneTransform(position: defaultPos, orientation: Quaternionf(w: 1, x: 0, y: 0, z: 0))
        let dummyBone = BoneTransform(position: Vector3f(x: 0, y: 0, z: 0), orientation: Quaternionf(w: 1, x: 0, y: 0, z: 0))
        let tupleJoints = (
            wristBone, dummyBone, dummyBone, dummyBone, dummyBone,
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

    private func extract21Joints(from observation: VNHumanHandPoseObservation, chirality: UInt32) -> HandPacketData? {
        guard let recognizedPoints = try? observation.recognizedPoints(.all),
              let wristPoint = recognizedPoints[.wrist] else { return nil }

        let isLeft = (chirality == 0)

        // 1. ピンチ検出
        var isPinching: UInt32 = 0
        var pinchDist: Float = 1.0
        var currentPinchState = isLeft ? isLeftPinchingState : isRightPinchingState

        if let thumbTip = recognizedPoints[.thumbTip], let indexTip = recognizedPoints[.indexTip] {
            let dx = Float(thumbTip.location.x - indexTip.location.x)
            let dy = Float(thumbTip.location.y - indexTip.location.y)
            pinchDist = sqrt(dx*dx + dy*dy)

            if currentPinchState {
                if pinchDist > 0.075 { currentPinchState = false }
            } else {
                if pinchDist < 0.045 { currentPinchState = true }
            }

            if isLeft {
                isLeftPinchingState = currentPinchState
            } else {
                isRightPinchingState = currentPinchState
            }
            isPinching = currentPinchState ? 1 : 0
        }

        // 2. ヘッドセット基準の素直な位置マッピング (Head-Relative 1:1 Mapping)
        // Vision正規化座標: x (0.0:左 ~ 1.0:右), y (0.0:下 ~ 1.0:上)
        // ↕️ 上下・左右の移動量を大幅強化 (ダイナミックな操作感)
        let deltaX = (Float(wristPoint.location.x) - 0.5) * Float(1.20)
        let deltaY = (Float(wristPoint.location.y) - 0.5) * Float(1.50)

        // 🚀 Z座標を圧倒的に前へ配置 (目の前 68cm: 操作しやすい自然な構え)
        let basePosX: Float = isLeft ? -0.18 : 0.18
        let basePosY: Float = -0.08
        let basePosZ: Float = -0.68

        let rawX = basePosX + deltaX
        let rawY = basePosY + deltaY
        let rawZ = basePosZ // 奥行き安定固定

        // EMA フィルタで自然な追従
        var targetWrist = SIMD3<Float>(rawX, rawY, rawZ)
        let alpha: Float = 0.50
        if isLeft {
            targetWrist = prevLeftWristPos * (1.0 - alpha) + targetWrist * alpha
            prevLeftWristPos = targetWrist
        } else {
            targetWrist = prevRightWristPos * (1.0 - alpha) + targetWrist * alpha
            prevRightWristPos = targetWrist
        }

        // 3. 🖐️ 指関節群 (21点) から手首の真の 3D 姿勢 (Pitch/Yaw/Roll) を幾何学合成
        var wristQuat = Quaternionf(w: 1, x: 0, y: 0, z: 0)
        
        let wx = Float(wristPoint.location.x)
        let wy = Float(wristPoint.location.y)
        
        let midMCP = recognizedPoints[.middleMCP]
        let idxMCP = recognizedPoints[.indexMCP]
        let litMCP = recognizedPoints[.littleMCP]
        
        if let mid = midMCP, let idx = idxMCP, let lit = litMCP {
            // Y軸基底: 手首 -> 中指付け根 (指先方向ベクトル)
            let fy = Float(mid.location.y) - wy
            let fx = Float(mid.location.x) - wx
            let fLen = max(0.001, hypot(fx, fy))
            let vForward = SIMD3<Float>(fx / fLen, fy / fLen, 0.0)

            // X軸基底: 人差し指付け根 -> 小指付け根 (手の甲横幅ベクトル)
            let px = Float(lit.location.x - idx.location.x)
            let py = Float(lit.location.y - idx.location.y)
            let pLen = max(0.001, hypot(px, py))
            let vRight = SIMD3<Float>((isLeft ? -px : px) / pLen, (isLeft ? -py : py) / pLen, 0.0)

            // Z軸基底 (手の甲の法線ベクトル): Forward × Right
            let vz = vForward.x * vRight.y - vForward.y * vRight.x
            let vNormal = SIMD3<Float>(0.0, 0.0, vz >= 0 ? 1.0 : -1.0)

            // 3次元クォータニオンの導出
            let roll = atan2(vForward.x, max(0.001, vForward.y))
            let pitch = Float(65.0 * .pi / 180.0)
            let yaw = atan2(vRight.y, max(0.001, vRight.x)) * 0.5

            let cr = cos(-roll * 0.5)
            let sr = sin(-roll * 0.5)
            let cp = cos(pitch * 0.5)
            let sp = sin(pitch * 0.5)
            let cy = cos(yaw * 0.5)
            let sy = sin(yaw * 0.5)

            wristQuat = Quaternionf(
                w: cp * cr * cy + sp * sr * sy,
                x: sp * cr * cy - cp * sr * sy,
                y: cp * sp * cy + sp * cp * sy,
                z: cp * cr * sy - sp * sr * cy
            )
        }

        // 4. 21 関節ボーンデータの構成
        let dummyBone = BoneTransform(position: Vector3f(x: 0, y: 0, z: 0), orientation: Quaternionf(w: 1, x: 0, y: 0, z: 0))
        var bones = Array(repeating: dummyBone, count: 21)

        // 手首（第0関節）
        bones[0] = BoneTransform(
            position: Vector3f(x: targetWrist.x, y: targetWrist.y, z: targetWrist.z),
            orientation: wristQuat
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
                let relX = Float(point.location.x - wristPoint.location.x) * Float(0.20)
                let relY = Float(point.location.y - wristPoint.location.y) * Float(0.20)
                let relZ = Float(0.0)

                bones[idx + 1] = BoneTransform(
                    position: Vector3f(x: relX, y: relY, z: relZ),
                    orientation: Quaternionf(w: 1, x: 0, y: 0, z: 0)
                )
            }
        }

        // 🖐️ 各指の個別 Curl（0.0: 完全全開/パー 〜 1.0: 完全握り/グー）
        let computeFingerCurl = { (mcpKey: VNHumanHandPoseObservation.JointName, tipKey: VNHumanHandPoseObservation.JointName) -> Float in
            guard let mcp = recognizedPoints[mcpKey], let tip = recognizedPoints[tipKey] else { return 0.0 }
            let dist = hypot(Float(tip.location.x - mcp.location.x), Float(tip.location.y - mcp.location.y))
            // 指を伸ばした時 (dist ≈ 0.16) -> 0.0, 曲げた時 (dist ≈ 0.04) -> 1.0
            let rawCurl = (0.15 - dist) / 0.10
            return max(0.0, min(1.0, rawCurl))
        }

        // 👍 親指の Curl (0.0: 直立・全開 〜 1.0: 手のひら折りたたみ)
        let computeThumbCurl = { () -> Float in
            guard let tip = recognizedPoints[.thumbTip], let indexMcp = recognizedPoints[.indexMCP] else { return 0.0 }
            let dist = hypot(Float(tip.location.x - indexMcp.location.x), Float(tip.location.y - indexMcp.location.y))
            let raw = (0.17 - dist) / 0.11
            return max(0.0, min(1.0, raw))
        }

        var curls = FingerCurls()
        curls.thumb = computeThumbCurl()
        curls.index = computeFingerCurl(.indexMCP, .indexTip)
        curls.middle = computeFingerCurl(.middleMCP, .middleTip)
        curls.ring = computeFingerCurl(.ringMCP, .ringTip)
        curls.pinky = computeFingerCurl(.littleMCP, .littleTip)

        // 👌 OKサイン判定
        var isOkPinch = false
        if let thbTip = recognizedPoints[.thumbTip], let idxTip = recognizedPoints[.indexTip] {
            let pDist = hypot(Float(thbTip.location.x - idxTip.location.x), Float(thbTip.location.y - idxTip.location.y))
            if pDist < 0.080 {
                isOkPinch = true
            }
        }

        if isPinching == 1 || isOkPinch {
            curls.thumb = 0.60
            curls.index = 0.65
            isPinching = 1
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


