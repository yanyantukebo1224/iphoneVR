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

    private var prevLeftPos: SIMD3<Float> = SIMD3<Float>(-0.18, -0.15, -0.45)
    private var prevRightPos: SIMD3<Float> = SIMD3<Float>(0.18, -0.15, -0.45)

    private var prevLeftQuat: simd_quatf = simd_quatf(real: 1, imag: .zero)
    private var prevRightQuat: simd_quatf = simd_quatf(real: 1, imag: .zero)

    private var prevLeftCurls = FingerCurls()
    private var prevRightCurls = FingerCurls()

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

    private func processHandObservation(results: [VNHumanHandPoseObservation]?) {
        var newLeft: HandPacketData?
        var newRight: HandPacketData?

        if let observations = results, !observations.isEmpty {
            for obs in observations {
                let isRight = (obs.chirality == .right)
                let chiralityVal: UInt32 = isRight ? 1 : 0
                if isRight {
                    if newRight == nil {
                        newRight = buildCleanHandData(from: obs, chirality: chiralityVal)
                    }
                } else {
                    if newLeft == nil {
                        newLeft = buildCleanHandData(from: obs, chirality: chiralityVal)
                    }
                }
            }
        }

        let gcMgr = GameControllerManager.shared
        let leftInput = gcMgr.getInputData(for: 0)
        let rightInput = gcMgr.getInputData(for: 1)

        // Joy-Conコントローラーが接続されている場合：ボタン・スティック入力のみをセットし、指アニメーションはカメラトラッキングを100%優先
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

    // ゼロから新規構築した高精度＆絶対壊れないハンドポーズ抽出エンジン
    private func buildCleanHandData(from observation: VNHumanHandPoseObservation, chirality: UInt32) -> HandPacketData? {
        guard let points = try? observation.recognizedPoints(.all),
              let wrist = points[.wrist] else { return nil }

        let isLeft = (chirality == 0)

        // 1. ピンチ計算 (親指Tipと人差し指Tipの画面内相対距離)
        var isPinching: UInt32 = 0
        var pinchDist: Float = 1.0
        if let thumbTip = points[.thumbTip], let indexTip = points[.indexTip] {
            let dx = Float(thumbTip.location.x - indexTip.location.x)
            let dy = Float(thumbTip.location.y - indexTip.location.y)
            pinchDist = sqrt(dx * dx + dy * dy)
            isPinching = (pinchDist < 0.065) ? 1 : 0
        }

        // 2. 3D位置 (Position): 画面中央 (0.5, 0.5) からのオフセット
        let wx = Float(wrist.location.x)
        let wy = Float(wrist.location.y)

        // 手のひらスケールからカメラ奥行き (Depth: 0.3m 〜 0.7m) を算出
        var scale: Float = 0.15
        if let midMCP = points[.middleMCP] {
            scale = max(0.04, hypot(Float(midMCP.location.x) - wx, Float(midMCP.location.y) - wy))
        }
        let depth: Float = max(0.30, min(0.70, 0.070 / scale))

        let rawX: Float = (wx - 0.5) * depth * 1.2
        let rawY: Float = (wy - 0.5) * depth * 1.2
        let rawZ: Float = -depth

        let rawPos = SIMD3<Float>(rawX, rawY, rawZ)
        let prevP = isLeft ? prevLeftPos : prevRightPos
        let smoothPos = prevP * 0.4 + rawPos * 0.6
        if isLeft { prevLeftPos = smoothPos } else { prevRightPos = smoothPos }

        // 3. 3D回転 (Rotation): 手首 -> 中指MCP への標準クォータニオン
        var wristQuat = Quaternionf(w: 1, x: 0, y: 0, z: 0)
        if let midMCP = points[.middleMCP], let idxMCP = points[.indexMCP] {
            let fwd = SIMD3<Float>(Float(midMCP.location.x) - wx, Float(midMCP.location.y) - wy, -0.3).normalized
            let right = SIMD3<Float>(Float(idxMCP.location.x) - wx, Float(idxMCP.location.y) - wy, 0.0).normalized
            let up = simd_cross(right, fwd).normalized

            let rotMat = simd_float3x3(columns: (right, up, fwd))
            var q = simd_quatf(rotMat)
            if q.real.isNaN || q.imag.x.isNaN { q = simd_quatf(real: 1, imag: .zero) }

            let prevQ = isLeft ? prevLeftQuat : prevRightQuat
            let smoothQ = simd_slerp(prevQ, q, 0.5)
            if isLeft { prevLeftQuat = smoothQ } else { prevRightQuat = smoothQ }

            wristQuat = Quaternionf(w: smoothQ.real, x: smoothQ.imag.x, y: smoothQ.imag.y, z: smoothQ.imag.z)
        }

        // 4. 指の屈曲度 (Finger Curls: 0.0 = パー, 1.0 = グー)
        let calcCurl = { (mcpKey: VNHumanHandPoseObservation.JointName, tipKey: VNHumanHandPoseObservation.JointName) -> Float in
            guard let mcp = points[mcpKey], let tip = points[tipKey] else { return 0.0 }
            let dMCP = hypot(Float(mcp.location.x) - wx, Float(mcp.location.y) - wy)
            let dTip = hypot(Float(tip.location.x) - wx, Float(tip.location.y) - wy)
            // 手首から先端までの距離が手首からMCPまでの距離に近くなれば握っている
            let ratio = dTip / max(0.001, dMCP)
            let curl = (1.85 - ratio) / 1.0
            return max(0.0, min(1.0, curl))
        }

        var rawCurls = FingerCurls()
        rawCurls.thumb = calcCurl(.thumbMP, .thumbTip)
        rawCurls.index = calcCurl(.indexMCP, .indexTip)
        rawCurls.middle = calcCurl(.middleMCP, .middleTip)
        rawCurls.ring = calcCurl(.ringMCP, .ringTip)
        rawCurls.pinky = calcCurl(.littleMCP, .littleTip)

        let prevC = isLeft ? prevLeftCurls : prevRightCurls
        let smoothCurls = FingerCurls(
            thumb: prevC.thumb * 0.4 + rawCurls.thumb * 0.6,
            index: prevC.index * 0.4 + rawCurls.index * 0.6,
            middle: prevC.middle * 0.4 + rawCurls.middle * 0.6,
            ring: prevC.ring * 0.4 + rawCurls.ring * 0.6,
            pinky: prevC.pinky * 0.4 + rawCurls.pinky * 0.6
        )
        if isLeft { prevLeftCurls = smoothCurls } else { prevRightCurls = smoothCurls }

        // 5. 正準骨格 joints (手首のみ有効、残り20関節は安全な標準オフセット)
        let wristBone = BoneTransform(
            position: Vector3f(x: smoothPos.x, y: smoothPos.y, z: smoothPos.z),
            orientation: wristQuat
        )
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
            isPinching: isPinching,
            pinchDistance: pinchDist,
            curls: smoothCurls,
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

    private func applyControllerInput(handData: inout HandPacketData, input: ControllerInputData, isLeft: Bool) {
        handData.controller = input
        if input.isConnected == 1 {
            handData.curls.index = input.triggerValue
            handData.curls.middle = input.gripValue
            handData.curls.ring = input.gripValue
            handData.curls.pinky = input.gripValue
            let isThumbBusy = (input.buttonMask != 0) || (abs(input.stickX) > 0.08) || (abs(input.stickY) > 0.08)
            handData.curls.thumb = isThumbBusy ? 0.60 : 0.15
        }
    }
}

private extension SIMD3 where Scalar == Float {
    var normalized: SIMD3<Float> {
        let len = simd_length(self)
        return len > 0.0001 ? self / len : SIMD3<Float>(0, 0, 1)
    }
}
